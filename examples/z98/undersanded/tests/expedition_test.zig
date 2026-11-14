// expedition_test.zig — UNDERSANDED M4 Task 3 expedition-loop tests.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/expedition_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/expedition_test"
//   "$OUT/expedition_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const rng = @import("../rng.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");
const expedition = @import("../expedition.zig");

var fails: usize = 0;

fn report(name: []const u8, ok: bool) void {
    if (ok) {
        io.write("ok - ");
    } else {
        io.write("FAIL - ");
        fails += 1;
    }
    io.write(name);
    io.write("\n");
}

fn newGame() def.GameState {
    var g: def.GameState = undefined;
    game.zeroWorld(&g.world);
    g.exp.active = 0;
    g.exp.zone = 0;
    g.exp.fight_index = 0;
    g.exp.seed = 0;
    const ep = &g.exp;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        ep.hold[i] = 0;
    }
    g.exp.hold_n = 0;
    g.pending_cond = def.COND_NONE;
    g.log_n = 0;
    g.screen = 0;
    g.fight.def_index = -1;
    g.fight.outcome = -1;
    g.fight.hull = 0;
    return g;
}

fn killCurrent(g: *def.GameState) void {
    g.fight.hp = 1;
    game.gameStep(g, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });
}

fn fleeCreature(g: *def.GameState) void {
    g.fight.pending_flee = 1;
    game.gameStep(g, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });
}

fn copyHold(dst: *[def.MAX_PARTS]i32, src: *const [def.MAX_PARTS]i32) void {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) dst[i] = src[i];
}

fn holdEqual(a: *const [def.MAX_PARTS]i32, b: *const [def.MAX_PARTS]i32) bool {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn holdNonZero(h: *const [def.MAX_PARTS]i32) bool {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (h[i] > 0) return true;
    }
    return false;
}

fn holdAllZero(h: *const [def.MAX_PARTS]i32) bool {
    return !holdNonZero(h);
}

fn hasDeathDrops(idx: i32) bool {
    const d = creatures.defAt(idx);
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        if (d.kill[i].part > 0 and d.kill[i].count > 0) return true;
        if (d.over[i].part > 0 and d.over[i].count > 0) return true;
    }
    return false;
}

// Deterministically find an rng_state whose first Z2 hunt lands on a creature
// with kill/overkill drops, so hold assertions are non-vacuous.
fn dropGame() def.GameState {
    var tries: u32 = 1;
    while (tries < 500) : (tries += 1) {
        var g = newGame();
        const gp = &g.world;
        gp.rng_state = tries;
        _ = expedition.depart(&g, 1);
        expedition.expeditionStep(&g, expedition.EXP_HUNT);
        const idx = g.fight.def_index;
        if (idx >= 0 and hasDeathDrops(idx)) return g;
    }
    return newGame();
}

fn expectedSeed(seed: u32, index: i32) u32 {
    var s: u32 = seed;
    const off: u32 = @intCast(u32, index) * @intCast(u32, 77);
    rng.rngSeed(&s, seed + off);
    return s;
}

fn findDefIndex(id: i32) i32 {
    var i: i32 = 0;
    while (i < creatures.defCount()) : (i += 1) {
        if (creatures.defAt(i).id == id) return i;
    }
    return -1;
}

fn isKeystone(part: i32) bool {
    return part == creatures.PART_HOOKED_BARBEL or part == creatures.PART_STEEL_FINS;
}

fn expectedDropHold(h: *[def.MAX_PARTS]i32, lines: []const def.DropLine, cargo: i32) void {
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) h[i] = 0;

    var primary: i32 = -1;
    var p: usize = 0;
    while (p < def.MAX_DROP_LINES and p < lines.len) : (p += 1) {
        if (lines[p].part <= 0 or lines[p].count <= 0) continue;
        if (isKeystone(lines[p].part)) continue;
        primary = @intCast(i32, p);
        break;
    }

    i = 0;
    while (i < def.MAX_DROP_LINES and i < lines.len) : (i += 1) {
        const part = lines[i].part;
        var count = lines[i].count;
        if (part <= 0 or count <= 0) continue;
        if (@intCast(usize, part) >= def.MAX_PARTS) continue;
        if (@intCast(i32, i) == primary) count += cargo;
        h[@intCast(usize, part)] += count;
    }
}

// Start a real expedition fight, then retarget its def index so drop-table
// assertions land on a known creature.
fn startedGame(idx: i32) def.GameState {
    var g = newGame();
    _ = expedition.depart(&g, 0);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index >= 0) {
        g.fight.def_index = idx;
        g.fight.hull = g.world.hull;
    }
    return g;
}

