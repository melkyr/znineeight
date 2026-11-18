// expedition.zig — UNDERSANDED M4 expedition loop (spec §5–§7, §11–§12).
//
// Pure: no I/O. Travel phases are advanced instantly at depart (1 dock action
// + travel cost) and on return (travel cost only, no arrival action). There is
// no persistent in-transit state. expeditionStep is the single entry: ongoing
// fights forward ACT_* verbs to game.gameStep and immediately run postFight
// (so a Hull-0 creature hit ascends at once); field actions use EXP_* values.
//
// Fight seeds use the §25.5 formula `exp.seed + fight_index*77`. startFightDef
// computes that from the *current* exp.fight_index, so the first fight is
// started with the 0-based index (0) and the count is advanced afterwards:
// a fight started as the Nth (1-based) fight therefore seeds with
// `exp.seed + (N-1)*77`, exactly as the task pinned.
//
// Flat state only (R1); module consts (R2); every switch has an else (R3).

const def = @import("def.zig");
const world = @import("world.zig");
const rng = @import("rng.zig");
const encounter = @import("encounter.zig");
const creatures = @import("creatures_t1.zig");
const tables = @import("tables_t1.zig");
const fight = @import("fight.zig");
const tools = @import("tools.zig");
const game = @import("game.zig");

// ---- Field actions --------------------------------------------------------
//
// Values 10..12 keep field actions disjoint from def.ACT_* (1..6), so a single
// expeditionStep entry can dispatch fight actions verbatim.

pub const EXP_HUNT: i32 = 10;
pub const EXP_REST: i32 = 11;
pub const EXP_SURFACE: i32 = 12;

// Bound on the expedition seed. fight.zig adds `fight_index*77` in u32; keeping
// the start seed under 2^24 leaves ample headroom for the whole 3..6 fight
// expedition and never traps under -fsafe.
const SEED_MASK: u32 = 0x00FFFFFF;

// Both fields are parked here whenever no fight is in progress. A fresh
// GameState is then never mistaken for an ongoing fight. `def_index` is also
// the single settled/pending marker: a pending Subdue keeps it live until
// resolveSubdueChoice clears it; every settled outcome clears it and leaves the
// Secured line to the CLS_SECURED log entry.
pub const NO_FIGHT: i32 = def.NO_FIGHT;

const REST_HEAL: i32 = 30;
const DOCK_REST_HEAL: i32 = 40;
const HEAVY_MIN_COST: i32 = 3;
const HEAVY_BONUS: i32 = 1;
const HEAVY_TIER: i32 = 3;

// Rough-sleep condition roll is 0..2 -> Drowsy/Shaky/Exposed (def ids 1..3).
const COND_ROLL_LO: i32 = 0;
const COND_ROLL_HI: i32 = 2;

// ---- Travel ---------------------------------------------------------------

fn zoneCost(zone: i32) i32 {
    if (zone < 0) return 0;
    if (@intCast(usize, zone) >= def.MAX_ZONES) return 0;
    return tables.ZONE_COST[@intCast(usize, zone)];
}

// Travel phases each way. Heavy (Hull T3 or Cargo T3) adds +1 on zones whose
// cost is already >= 3 (§6/§11).
pub fn travelPhases(g: *def.GameState, zone: i32) i32 {
    var cost = zoneCost(zone);
    if (cost >= HEAVY_MIN_COST) {
        if (g.world.boat[world.BOAT_HULL] == HEAVY_TIER or g.world.boat[world.BOAT_CARGO] == HEAVY_TIER) {
            cost += HEAVY_BONUS;
        }
    }
    return cost;
}

// ---- Rest -----------------------------------------------------------------

fn healNode(g: *def.GameState) void {
    var h = g.world.hull + REST_HEAL;
    const mx = world.hullMax(&g.world);
    if (h > mx) h = mx;
    if (h < 0) h = 0;
    g.world.hull = h;
}

// §5: Dock Rest always costs exactly one phase, even at full Hull. It is safe
// (no condition roll) and draws no RNG.
pub fn restAtDock(g: *def.GameState) void {
    var h = g.world.hull + DOCK_REST_HEAL;
    const mx = world.hullMax(&g.world);
    if (h > mx) h = mx;
    if (h < 0) h = 0;
    g.world.hull = h;
    world.advancePhase(&g.world);
}

// Empty pool check for the safe-Rest distinction (§5/§12). apportion does not
// draw RNG, so this is safe to call before a Rest.
fn poolEmpty(g: *def.GameState) bool {
    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    const n = encounter.apportion(&g.world, g.exp.zone, &defs, &weights);
    return n <= 0;
}

// ---- Loot hold ------------------------------------------------------------

