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
const fight = @import("../fight.zig");
const expedition = @import("../expedition.zig");
const render = @import("../render_term.zig");

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

fn appendText(out: []u8, p: usize, text: []const u8) usize {
    var pos = p;
    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        out[pos] = text[i];
        pos += 1;
    }
    return pos;
}

fn appendInt(out: []u8, p: usize, v: i32) usize {
    var pos = p;
    if (v == 0) {
        out[pos] = '0';
        return pos + 1;
    }
    var tmp: [16]u8 = undefined;
    var n: usize = 0;
    var x = v;
    while (x > 0) : (x = x / 10) {
        tmp[n] = @intCast(u8, '0' + @intCast(i32, x % 10));
        n += 1;
    }
    var i = n;
    while (i > 0) {
        i -= 1;
        out[pos] = tmp[i];
        pos += 1;
    }
    return pos;
}

fn textEqual(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return true;
}

fn expectedSecured(out: []u8, lines: []const def.DropLine, cargo: i32) []const u8 {
    var h: [def.MAX_PARTS]i32 = undefined;
    expectedDropHold(&h, lines, cargo);

    var p = appendText(out, 0, "Secured: ");
    var any = false;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (h[i] <= 0) continue;
        if (any) p = appendText(out, p, ", ");
        any = true;
        p = appendText(out, p, render.partName(@intCast(i32, i)));
        p = appendText(out, p, " x");
        p = appendInt(out, p, h[i]);
    }
    if (!any) p = appendText(out, p, "nothing");
    return out[0..p];
}

// Real Z2 (night on arrival) drive. Seed 0 hunts a Kelp Crab: Restrain
// reaches the auto-subdue gate, Strike lands a plain Kill, and seed 9 Strike
// overkills. Modal prompts (rare rows) take the Attempt action.
const REAL_SEED: u32 = 0;
const OVERKILL_SEED: u32 = 9;

fn startReal(seed: u32, cargo: i32) def.GameState {
    var g = newGame();
    const gw = &g.world;
    gw.rng_state = seed;
    gw.boat[world.BOAT_CARGO] = cargo;
    _ = expedition.depart(&g, 1);
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    return g;
}

fn driveReal(g: *def.GameState, act: i32) void {
    var guard: i32 = 0;
    while (expedition.isInFight(g) and guard < 80) : (guard += 1) {
        if (g.screen == fight.SCREEN_FIGHT) {
            expedition.expeditionStep(g, act);
        } else {
            expedition.expeditionStep(g, def.ACT_ATTEMPT);
        }
    }
}

fn realSubdue(seed: u32) def.GameState {
    var g = startReal(seed, 0);
    driveReal(&g, def.ACT_RESTRAIN);
    return g;
}

fn startsWith(text: []const u8, prefix: []const u8) bool {
    if (prefix.len > text.len) return false;
    var i: usize = 0;
    while (i < prefix.len) : (i += 1) {
        if (text[i] != prefix[i]) return false;
    }
    return true;
}

fn countSecured(s: *const def.GameState) i32 {
    var n: i32 = 0;
    var i: i32 = 0;
    while (i < s.log_n) : (i += 1) {
        if (s.log[@intCast(usize, i)].class == def.CLS_SECURED) n += 1;
    }
    return n;
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
    // A settled kill clears def_index; the CLS_SECURED log owns the line.
    if (g.fight.def_index != expedition.NO_FIGHT) return false;

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
    // A settled creature flee clears def_index; the log owns the line.
    if (g.fight.outcome != def.OUT_CREATURE_FLED) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;
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
    var probe = realSubdue(REAL_SEED);
    if (probe.fight.outcome != def.OUT_SUBDUE) return false;
    const idx = probe.fight.def_index;
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);

    var nonempty: i32 = 0;
    var i: usize = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        if (cdef.sub[i].part > 0 and cdef.sub[i].count > 0) nonempty += 1;
    }
    if (nonempty < 2) return false;

    var primary: i32 = -1;
    i = 0;
    while (i < def.MAX_DROP_LINES) : (i += 1) {
        if (cdef.sub[i].part <= 0 or cdef.sub[i].count <= 0) continue;
        if (isKeystone(cdef.sub[i].part)) continue;
        primary = @intCast(i32, i);
        break;
    }
    if (primary < 0) return false;

    var tier: i32 = 0;
    while (tier <= 3) : (tier += 1) {
        var g = startReal(REAL_SEED, tier);
        if (g.fight.def_index != idx) return false;
        driveReal(&g, def.ACT_RESTRAIN);
        if (g.fight.outcome != def.OUT_SUBDUE) return false;

        var want: [def.MAX_PARTS]i32 = undefined;
        expectedDropHold(&want, cdef.sub[0..], tier);
        if (!holdEqual(&g.exp.hold, &want)) return false;

        i = 0;
        while (i < def.MAX_DROP_LINES) : (i += 1) {
            if (cdef.sub[i].part <= 0 or cdef.sub[i].count <= 0) continue;
            var add: i32 = 0;
            if (@intCast(i32, i) == primary) add = tier;
            const p: usize = @intCast(usize, cdef.sub[i].part);
            if (g.exp.hold[p] != cdef.sub[i].count + add) return false;
        }
    }
    return true;
}

