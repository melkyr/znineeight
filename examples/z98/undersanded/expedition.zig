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
// GameState is then never mistaken for an ongoing fight.
const NO_FIGHT: i32 = -1;

const REST_HEAL: i32 = 30;
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
    return g.fight.outcome == def.OUT_ONGOING;
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

// Settle a fight once its outcome is resolved, or immediately when Hull hits 0
// while the fight is still technically ongoing (creatureAct leaves it that
// way). Returns true when the expedition ended (player flee or Hull-0 ascent).
fn postFight(g: *def.GameState) bool {
    if (g.fight.def_index < 0) return false;
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
        // No loot; subdue-length renewal; stay at the node.
        g.world.hull = g.fight.hull;
        world.markTaken(&g.world, zone, idx, def.OUT_CREATURE_FLED);
        g.fight.def_index = NO_FIGHT;
        return false;
    }

    var cdef = creatures.defAt(idx);
    addLoot(g, &cdef, outcome);
    world.markTaken(&g.world, zone, idx, outcome);
    g.world.hull = g.fight.hull;
    g.fight.def_index = NO_FIGHT;
    return false;
}

// ---- Actions --------------------------------------------------------------

pub fn depart(g: *def.GameState, zone: i32) *def.Expedition {
    const ep = &g.exp;
    ep.active = 1;
    ep.zone = zone;
    ep.fight_index = 0;
    // Bound the drawn seed (see SEED_MASK): fight.zig adds `fight_index*77`
    // in u32, and a full-range seed would trap under -fsafe.
    ep.seed = rng.rngNext(&g.world.rng_state) & SEED_MASK;
    ep.hold_n = 0;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        ep.hold[i] = 0;
    }

    g.fight.def_index = NO_FIGHT;
    g.fight.outcome = NO_FIGHT;
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

    const wary = world.consumeWariness(&g.world, idx);
    g.fight.max_res += wary;
    g.fight.res += wary;
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