// Keystones are drop-only, used as-is, and never receive the Cargo bonus.
fn isKeystone(part: i32) bool {
    return part == creatures.PART_HOOKED_BARBEL or part == creatures.PART_STEEL_FINS;
}

fn addDropLines(g: *def.GameState, lines: []const def.DropLine, cargo: i32) void {
    // Z98 lowers `g.exp.hold[i]` through a struct copy; go via a pointer so
    // the write reaches the real hold array.
    const ep = &g.exp;

    // Primary = first non-empty, non-keystone line. §7 Cargo adds to that line
    // only, not to every line.
    var primary: i32 = -1;
    var p: usize = 0;
    while (p < def.MAX_DROP_LINES and p < lines.len) : (p += 1) {
        if (lines[p].part <= 0 or lines[p].count <= 0) continue;
        if (isKeystone(lines[p].part)) continue;
        primary = @intCast(i32, p);
        break;
    }

    var i: usize = 0;
    while (i < def.MAX_DROP_LINES and i < lines.len) : (i += 1) {
        const part = lines[i].part;
        var count = lines[i].count;
        if (part <= 0 or count <= 0) continue;
        if (@intCast(usize, part) >= def.MAX_PARTS) continue;
        if (@intCast(i32, i) == primary) count += cargo;
        ep.hold[@intCast(usize, part)] += count;
    }
}

fn recountHold(g: *def.GameState) void {
    const ep = &g.exp;
    var n: i32 = 0;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (ep.hold[i] > 0) n += 1;
    }
    ep.hold_n = n;
}

// §7: Subdue/Kill/Overkill drop immediately into the hold. Flee/ascent add
// nothing. Cargo adds its current-tier count to the primary drop line only.
fn addLoot(g: *def.GameState, cdef: *const def.CreatureDef, outcome: i32) void {
    const cargo = world.cargoMax(&g.world);
    switch (outcome) {
        def.OUT_SUBDUE => addDropLines(g, cdef.sub[0..], cargo),
        def.OUT_KILL => addDropLines(g, cdef.kill[0..], cargo),
        def.OUT_OVERKILL => addDropLines(g, cdef.over[0..], cargo),
        else => return,
    }
    recountHold(g);
}

// ---- Fight state ----------------------------------------------------------

pub fn isInFight(g: *def.GameState) bool {
    return g.fight.def_index != NO_FIGHT and g.fight.outcome == def.OUT_ONGOING;
}

pub fn returnToDock(g: *def.GameState) void {
    if (g.exp.active == 0) return;
    const cost = travelPhases(g, g.exp.zone);
    var i: i32 = 0;
    while (i < cost) : (i += 1) {
        world.advancePhase(&g.world);
    }
    g.exp.active = 0;
}

// Escape a fight without recording a flee. Emergency Ascent is not a player
// flee, so its outcome must not drive renewal.
fn endAscent(g: *def.GameState) void {
    g.fight.outcome = NO_FIGHT;
    g.fight.def_index = NO_FIGHT;
}

// Record the settled outcome once. The log lives until startFightDef resets it
// for the next fight, and securedLine reads it back rather than fight state.
fn logSecured(g: *def.GameState, idx: i32, outcome: i32) void {
    fight.log(g, def.CLS_SECURED, def.MSG_SECURED, idx, outcome);
}

// Settle a fight once its outcome is resolved, or immediately when Hull hits 0
// while the fight is still technically ongoing (creatureAct leaves it that
// way). Returns true when the expedition ended (player flee or Hull-0 ascent).
// def_index == NO_FIGHT is the settled marker, so a second call is a no-op.
fn postFight(g: *def.GameState) bool {
    if (g.fight.def_index == NO_FIGHT) return false;
    const idx = g.fight.def_index;
    const outcome = g.fight.outcome;
    const zone = g.exp.zone;

    // Hull 0 is checked before outcome: M2's creatureAct zeroes Hull but leaves
    // the fight OUT_ONGOING, and ascent must end it immediately.
    if (g.fight.hull <= 0) {
        endAscent(g);
        g.world.hull = 0;
        world.advancePhase(&g.world);
        returnToDock(g);
        return true;
    }

    if (outcome == def.OUT_ONGOING) return false;

    if (outcome == def.OUT_PLAYER_FLED) {
        // Nothing from this fight; secured hold kept, +1 phase, return travel.
        g.world.hull = g.fight.hull;
        g.fight.def_index = NO_FIGHT;
        world.advancePhase(&g.world);
        returnToDock(g);
        return true;
    }

    if (outcome == def.OUT_CREATURE_FLED) {
        // No loot; subdue-length renewal; stay at the node. The log entry drives
        // the explicit `Secured: nothing` line.
        g.world.hull = g.fight.hull;
        logSecured(g, idx, outcome);
        world.markTaken(&g.world, zone, idx, def.OUT_CREATURE_FLED);
        g.fight.def_index = NO_FIGHT;
        return false;
    }

    if (outcome == def.OUT_SUBDUE) {
        // §7: loot is awarded as the fight ends, before Release/Sell. Keep the
        // def_index and outcome live as the pending-choice marker; renewal and
        // the choice settle in resolveSubdueChoice.
        var subdef = creatures.defAt(idx);
        addLoot(g, &subdef, outcome);
        logSecured(g, idx, outcome);
        g.world.hull = g.fight.hull;
        return false;
    }

    // Kill / Overkill: corpse or ruined table, renewal, then clear the marker.
    var cdef = creatures.defAt(idx);
    addLoot(g, &cdef, outcome);
    logSecured(g, idx, outcome);
    world.markTaken(&g.world, zone, idx, outcome);
    g.world.hull = g.fight.hull;
    g.fight.def_index = NO_FIGHT;
    return false;
}