fn tLootTablesExact() bool {
    // Subdue: real drive, drops already in the hold while the choice is pending.
    var sub = realSubdue(REAL_SEED);
    if (sub.fight.outcome != def.OUT_SUBDUE) return false;
    const sub_idx = sub.fight.def_index;
    if (sub_idx < 0) return false;
    const sub_def = creatures.defAt(sub_idx);

    var want: [def.MAX_PARTS]i32 = undefined;
    expectedDropHold(&want, sub_def.sub[0..], 0);
    if (!holdEqual(&sub.exp.hold, &want)) return false;

    // Kill: real Strike drive, corpse table + kill-index renewal.
    var kill = startReal(REAL_SEED, 0);
    const kill_idx = kill.fight.def_index;
    if (kill_idx < 0) return false;
    const kill_def = creatures.defAt(kill_idx);
    const kill_cycle = kill.world.cycle;
    driveReal(&kill, def.ACT_STRIKE);
    if (kill.fight.outcome != def.OUT_KILL) return false;
    expectedDropHold(&want, kill_def.kill[0..], 0);
    if (!holdEqual(&kill.exp.hold, &want)) return false;
    if (kill.fight.def_index != expedition.NO_FIGHT) return false;
    const kri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, kill_idx);
    if (kill.world.ready[kri] != kill_cycle + kill_def.respawn[@intCast(usize, world.RESPAWN_KILL)]) return false;

    // Overkill: real Strike drive on a seed that overshoots.
    var over = startReal(OVERKILL_SEED, 0);
    const over_idx = over.fight.def_index;
    if (over_idx < 0) return false;
    const over_def = creatures.defAt(over_idx);
    driveReal(&over, def.ACT_STRIKE);
    if (over.fight.outcome != def.OUT_OVERKILL) return false;
    expectedDropHold(&want, over_def.over[0..], 0);
    if (!holdEqual(&over.exp.hold, &want)) return false;
    if (over.fight.def_index != expedition.NO_FIGHT) return false;
    return true;
}

fn tFleeAddsNothing() bool {
    var g = startReal(REAL_SEED, 0);
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);

    expedition.expeditionStep(&g, def.ACT_FLEE);
    if (g.fight.outcome != def.OUT_PLAYER_FLED) return false;
    if (g.exp.active != 0) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;
    if (!holdAllZero(&g.exp.hold)) return false;
    if (g.world.ready[ri] != 0) return false;

    var c = startReal(REAL_SEED, 0);
    const c_idx = c.fight.def_index;
    if (c_idx < 0) return false;
    const c_def = creatures.defAt(c_idx);
    const c_cycle = c.world.cycle;
    const cri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, c_idx);
    fleeCreature(&c);
    if (c.fight.outcome != def.OUT_CREATURE_FLED) return false;
    expedition.expeditionStep(&c, expedition.EXP_SURFACE);
    if (!holdAllZero(&c.exp.hold)) return false;
    if (c.world.ready[cri] != c_cycle + c_def.respawn[@intCast(usize, world.RESPAWN_SUBDUE)]) return false;
    return true;
}

