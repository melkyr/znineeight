// world_test.zig — UNDERSANDED M4 Task 1 world/calendar/respawn/rare tests.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/world_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/world_test"
//   "$OUT/world_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");

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

fn blankWorld() def.World {
    var w: def.World = undefined;
    game.zeroWorld(&w);
    return w;
}

fn tWorldHull() bool {
    const w = blankWorld();
    if (w.hull != 100) return false;
    if (world.BASE_HULL != 100) return false;
    return true;
}

fn tAdvancePhase() bool {
    var w = blankWorld();
    w.cycle = 0;
    w.phase = world.PHASE_DAY;
    w.field_phases = 0;

    world.advancePhase(&w);
    if (w.phase != world.PHASE_NIGHT) return false;
    if (w.cycle != 0) return false;
    if (w.field_phases != 1) return false;

    world.advancePhase(&w);
    if (w.phase != world.PHASE_DAY) return false;
    if (w.cycle != 1) return false;
    if (w.field_phases != 2) return false;
    return true;
}

// cycle 3 Night + subdue respawn 3 -> ready 6; available Day of cycle 6 but
// not Night of cycle 6, and available from cycle 7 on.
fn tRenewalDayOfCycle() bool {
    var w = blankWorld();
    w.cycle = 3;
    w.phase = world.PHASE_NIGHT;
    world.markTaken(&w, 0, 0, def.OUT_SUBDUE);
    if (w.ready[0] != 6) return false;
    if (w.lockout_until[0] != 0) return false;

    w.cycle = 6;
    w.phase = world.PHASE_NIGHT;
    if (world.available(&w, 0, 0)) return false;
    w.phase = world.PHASE_DAY;
    if (!world.available(&w, 0, 0)) return false;

    w.cycle = 7;
    w.phase = world.PHASE_NIGHT;
    if (!world.available(&w, 0, 0)) return false;
    return true;
}

fn tRespawnOutcomes() bool {
    var w = blankWorld();
    w.cycle = 3;

    // Def 0 (Mystic Eel) respawn triple is 3/9/15.
    world.markTaken(&w, 0, 0, def.OUT_SUBDUE);
    if (w.ready[0] != 6) return false;
    if (w.lockout_until[0] != 0) return false;
    world.markTaken(&w, 0, 0, def.OUT_KILL);
    if (w.ready[0] != 12) return false;
    if (w.lockout_until[0] != 0) return false;

    // Mystic Eel is family 1 -> bit 1, not bit 0. Assert the mask is unchanged
    // before the overkill call, then set on overkill.
    const fam: u32 = @intCast(u32, 1) << @intCast(u32, 1);
    if ((w.family_overkill_mask & fam) != 0) return false;
    world.markTaken(&w, 0, 0, def.OUT_OVERKILL);
    if (w.ready[0] != 18) return false;
    if ((w.family_overkill_mask & fam) == 0) return false;
    if ((w.family_overkill_mask & @intCast(u32, 1)) != 0) return false;
    return true;
}

fn tPerZoneIsolation() bool {
    var w = blankWorld();
    w.cycle = 1;

    world.markTaken(&w, 0, 0, def.OUT_SUBDUE); // Z1: ready 4
    world.markTaken(&w, 1, 0, def.OUT_KILL); // Z2: ready 10
    if (w.ready[0] != 4) return false;
    if (w.ready[def.MAX_CREATURES] != 10) return false;

    w.cycle = 4;
    w.phase = world.PHASE_DAY;
    if (!world.available(&w, 0, 0)) return false;
    if (world.available(&w, 1, 0)) return false;

    w.cycle = 10;
    w.phase = world.PHASE_NIGHT;
    if (!world.available(&w, 0, 0)) return false;
    if (world.available(&w, 1, 0)) return false;
    w.phase = world.PHASE_DAY;
    if (!world.available(&w, 1, 0)) return false;
    return true;
}