// ---- Release / sell -------------------------------------------------------
//
// §9.7: both choices keep the parts and renew on the subdue index. Release also
// adds the node rare-chance bonus (+8 pp, cap +40) and marks the creature wary;
// Sell adds the creature's sale price in coins.
//
// Valid only while `fight.outcome == OUT_SUBDUE` and the pending marker
// (`def_index != NO_FIGHT`) is still live. The first valid call renews and
// resolves the choice; it then clears def_index, so a second call no-ops. The
// CLS_SECURED log entry written by postFight drives the node Secured line.

pub const SUB_RELEASE: i32 = 1;
pub const SUB_SELL: i32 = 2;

pub fn resolveSubdueChoice(g: *def.GameState, choice: i32) void {
    if (g.exp.active == 0) return;
    if (g.fight.outcome != def.OUT_SUBDUE) return;
    const idx = g.fight.def_index;
    if (idx == NO_FIGHT) return;
    if (idx < 0 or idx >= creatures.defCount()) return;

    const zone = g.exp.zone;
    switch (choice) {
        SUB_RELEASE => {
            world.markTaken(&g.world, zone, idx, def.OUT_SUBDUE);
            world.applyRelease(&g.world, zone, idx);
        },
        SUB_SELL => {
            world.markTaken(&g.world, zone, idx, def.OUT_SUBDUE);
            g.world.money += creatures.defAt(idx).sale;
        },
        else => return,
    }
    g.fight.def_index = NO_FIGHT;
}

// ---- Actions --------------------------------------------------------------

// Owned-tool bits are keyed by tool id (R6: tool 1..7 -> bit 1..7).
fn toolOwned(w: *const def.World, tool: i32) bool {
    if (tool < 1 or tool > 7) return false;
    const bit: u32 = @intCast(u32, tool);
    const mask: u32 = @intCast(u32, 1) << bit;
    return (w.tools_owned & mask) != 0;
}

fn toolKind(tool: i32) i32 {
    var i: usize = 0;
    while (i < tables.TOOLS.len) : (i += 1) {
        if (tables.TOOLS[i].id == tool) return tables.TOOLS[i].kind;
    }
    return -1;
}

// Zone milestones de-gray the 12 cosmetics (R12: `CosmeticRow.unlock` is a
// condition id, the stored bits are item indexes 0..11). Derelict bits stay 0
// until M11.
fn unlockZoneCosmetics(w: *def.World, zone: i32) void {
    var cond: i32 = 0;
    switch (zone) {
        0 => cond = tables.UNLOCK_Z1,
        1 => cond = tables.UNLOCK_Z2,
        2 => cond = tables.UNLOCK_Z3,
        else => return,
    }
    var i: usize = 0;
    while (i < tables.COSMETICS.len) : (i += 1) {
        if (tables.COSMETICS[i].unlock != cond) continue;
        const bit: u32 = @intCast(u32, i);
        w.cosmetics_unlocked = w.cosmetics_unlocked | (@intCast(u32, 1) << bit);
    }
}