// §7: settled KILL/OVERKILL log the exact §14.4 drops (including the Cargo
// primary-line bonus); creature flee logs the explicit empty line. No outcome
// may ever set fight.flags bit 31.
fn tSecuredLineForSettledFights() bool {
    var line_buf: [256]u8 = undefined;
    var ck_buf: [256]u8 = undefined;
    var want_buf: [256]u8 = undefined;

    var kill = startReal(REAL_SEED, 0);
    const kill_idx = kill.fight.def_index;
    if (kill_idx < 0) return false;
    const kill_def = creatures.defAt(kill_idx);
    driveReal(&kill, def.ACT_STRIKE);
    if (kill.fight.outcome != def.OUT_KILL) return false;
    if (kill.fight.def_index != expedition.NO_FIGHT) return false;
    if (kill.fight.flags != kill_def.flags) return false;
    if ((kill.fight.flags & 0x80000000) != 0) return false;
    if (countSecured(&kill) != 1) return false;

    const kill_line = render.securedLine(&kill, line_buf[0..]);
    const kill_want = expectedSecured(want_buf[0..], kill_def.kill[0..], 0);
    if (!textEqual(kill_line, kill_want)) return false;
    if (startsWith(kill_line, "Secured: nothing")) return false;

    // Cargo 2 adds +2 to the primary (non-keystone, first non-empty) line.
    var cargo_kill = startReal(REAL_SEED, 2);
    const ck_idx = cargo_kill.fight.def_index;
    if (ck_idx != kill_idx) return false;
    driveReal(&cargo_kill, def.ACT_STRIKE);
    if (cargo_kill.fight.outcome != def.OUT_KILL) return false;
    const ck_line = render.securedLine(&cargo_kill, ck_buf[0..]);
    const ck_want = expectedSecured(want_buf[0..], kill_def.kill[0..], 2);
    if (!textEqual(ck_line, ck_want)) return false;
    if (textEqual(ck_line, kill_line)) return false;

    var over = startReal(OVERKILL_SEED, 0);
    const over_idx = over.fight.def_index;
    if (over_idx < 0) return false;
    const over_def = creatures.defAt(over_idx);
    driveReal(&over, def.ACT_STRIKE);
    if (over.fight.outcome != def.OUT_OVERKILL) return false;
    if (over.fight.def_index != expedition.NO_FIGHT) return false;
    if (over.fight.flags != over_def.flags) return false;
    if ((over.fight.flags & 0x80000000) != 0) return false;

    const over_line = render.securedLine(&over, line_buf[0..]);
    const over_want = expectedSecured(want_buf[0..], over_def.over[0..], 0);
    if (!textEqual(over_line, over_want)) return false;
    if (startsWith(over_line, "Secured: nothing")) return false;

    var fled = startReal(REAL_SEED, 0);
    const fled_idx = fled.fight.def_index;
    if (fled_idx < 0) return false;
    const fled_def = creatures.defAt(fled_idx);
    fleeCreature(&fled);
    if (fled.fight.outcome != def.OUT_CREATURE_FLED) return false;
    expedition.expeditionStep(&fled, expedition.EXP_SURFACE);
    if (fled.fight.def_index != expedition.NO_FIGHT) return false;
    if (fled.fight.flags != fled_def.flags) return false;
    if ((fled.fight.flags & 0x80000000) != 0) return false;
    const fled_line = render.securedLine(&fled, line_buf[0..]);
    if (!textEqual(fled_line, "Secured: nothing")) return false;
    return true;
}

// §7: Subdue loot lands before the Release/Sell choice; the pending marker
// blocks fields until the choice, and securedLine can already show the haul.
fn tSubdueSettlesBeforeChoice() bool {
    var g = realSubdue(REAL_SEED);
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    const idx = g.fight.def_index;
    if (idx < 0) return false;

    var want: [def.MAX_PARTS]i32 = undefined;
    expectedDropHold(&want, creatures.defAt(idx).sub[0..], 0);
    if (!holdEqual(&g.exp.hold, &want)) return false;

    var sbuf: [256]u8 = undefined;
    const line = render.securedLine(&g, sbuf[0..]);
    if (!startsWith(line, "Secured: ")) return false;
    if (line.len <= "Secured: ".len) return false;
    if (startsWith(line, "Secured: nothing")) return false;

    // No renewal yet: the Release/Sell choice still owns markTaken.
    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);
    if (g.world.ready[ri] != 0) return false;

    // HUNT is refused with no phase, rng, fight-index or hold change.
    var hold_snap: [def.MAX_PARTS]i32 = undefined;
    copyHold(&hold_snap, &g.exp.hold);
    const phases = g.world.field_phases;
    const rng_state = g.world.rng_state;
    const fight_index = g.exp.fight_index;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (g.world.field_phases != phases) return false;
    if (g.world.rng_state != rng_state) return false;
    if (g.exp.fight_index != fight_index) return false;
    if (g.fight.def_index != idx) return false;
    if (g.fight.outcome != def.OUT_SUBDUE) return false;
    if (!holdEqual(&g.exp.hold, &hold_snap)) return false;
    return true;
}

// (g) Kill path: corpse drops, the kill respawn index, and NO_FIGHT settle.
fn tKillAwardsAndRenews() bool {
    var g = startReal(REAL_SEED, 0);
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);
    const cycle = g.world.cycle;

    driveReal(&g, def.ACT_STRIKE);
    if (g.fight.outcome != def.OUT_KILL) return false;

    var want: [def.MAX_PARTS]i32 = undefined;
    expectedDropHold(&want, cdef.kill[0..], 0);
    if (!holdEqual(&g.exp.hold, &want)) return false;

    if (g.fight.def_index != expedition.NO_FIGHT) return false;
    if (g.fight.flags != cdef.flags) return false;

    const ri: usize = @intCast(usize, 1) * def.MAX_CREATURES + @intCast(usize, idx);
    if (g.world.ready[ri] != cycle + cdef.respawn[@intCast(usize, world.RESPAWN_KILL)]) return false;
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

    // Stale settled/pending markers from an earlier expedition must not survive.
    g.fight.def_index = 0;
    g.fight.outcome = def.OUT_KILL;
    _ = expedition.depart(&g, 1);
    if (g.fight.def_index != expedition.NO_FIGHT) return false;
    if (g.fight.outcome != def.OUT_ONGOING) return false;
    if (expedition.isInFight(&g)) return false;
    expedition.expeditionStep(&g, expedition.EXP_HUNT);
    if (!expedition.isInFight(&g)) return false;
    return true;
}