fn tReleaseBonus() bool {
    var w = blankWorld();
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 8) return false;
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 16) return false;
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 24) return false;
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 32) return false;
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 40) return false;
    world.applyRelease(&w, 1, 4);
    if (w.release_bonus[1] != 40) return false;

    world.clearReleaseBonus(&w, 1);
    if (w.release_bonus[1] != 0) return false;

    // Bonus accrues nothing in a base-zero zone (Z1).
    w.cycle = 0;
    w.phase = world.PHASE_DAY;
    world.applyRelease(&w, 0, 0);
    world.applyRelease(&w, 0, 0);
    if (world.rareChance(&w, 0) != 0) return false;
    return true;
}

fn tLockoutFiveCycles() bool {
    var w = blankWorld();
    w.cycle = 0;
    w.phase = world.PHASE_DAY;
    w.lockout_until[1] = 5;

    w.cycle = 0;
    if (world.rareChance(&w, 1) != 0) return false;
    w.cycle = 4;
    if (world.rareChance(&w, 1) != 0) return false;
    // At cycle == lockout_until the node is no longer locked.
    w.cycle = 5;
    if (world.rareChance(&w, 1) != 15) return false;
    return true;
}

// An expired lockout (cycle - 1) must not count in the global echo; rareChance
// must equal the no-lock baseline.
fn tExpiredLockout() bool {
    var w = blankWorld();
    w.cycle = 3;
    w.phase = world.PHASE_DAY;
    const baseline = world.rareChance(&w, 1);
    if (baseline != 15) return false;
    w.lockout_until[0] = w.cycle - 1;
    if (world.lockedNodeCount(&w) != 0) return false;
    if (world.rareChance(&w, 1) != baseline) return false;
    return true;
}

fn tGlobalEcho() bool {
    var w = blankWorld();
    w.cycle = 0;
    w.phase = world.PHASE_DAY;

    // Two locked nodes elsewhere: Z1 and Z4. Z2 stays unlocked.
    w.lockout_until[0] = 5;
    w.lockout_until[3] = 5;
    if (world.lockedNodeCount(&w) != 2) return false;
    if (world.rareChance(&w, 1) != 5) return false; // 15 - 5*2

    w.lockout_until[3] = 0;
    if (world.rareChance(&w, 1) != 10) return false; // 15 - 5*1

    // Floor at 0 when many nodes are locked.
    var i: usize = 0;
    while (i < def.MAX_ZONES) : (i += 1) {
        w.lockout_until[i] = 5;
    }
    w.lockout_until[1] = 0; // Z2 itself remains unlocked
    if (world.lockedNodeCount(&w) != 11) return false;
    if (world.rareChance(&w, 1) != 0) return false;

    // Clamp at 100: Z3 night 75 + bonus 40 = 115.
    var v = blankWorld();
    v.cycle = 0;
    v.phase = world.PHASE_NIGHT;
    var k: i32 = 0;
    while (k < 5) : (k += 1) {
        world.applyRelease(&v, 2, 4);
    }
    if (v.release_bonus[2] != 40) return false;
    if (world.rareChance(&v, 2) != 100) return false;
    return true;
}

fn tWariness() bool {
    var w = blankWorld();
    if (world.consumeWariness(&w, 4) != 0) return false;

    world.applyRelease(&w, 2, 4);
    world.applyRelease(&w, 2, 4); // no stacking
    if (world.consumeWariness(&w, 4) != 15) return false;
    if (world.consumeWariness(&w, 4) != 0) return false;
    return true;
}

fn tMarkSeen() bool {
    var w = blankWorld();
    world.markSeen(&w, 4);
    if ((w.seen_mask[0] & (@intCast(u32, 1) << @intCast(u32, 4))) == 0) return false;
    world.markSeen(&w, 40);
    if ((w.seen_mask[1] & (@intCast(u32, 1) << @intCast(u32, 8))) == 0) return false;
    return true;
}