pub fn depart(g: *def.GameState, zone: i32) *def.Expedition {
    const ep = &g.exp;
    ep.active = 1;
    ep.zone = zone;
    ep.fight_index = 0;
    // Bound the drawn seed (see SEED_MASK): fight.zig adds `fight_index*77`
    // in u32, and a full-range seed would trap under -fsafe.
    ep.seed = rng.rngNext(&g.world.rng_state) & SEED_MASK;

    // P22.4: the hold is the persistent dock parts store, kept across depart.
    // P22.5/R6: copy the selected tool, charging activated tools once.
    var selected = g.world.tool_selected;
    if (!toolOwned(&g.world, selected)) selected = 0;
    ep.tool = selected;
    ep.tool_charge = 0;
    if (selected != 0 and toolKind(selected) == tables.TOOL_KIND_ACTIVATED) {
        ep.tool_charge = 1;
    }
    ep.tool_broken = 0;

    g.log_n = 0;
    unlockZoneCosmetics(&g.world, zone);

    g.fight.def_index = NO_FIGHT;
    g.fight.outcome = def.OUT_ONGOING;
    g.pending_cond = def.COND_NONE;

    // Depart = 1 dock action + travel cost, advanced instantly (§6).
    const phases = 1 + travelPhases(g, zone);
    var p: i32 = 0;
    while (p < phases) : (p += 1) {
        world.advancePhase(&g.world);
    }
    return &g.exp;
}

fn hunt(g: *def.GameState) void {
    if (isInFight(g)) return;
    if (g.exp.fight_index >= world.maxFights(&g.world)) return;

    var idx: i32 = NO_FIGHT;
    if (!encounter.rollEncounter(&g.world, g.exp.zone, &idx)) return;
    if (idx < 0) return;

    world.markSeen(&g.world, idx);

    // startFightDef resets pending_cond, so capture the rough-sleep condition
    // first and copy it into the fight after the fight is initialised.
    const saved_cond = g.pending_cond;
    var cdef = creatures.defAt(idx);

    // 0-based fight index at call time: seed = exp.seed + index*77.
    fight.startFightDef(g, idx, &cdef, creatures.RULES[0..]);
    g.exp.fight_index += 1;

    g.fight.cond = saved_cond;
    g.pending_cond = def.COND_NONE;
    g.fight.hull = g.world.hull;
    g.fight.max_hull = world.hullMax(&g.world);

    // §11 loadout: Speed and Precision tiers feed the fight math directly.
    g.fight.player_speed = world.speedMax(&g.world);
    g.fight.margin_pct = world.precisionMargin(&g.world);

    // P22.5 tool lifecycle: copy the expedition tool state. A working rigged
    // tool is always on; activated tools wait for EQUIP. Charge and breakage
    // stay expedition-scoped.
    g.fight.tool = g.exp.tool;
    g.fight.tool_charge = g.exp.tool_charge;
    g.fight.tool_broken = g.exp.tool_broken;
    g.fight.tool_active = 0;
    if (g.fight.tool != 0 and g.fight.tool_broken == 0 and tools.isRigged(g.fight.tool)) {
        g.fight.tool_active = 1;
    }

    const wary = world.consumeWariness(&g.world, idx);
    g.fight.max_res += wary;
    g.fight.res += wary;

    // §10 grudge: run-scoped family overkill raises this fight's stats.
    fight.applyGrudge(g, &cdef, g.world.family_overkill_mask);
}

fn restAtNode(g: *def.GameState) void {
    if (isInFight(g)) return;

    // Availability depends on cycle/phase, so decide before advancing: the
    // Rest's own phase step must not turn a non-empty pool into a safe Rest.
    const empty = poolEmpty(g);
    healNode(g);
    world.advancePhase(&g.world);

    // Node Rest is penalised; empty-pool Rest is safe (§5).
    if (!empty) {
        const roll = rng.rngRange(&g.world.rng_state, COND_ROLL_LO, COND_ROLL_HI);
        g.pending_cond = def.COND_DROWSY + roll;
    }
}

pub fn expeditionStep(g: *def.GameState, action: i32) void {
    if (g.exp.active == 0) return;

    // Pending Subdue choice (§7/§9.7): loot is already in the hold, so only
    // Release/Sell may settle. Every field and fight action is refused here
    // before any phase or rng draw.
    if (g.fight.outcome == def.OUT_SUBDUE and g.fight.def_index != NO_FIGHT) {
        switch (action) {
            SUB_RELEASE, SUB_SELL => resolveSubdueChoice(g, action),
            else => {},
        }
        return;
    }

    // Single entry: while a fight is ongoing, actions 1..6 are def.ACT_*
    // verbs routed straight to game.gameStep. Run postFight immediately even
    // when the creature's attack just zeroed Hull mid-fight.
    if (isInFight(g)) {
        if (action >= def.ACT_STRIKE and action <= def.ACT_DECLINE) {
            game.gameStep(g, def.Action{ .kind = action, .arg = 0 });
        }
        _ = postFight(g);
        return;
    }

    // A resolved fight may be waiting (e.g. an external gameStep or a test);
    // settle it before applying a field action.
    if (g.fight.def_index >= 0) {
        if (postFight(g)) return;
    }

    switch (action) {
        EXP_HUNT => hunt(g),
        EXP_REST => restAtNode(g),
        EXP_SURFACE => returnToDock(g),
        else => {},
    }
}