// ---- Cases ----------------------------------------------------------------

fn tZ2PhaseLedger() bool {
    var g = newGame();
    g.world.phase = world.PHASE_DAY;
    g.world.cycle = 0;
    const before = g.world.field_phases;

    const e = expedition.depart(&g, 1);
    if (e.zone != 1) return false;
    if (g.exp.active != 1) return false;
    if (g.exp.zone != 1) return false;
    if (g.exp.fight_index != 0) return false;
    if (g.world.field_phases - before != 3) return false; // 1 action + 2 travel

    // Fight leg: start + finish a real fight. Neither consumes a field phase.
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index < 0) return false;
    if (g.world.field_phases - before != 3) return false;
    g.fight.hp = 1;
    expedition.expeditionStep(&g, def.ACT_STRIKE);
    if (expedition.isInFight(&g)) return false;
    if (g.world.field_phases - before != 3) return false;

    expedition.expeditionStep(&g, expedition.EXP_SURFACE);
    if (g.exp.active != 0) return false;
    if (g.world.field_phases - before != 5) return false; // return = 2 travel
    return true;
}

fn tFightSeedFormula() bool {
    var g = newGame();
    _ = expedition.depart(&g, 1);
    const seed = g.exp.seed;

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.exp.fight_index != 1) return false;
    if (g.fight.rng_state != expectedSeed(seed, 0)) return false;

    // Finish fight 1 (no RNG needed for the outcome) and start fight 2.
    g.fight.outcome = def.OUT_CREATURE_FLED;
    g.fight.hull = g.world.hull;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.exp.fight_index != 2) return false;
    if (g.fight.rng_state != expectedSeed(seed, 1)) return false;
    return true;
}

fn tHullZeroKeepsHold() bool {
    var g = dropGame();
    if (g.fight.def_index < 0) return false;

    // Real fight 1: kill it, then settle through the single entry.
    killCurrent(&g);
    if (g.fight.outcome == def.OUT_ONGOING) return false;
    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (g.fight.def_index >= 0) return false;

    var snap: [def.MAX_PARTS]i32 = undefined;
    copyHold(&snap, &g.exp.hold);
    if (!holdNonZero(&snap)) return false;

    // Real fight 2, entered at 1 Hull; one equip action lets the creature hit.
    g.world.hull = 1;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index < 0) return false;
    if (g.fight.hull != 1) return false;

    const phases_before = g.world.field_phases;
    expedition.expeditionStep(&g, def.ACT_EQUIP);

    // Emergency Ascent ended the fight immediately (not a player flee).
    if (expedition.isInFight(&g)) return false;
    if (g.fight.def_index >= 0) return false;
    if (g.fight.outcome == def.OUT_PLAYER_FLED) return false;
    if (g.world.hull != 0) return false;
    if (!holdEqual(&snap, &g.exp.hold)) return false;
    if (g.exp.active != 0) return false;
    // +1 ascent phase + 2 return travel.
    if (g.world.field_phases - phases_before != 3) return false;
    return true;
}

fn tPlayerFleeKeepsHold() bool {
    var g = dropGame();
    if (g.fight.def_index < 0) return false;

    killCurrent(&g);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.exp.fight_index != 2) return false;

    var snap: [def.MAX_PARTS]i32 = undefined;
    copyHold(&snap, &g.exp.hold);
    if (!holdNonZero(&snap)) return false;

    const phases_before = g.world.field_phases;

    game.gameStep(&g, def.Action{ .kind = def.ACT_FLEE, .arg = 0 });
    if (g.fight.outcome != def.OUT_PLAYER_FLED) return false;

    expedition.expeditionStep(&g, expedition.EXP_SURFACE);
    if (!holdEqual(&snap, &g.exp.hold)) return false;
    if (g.exp.active != 0) return false;
    if (g.world.field_phases - phases_before != 3) return false; // +1 + return 2
    return true;
}