fn tBaseRareSums() bool {
    // §13 Z2: day 5+10, night 10+10.
    if (world.BASE_RARE[1][world.PHASE_DAY] != 5 + 10) return false;
    if (world.BASE_RARE[1][world.PHASE_NIGHT] != 10 + 10) return false;

    // §13 Z3: day 20+15+10, night 10+15+15+10+15+10.
    if (world.BASE_RARE[2][world.PHASE_DAY] != 20 + 15 + 10) return false;
    if (world.BASE_RARE[2][world.PHASE_NIGHT] != 10 + 15 + 15 + 10 + 15 + 10) return false;

    // Z1 and Z4..Z11 have no rares.
    if (world.BASE_RARE[0][0] != 0 or world.BASE_RARE[0][1] != 0) return false;
    var z: usize = 3;
    while (z < def.MAX_ZONES) : (z += 1) {
        if (world.BASE_RARE[z][0] != 0) return false;
        if (world.BASE_RARE[z][1] != 0) return false;
    }
    return true;
}

fn tBoatTables() bool {
    if (world.HULL_TABLE[0] != 100) return false;
    if (world.HULL_TABLE[1] != 125) return false;
    if (world.HULL_TABLE[2] != 150) return false;
    if (world.HULL_TABLE[3] != 200) return false;
    if (world.SPEED_TABLE[0] != 10) return false;
    if (world.SPEED_TABLE[1] != 12) return false;
    if (world.SPEED_TABLE[2] != 15) return false;
    if (world.SPEED_TABLE[3] != 19) return false;
    if (world.CARGO_TABLE[0] != 0) return false;
    if (world.CARGO_TABLE[1] != 1) return false;
    if (world.CARGO_TABLE[2] != 2) return false;
    if (world.CARGO_TABLE[3] != 3) return false;
    if (world.OXYGEN_FIGHTS[0] != 3) return false;
    if (world.OXYGEN_FIGHTS[1] != 4) return false;
    if (world.OXYGEN_FIGHTS[2] != 5) return false;
    if (world.OXYGEN_FIGHTS[3] != 6) return false;
    if (world.PRECISION_TABLE[0] != 10) return false;
    if (world.PRECISION_TABLE[1] != 15) return false;
    if (world.PRECISION_TABLE[2] != 20) return false;
    if (world.PRECISION_TABLE[3] != 25) return false;

    // Distinct tiers per axis so each helper resolves its own axis.
    var w = blankWorld();
    w.boat[world.BOAT_HULL] = 3;
    w.boat[world.BOAT_SPEED] = 1;
    w.boat[world.BOAT_CARGO] = 2;
    w.boat[world.BOAT_OXYGEN] = 1;
    w.boat[world.BOAT_PRECISION] = 0;
    if (world.hullMax(&w) != world.HULL_TABLE[3]) return false;
    if (world.speedMax(&w) != world.SPEED_TABLE[1]) return false;
    if (world.cargoMax(&w) != world.CARGO_TABLE[2]) return false;
    if (world.oxygenFights(&w) != world.OXYGEN_FIGHTS[1]) return false;
    if (world.precisionMargin(&w) != world.PRECISION_TABLE[0]) return false;
    if (world.maxFights(&w) != 3 + w.boat[world.BOAT_OXYGEN]) return false;
    if (world.maxFights(&w) != 4) return false;
    return true;
}

// OUT_OVERKILL sets lockout_until[zone] = cycle + 5 and rare is 0 for the take
// cycle through cycle+4 (Z2 has a non-zero base: day 15).
fn tOverkillLockout() bool {
    var w = blankWorld();
    w.cycle = 2;
    w.phase = world.PHASE_DAY;
    world.markTaken(&w, 1, 0, def.OUT_OVERKILL);
    if (w.lockout_until[1] != w.cycle + 5) return false;

    var c: i32 = 2;
    while (c < 7) : (c += 1) {
        w.cycle = c;
        if (world.rareChance(&w, 1) != 0) return false;
    }
    w.cycle = 7;
    if (world.rareChance(&w, 1) <= 0) return false;
    if (world.rareChance(&w, 1) != 15) return false;
    return true;
}