fn tSecuredNoEntryEmpty() bool {
    var g = newGame();
    var buf: [256]u8 = undefined;
    if (render.securedLine(&g, buf[0..]).len != 0) return false;

    // A normal fight-log row is not a settlement record.
    g.log_n = 1;
    g.log[0] = def.LogEntry{ .class = def.LOG_NORMAL, .msg_id = fight.MSG_STRIKE, .a = 1, .b = 2 };
    if (render.securedLine(&g, buf[0..]).len != 0) return false;
    return true;
}

fn tSecuredExactlyOnce() bool {
    var g = startReal(REAL_SEED, 0);
    const idx = g.fight.def_index;
    if (idx < 0) return false;
    const cdef = creatures.defAt(idx);

    // Resolve directly so no postFight has run yet.
    g.fight.hp = 1;
    game.gameStep(&g, def.Action{ .kind = def.ACT_STRIKE, .arg = 0 });
    if (g.fight.outcome != def.OUT_KILL and g.fight.outcome != def.OUT_OVERKILL) return false;
    if (countSecured(&g) != 0) return false;

    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (countSecured(&g) != 1) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;
    if (g.fight.flags != cdef.flags) return false;

    var snap: [def.MAX_PARTS]i32 = undefined;
    copyHold(&snap, &g.exp.hold);

    // Second settle attempt is a no-op: marker clear, no extra log or loot.
    expedition.expeditionStep(&g, expedition.EXP_REST);
    if (countSecured(&g) != 1) return false;
    if (!holdEqual(&snap, &g.exp.hold)) return false;
    if (g.fight.def_index != expedition.NO_FIGHT) return false;
    return true;
}

fn tDockRest() bool {
    // 60 -> 100 (+40); Day -> Night keeps the cycle, phase +1, no condition,
    // no RNG draw.
    var g = newGame();
    const gw = &g.world;
    gw.hull = 60;
    gw.phase = world.PHASE_DAY;
    gw.cycle = 4;
    gw.field_phases = 10;
    gw.rng_state = 12345;
    g.pending_cond = def.COND_NONE;

    expedition.restAtDock(&g);
    if (gw.hull != 100) return false;
    if (gw.field_phases != 11) return false;
    if (gw.phase != world.PHASE_NIGHT) return false;
    if (gw.cycle != 4) return false;
    if (g.pending_cond != def.COND_NONE) return false;
    if (gw.rng_state != 12345) return false;

    // Clamp at the base 100 max (Hull tier 0).
    var c = newGame();
    const cw = &c.world;
    cw.boat[world.BOAT_HULL] = 0;
    cw.hull = 90;
    expedition.restAtDock(&c);
    if (cw.hull != 100) return false;

    // Clamp at the Hull T3 max (200); Night -> Day advances the cycle +1 and
    // the phase count +1.
    var h = newGame();
    const hw = &h.world;
    hw.boat[world.BOAT_HULL] = 3;
    hw.hull = 190;
    hw.phase = world.PHASE_NIGHT;
    hw.cycle = 2;
    hw.field_phases = 5;
    expedition.restAtDock(&h);
    if (hw.hull != 200) return false;
    if (hw.field_phases != 6) return false;
    if (hw.phase != world.PHASE_DAY) return false;
    if (hw.cycle != 3) return false;

    // Full Hull still costs exactly one phase (§5).
    var f = newGame();
    f.world.hull = 100;
    f.world.field_phases = 0;
    expedition.restAtDock(&f);
    if (f.world.hull != 100) return false;
    if (f.world.field_phases != 1) return false;
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
    report("secured_line_settled_kill_over_flee", tSecuredLineForSettledFights());
    report("subdue_loot_before_choice_pending_guard", tSubdueSettlesBeforeChoice());
    report("kill_awards_drops_and_renews", tKillAwardsAndRenews());
    report("rough_sleep_carries_into_next_fight", tRoughSleepCarriesIntoFight());
    report("depart_parks_no_fight_state", tDepartParksNoFight());
    report("secured_line_no_entry_empty", tSecuredNoEntryEmpty());
    report("secured_awards_exactly_once", tSecuredExactlyOnce());
    report("dock_rest_heal_phase_no_condition_rng", tDockRest());

    if (fails != 0) os.exit(1);
    io.write("expedition_test PASS\n");
}
