// expedition.zig — UNDERSANDED M4 expedition loop (spec §5–§7, §11–§12).
//
// Pure: no I/O. Travel phases are advanced instantly at depart (1 dock action
// + travel cost) and on return (travel cost only, no arrival action). There is
// no persistent in-transit state. Fights are driven through game.gameStep;
// expeditionStep settles a finished fight at entry, then applies the requested
// field action.
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

// ---- Field actions --------------------------------------------------------

pub const EXP_HUNT: i32 = 1;
pub const EXP_REST: i32 = 2;
pub const EXP_SURFACE: i32 = 3;

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

fn addDropLines(g: *def.GameState, lines: []const def.DropLine) void {
    // Z98 lowers `g.exp.hold[i]` through a struct copy; go via a pointer so
    // the write reaches the real hold array.
    const ep = &g.exp;
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        const part = lines[i].part;
        const count = lines[i].count;
        if (part <= 0 or count <= 0) continue;
        if (@intCast(usize, part) >= def.MAX_PARTS) continue;
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
// nothing. Cargo's primary-line bonus is a later (M5) concern.
fn addLoot(g: *def.GameState, cdef: *const def.CreatureDef, outcome: i32) void {
    switch (outcome) {
        def.OUT_SUBDUE => addDropLines(g, cdef.sub[0..]),
        def.OUT_KILL => addDropLines(g, cdef.kill[0..]),
        def.OUT_OVERKILL => addDropLines(g, cdef.over[0..]),
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

fn hasPendingFight(g: *def.GameState) bool {
    if (g.exp.active != 1) return false;
    if (g.fight.def_index < 0) return false;
    if (g.fight.outcome == def.OUT_ONGOING and g.fight.hull > 0) return false;
    return true;
}

// Settle one finished fight. Returns true when the expedition ended (player
// flee or Hull-0 ascent); false when play continues at the node.
fn settleFight(g: *def.GameState) bool {
    const idx = g.fight.def_index;
    const outcome = g.fight.outcome;
    const zone = g.exp.zone;
    var cdef = creatures.defAt(idx);

    // Hull persists across fights; copy the per-fight value back first so the
    // ascent check sees the real damage.
    g.world.hull = g.fight.hull;

    if (outcome == def.OUT_PLAYER_FLED or g.world.hull <= 0) {
        // Player flee / Emergency Ascent: nothing from the current fight,
        // secured hold kept, +1 phase, then normal return travel.
        world.advancePhase(&g.world);
        g.fight.def_index = NO_FIGHT;
        returnToDock(g);
        return true;
    }

    addLoot(g, &cdef, outcome);
    world.markTaken(&g.world, zone, idx, outcome);
    g.fight.def_index = NO_FIGHT;
    return false;
}

// ---- Actions --------------------------------------------------------------

pub fn depart(g: *def.GameState, zone: i32) *def.Expedition {
    const ep = &g.exp;
    ep.active = 1;
    ep.zone = zone;
    ep.fight_index = 0;
    ep.seed = rng.rngNext(&g.world.rng_state);
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
    if (!encounter.rollEncounter(&g.world, g.exp.zone, &idx)) {
        // Empty pool -> safe Rest: heal, no rough-sleep, no extra phase.
        healNode(g);
        return;
    }
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
    healNode(g);
    world.advancePhase(&g.world);

    // Node Rest is penalised; empty-pool Rest is safe (§5).
    if (!poolEmpty(g)) {
        const roll = rng.rngRange(&g.world.rng_state, COND_ROLL_LO, COND_ROLL_HI);
        g.pending_cond = def.COND_DROWSY + roll;
    }
}

pub fn expeditionStep(g: *def.GameState, action: i32) void {
    if (g.exp.active == 0) return;

    if (hasPendingFight(g)) {
        const ended = settleFight(g);
        if (ended) return;
    }

    // Ongoing fights are driven by game.gameStep; field actions wait.
    if (isInFight(g)) return;

    switch (action) {
        EXP_HUNT => hunt(g),
        EXP_REST => restAtNode(g),
        EXP_SURFACE => returnToDock(g),
        else => {},
    }
}