fn tCreatureFleeRenewsSubdue() bool {
    var g = newGame();
    _ = expedition.depart(&g, 1);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index < 0) return false;

    const idx = g.fight.def_index;
    const cdef = creatures.defAt(idx);
    const cycle_at_take = g.world.cycle;

    fleeCreature(&g);
    if (g.fight.outcome != def.OUT_CREATURE_FLED) return false;

    const phases_before = g.world.field_phases;
    expedition.expeditionStep(&g, expedition.EXP_SURFACE);

    if (g.exp.active != 0) return false;
    if (g.world.field_phases - phases_before != 2) return false; // return only
    if (!holdAllZero(&g.exp.hold)) return false;

    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);
    const subdue_idx: usize = @intCast(usize, world.RESPAWN_SUBDUE);
    if (g.world.ready[ri] != cycle_at_take + cdef.respawn[subdue_idx]) return false;

    // Renewal lands Day of the ready cycle, not Night.
    g.world.cycle = g.world.ready[ri];
    g.world.phase = world.PHASE_NIGHT;
    if (world.available(&g.world, 1, idx)) return false;
    g.world.phase = world.PHASE_DAY;
    if (!world.available(&g.world, 1, idx)) return false;
    return true;
}

fn tMaxFightsBlocksHunt() bool {
    var g = newGame();
    const gw = &g.world;
    gw.boat[world.BOAT_OXYGEN] = 1; // max 4
    _ = expedition.depart(&g, 1);

    var i: i32 = 0;
    while (i < 4) : (i += 1) {
        expedition.expeditionStep(&g, expedition.EXP_HUNT);
        if (g.fight.def_index < 0) return false;
        fleeCreature(&g);
        if (g.fight.outcome != def.OUT_CREATURE_FLED) return false;
    }
    if (g.exp.fight_index != 4) return false;
    if (world.maxFights(&g.world) != 4) return false;

    // Settles fight 4, then refuses to hunt.
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.exp.fight_index != 4) return false;
    if (g.fight.def_index >= 0) return false;
    if (g.exp.active != 1) return false;
    return true;
}

fn tHeavyTravelEachWay() bool {
    var g = newGame();
    const gwh = &g.world;
    gwh.boat[world.BOAT_HULL] = 3;

    // Z2 cost 2 < 3: no Heavy.
    expedition.depart(&g, 1);
    if (g.world.field_phases != 3) return false; // 1 + 2
    expedition.returnToDock(&g);
    if (g.world.field_phases != 5) return false; // + 2

    // Z3 cost 3: Heavy adds +1 each way.
    var h = newGame();
    const hw = &h.world;
    hw.boat[world.BOAT_HULL] = 3;
    const before = h.world.field_phases;
    expedition.depart(&h, 2);
    if (h.world.field_phases - before != 5) return false; // 1 + (3 + 1)
    expedition.returnToDock(&h);
    if (h.world.field_phases - before != 9) return false; // + (3 + 1)

    // Cargo T3 also triggers Heavy.
    var c = newGame();
    const cw = &c.world;
    cw.boat[world.BOAT_CARGO] = 3;
    expedition.depart(&c, 2);
    if (c.world.field_phases != 5) return false;
    return true;
}

fn tWorldHullRoundTrip() bool {
    var g = newGame();
    g.world.hull = 73;
    _ = expedition.depart(&g, 1);

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index < 0) return false;
    if (g.fight.hull != 73) return false; // no free dock heal
    if (g.fight.max_hull != world.hullMax(&g.world)) return false;
    if (g.world.hull != 73) return false; // world untouched during fight

    // One strike lets the creature answer: Hull takes real damage.
    game.gameStep(&g, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });
    if (g.fight.outcome != def.OUT_ONGOING) {
        // Killed in one hit would make the round-trip check vacuous.
        return false;
    }
    const damaged = g.fight.hull;
    if (damaged >= 73) return false;

    killCurrent(&g);
    if (g.fight.outcome == def.OUT_ONGOING) return false;
    expedition.expeditionStep(&g, expedition.EXP_SURFACE);

    if (g.world.hull != damaged) return false; // damage persists, no heal
    return true;
}

fn tWarinessAtFightStart() bool {
    var g = newGame();
    _ = expedition.depart(&g, 1);

    // Mark every def wary; whichever encounter rolls gets the +15.
    const gw_mask = &g.world;
    gw_mask.wary_mask[0] = 0xFFFFFFFF;
    gw_mask.wary_mask[1] = 0xFFFFFFFF;

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);

    if (g.fight.max_res != cdef.resolve + world.WARY_RESOLVE_BONUS) return false;
    if (g.fight.res != cdef.resolve + world.WARY_RESOLVE_BONUS) return false;
    if (world.consumeWariness(&g.world, idx) != 0) return false; // cleared
    return true;
}