// Creature-flee renews on the subdue index (def 0 respawn[0] = 3).
fn tCreatureFledRenews() bool {
    var w = blankWorld();
    w.cycle = 3;
    world.markTaken(&w, 0, 0, def.OUT_CREATURE_FLED);
    if (w.ready[0] != 6) return false;
    if (w.lockout_until[0] != 0) return false;
    return true;
}

// Outcome 6 is not a defined OUT_* code: it must not renew, set masks, or lock.
fn tOtherOutcomeNoop() bool {
    var w = blankWorld();
    w.cycle = 3;
    w.ready[0] = 42;
    w.lockout_until[0] = 7;
    w.family_overkill_mask = 0x10;
    const ready_before = w.ready[0];
    const lockout_before = w.lockout_until[0];
    const mask_before = w.family_overkill_mask;
    world.markTaken(&w, 0, 0, 6);
    if (w.ready[0] != ready_before) return false;
    if (w.lockout_until[0] != lockout_before) return false;
    if (w.family_overkill_mask != mask_before) return false;
    return true;
}

// A negative def index must not panic and must leave all state untouched.
fn tNegativeDefNoop() bool {
    var w = blankWorld();
    w.cycle = 3;
    w.ready[0] = 42;
    w.lockout_until[0] = 7;
    w.family_overkill_mask = 0x10;
    world.markTaken(&w, 0, -1, def.OUT_OVERKILL);
    if (w.ready[0] != 42) return false;
    if (w.lockout_until[0] != 7) return false;
    if (w.family_overkill_mask != 0x10) return false;
    return true;
}

// Player flee/ascent (and other non-terminal codes) must not renew or touch
// masks/lockout.
fn tFleeOngoingNoop() bool {
    var w = blankWorld();
    w.cycle = 3;
    w.ready[0] = 42;
    world.markTaken(&w, 0, 0, def.OUT_PLAYER_FLED);
    if (w.ready[0] != 42) return false;
    world.markTaken(&w, 0, 0, def.OUT_ONGOING);
    if (w.ready[0] != 42) return false;
    if (w.lockout_until[0] != 0) return false;
    if (w.family_overkill_mask != 0) return false;
    return true;
}

// A def row not yet authored (index 5; DEFS has rows 0..4) is a no-op, not a
// defAt panic.
fn tUndefinedDefNoop() bool {
    if (creatures.defCount() != 5) return false;
    var w = blankWorld();
    w.cycle = 3;
    w.ready[5] = 42;
    world.markTaken(&w, 0, 5, def.OUT_OVERKILL);
    if (w.ready[5] != 42) return false;
    if (w.lockout_until[0] != 0) return false;
    if (w.family_overkill_mask != 0) return false;
    return true;
}

pub fn main() void {
    report("world_hull_starts_100", tWorldHull());
    report("advance_phase_day_night_cycle", tAdvancePhase());
    report("renewal_day_of_cycle_exact", tRenewalDayOfCycle());
    report("respawn_outcomes_and_overkill_mask", tRespawnOutcomes());
    report("per_zone_instance_isolation", tPerZoneIsolation());
    report("release_bonus_steps_cap_clear", tReleaseBonus());
    report("lockout_five_cycles", tLockoutFiveCycles());
    report("expired_lockout_not_echoed", tExpiredLockout());
    report("global_echo_per_locked_node", tGlobalEcho());
    report("wariness_15_then_0", tWariness());
    report("mark_seen_words", tMarkSeen());
    report("base_rare_matches_spec13_sums", tBaseRareSums());
    report("boat_tier_tables_and_max_fights", tBoatTables());
    report("overkill_sets_five_cycle_lockout", tOverkillLockout());
    report("creature_fled_renews_subdue", tCreatureFledRenews());
    report("player_fled_ongoing_noop", tFleeOngoingNoop());
    report("undefined_def_noop", tUndefinedDefNoop());
    report("other_outcome_noop", tOtherOutcomeNoop());
    report("negative_def_noop", tNegativeDefNoop());

    if (fails != 0) os.exit(1);
    io.write("world_test PASS\n");
}