fn tRestHealsAdvancesAndCondition() bool {
    var g = newGame();
    g.world.hull = 50;
    _ = expedition.depart(&g, 0); // Z1, non-empty pool
    const before = g.world.field_phases;

    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (g.world.hull != 80) return false;
    if (g.world.field_phases - before != 1) return false;
    if (g.pending_cond < def.COND_DROWSY or g.pending_cond > def.COND_EXPOSED) return false;

    // Clamp at Hull T3 max (200).
    var h = newGame();
    const hw = &h.world;
    hw.boat[world.BOAT_HULL] = 3;
    h.world.hull = 190;
    _ = expedition.depart(&h, 0);
    expedition.expeditionStep(&h, expedition.EXP_REST);
    if (h.world.hull != 200) return false;

    // Empty-pool Rest (Z4 has no table rows): heals, advances, no condition.
    var e = newGame();
    e.world.hull = 50;
    _ = expedition.depart(&e, 3); // Z4
    const e_before = e.world.field_phases;
    expedition.expeditionStep(&e, expedition.EXP_REST);
    if (e.world.hull != 80) return false;
    if (e.world.field_phases - e_before != 1) return false;
    if (e.pending_cond != def.COND_NONE) return false;
    return true;
}

fn tEmptyPoolHuntDoesNothing() bool {
    var g = newGame();
    g.world.hull = 50;
    _ = expedition.depart(&g, 3); // Z4: empty pool
    const phases = g.world.field_phases;

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.world.hull != 50) return false;
    if (g.world.field_phases != phases) return false;
    if (g.pending_cond != def.COND_NONE) return false;
    if (g.fight.def_index >= 0) return false;
    if (g.exp.fight_index != 0) return false;
    return true;
}

fn tRestOrderingAfterPhaseAdvance() bool {
    var g = newGame();
    g.world.hull = 50;
    _ = expedition.depart(&g, 0); // ends Day of cycle 1
    const gw = &g.world;

    // Available only on Day of this cycle: the Rest's own phase advance turns
    // the pool empty, but the decision must use the pre-advance phase.
    var i: usize = 0;
    while (i < def.MAX_ZONES * def.MAX_CREATURES) : (i += 1) {
        gw.ready[i] = gw.cycle;
    }

    const phases_before = gw.field_phases;
    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (g.world.hull != 80) return false;
    if (g.world.field_phases - phases_before != 1) return false;
    if (g.pending_cond < def.COND_DROWSY or g.pending_cond > def.COND_EXPOSED) return false;

    // Now Night: the pool is empty, so Hunt does nothing at all.
    const hull = g.world.hull;
    const phases = g.world.field_phases;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.world.hull != hull) return false;
    if (g.world.field_phases != phases) return false;
    if (g.fight.def_index >= 0) return false;
    return true;
}

fn tSeedBounded() bool {
    var state: u32 = 1;
    var raw: u32 = 0;
    var found = false;
    while (state < 1000) : (state += 1) {
        var tmp: u32 = state;
        const r = rng.rngNext(&tmp);
        if (r > 0x00FFFFFF) {
            raw = r;
            found = true;
            break;
        }
    }
    if (!found) return false; // masking must be non-vacuous

    var g = newGame();
    g.world.rng_state = state;
    _ = expedition.depart(&g, 0);
    const bounded: u32 = raw & 0x00FFFFFF;
    if (g.exp.seed != bounded) return false;

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    var i: i32 = 0;
    while (i < 3) : (i += 1) {
        if (g.fight.def_index < 0) return false;
        if (g.fight.rng_state != expectedSeed(bounded, i)) return false;
        g.fight.outcome = def.OUT_CREATURE_FLED;
        g.fight.hull = g.world.hull;
        expedition.expeditionStep(&g, expedition.EXP_HUNT);
    }
    return true;
}

fn tCargoBonusPrimaryOnly() bool {
    const idx = findDefIndex(16); // Ironclad Wrasse: three subdue lines
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);
    if (cdef.sub[0].part <= 0 or cdef.sub[1].part <= 0 or cdef.sub[2].part <= 0) return false;
    if (isKeystone(cdef.sub[0].part) or isKeystone(cdef.sub[1].part) or isKeystone(cdef.sub[2].part)) return false;

    var tier: i32 = 0;
    while (tier <= 3) : (tier += 1) {
        var g = startedGame(idx);
        const gw = &g.world;
        gw.boat[world.BOAT_CARGO] = tier;
        g.fight.outcome = def.OUT_SUBDUE;
        g.fight.hull = g.world.hull;
        expedition.expeditionStep(&g, expedition.EXP_SURFACE);

        var want: [def.MAX_PARTS]i32 = undefined;
        expectedDropHold(&want, cdef.sub[0..], tier);
        if (!holdEqual(&g.exp.hold, &want)) return false;
        const p0: usize = @intCast(usize, cdef.sub[0].part);
        const p1: usize = @intCast(usize, cdef.sub[1].part);
        const p2: usize = @intCast(usize, cdef.sub[2].part);
        if (g.exp.hold[p0] != cdef.sub[0].count + tier) return false;
        if (g.exp.hold[p1] != cdef.sub[1].count) return false;
        if (g.exp.hold[p2] != cdef.sub[2].count) return false;
    }
    return true;
}

fn tLootTablesExact() bool {
    const idx = findDefIndex(16); // Ironclad Wrasse: distinct sub/kill/over lines
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);

    const outcomes = [3]i32{ def.OUT_SUBDUE, def.OUT_KILL, def.OUT_OVERKILL };
    var k: usize = 0;
    while (k < outcomes.len) : (k += 1) {
        var g = startedGame(idx);
        g.fight.outcome = outcomes[k];
        g.fight.hull = g.world.hull;
        expedition.expeditionStep(&g, expedition.EXP_SURFACE);

        var want: [def.MAX_PARTS]i32 = undefined;
        if (outcomes[k] == def.OUT_SUBDUE) {
            expectedDropHold(&want, cdef.sub[0..], 0);
        } else if (outcomes[k] == def.OUT_KILL) {
            expectedDropHold(&want, cdef.kill[0..], 0);
        } else {
            expectedDropHold(&want, cdef.over[0..], 0);
        }
        if (!holdEqual(&g.exp.hold, &want)) return false;
    }
    return true;
}

fn tFleeAddsNothing() bool {
    const idx = findDefIndex(16);
    if (idx < 0) return false;

    var g = startedGame(idx);
    game.gameStep(&g, def.Action{ .kind = def.ACT_FLEE, .arg = 0 });
    if (g.fight.outcome != def.OUT_PLAYER_FLED) return false;
    expedition.expeditionStep(&g, expedition.EXP_SURFACE);
    if (!holdAllZero(&g.exp.hold)) return false;

    var c = startedGame(idx);
    fleeCreature(&c);
    if (c.fight.outcome != def.OUT_CREATURE_FLED) return false;
    expedition.expeditionStep(&c, expedition.EXP_SURFACE);
    if (!holdAllZero(&c.exp.hold)) return false;
    return true;
}

fn tRoughSleepCarriesIntoFight() bool {
    var g = newGame();
    g.world.hull = 50;
    _ = expedition.depart(&g, 0);

    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (g.pending_cond == def.COND_NONE) return false;
    const cond = g.pending_cond;

    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.fight.def_index < 0) return false;
    if (g.fight.cond != cond) return false;
    if (g.pending_cond != def.COND_NONE) return false;
    return true;
}

fn tDepartParksNoFight() bool {
    var g = newGame();
    if (expedition.isInFight(&g)) return false;
    _ = expedition.depart(&g, 1);
    if (expedition.isInFight(&g)) return false;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (!expedition.isInFight(&g)) return false;
    return true;
}

pub fn main() void {
    report("z2_phase_ledger_depart_return", tZ2PhaseLedger());
    report("fight_seed_formula_seed_plus_index_77", tFightSeedFormula());
    report("hull_zero_keeps_earlier_hold", tHullZeroKeepsHold());
    report("player_flee_keeps_earlier_hold_plus_phase", tPlayerFleeKeepsHold());
    report("creature_flee_no_loot_renews_subdue", tCreatureFleeRenewsSubdue());
    report("max_fights_3_plus_oxygen_blocks_hunt", tMaxFightsBlocksHunt());
    report("heavy_plus_one_each_way_cost_ge_3", tHeavyTravelEachWay());
    report("world_hull_round_trips_no_free_heal", tWorldHullRoundTrip());
    report("wariness_plus_15_then_cleared", tWarinessAtFightStart());
    report("rest_heal_phase_clamp_condition", tRestHealsAdvancesAndCondition());
    report("empty_pool_hunt_does_nothing", tEmptyPoolHuntDoesNothing());
    report("rest_uses_pre_advance_pool", tRestOrderingAfterPhaseAdvance());
    report("seed_bounded_no_overflow", tSeedBounded());
    report("cargo_bonus_primary_line_only", tCargoBonusPrimaryOnly());
    report("loot_tables_sub_kill_over_exact", tLootTablesExact());
    report("flee_adds_no_loot", tFleeAddsNothing());
    report("rough_sleep_carries_into_next_fight", tRoughSleepCarriesIntoFight());
    report("depart_parks_no_fight_state", tDepartParksNoFight());

    if (fails != 0) os.exit(1);
    io.write("expedition_test PASS\n");
}
