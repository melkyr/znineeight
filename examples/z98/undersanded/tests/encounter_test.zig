// encounter_test.zig — UNDERSANDED M4 Task 2 encounter pipeline tests.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/encounter_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/encounter_test"
//   "$OUT/encounter_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const creatures = @import("../creatures_t1.zig");
const tables = @import("../tables_t1.zig");
const encounter = @import("../encounter.zig");

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

fn dayWorld() def.World {
    var w = blankWorld();
    w.cycle = 0;
    w.phase = world.PHASE_DAY;
    return w;
}

fn nightWorld() def.World {
    var w = blankWorld();
    w.cycle = 1;
    w.phase = world.PHASE_NIGHT;
    return w;
}

fn isRareDef(index: i32) bool {
    return creatures.defAt(index).role == creatures.ROLE_RARE;
}

fn tableSum(zone: i32, phase: i32) i32 {
    const rows = tables.rows(zone, phase);
    var total: i32 = 0;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        total += rows[i].weight;
    }
    return total;
}

fn tableRareSum(zone: i32, phase: i32) i32 {
    const rows = tables.rows(zone, phase);
    var total: i32 = 0;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (isRareDef(rows[i].def_index)) total += rows[i].weight;
    }
    return total;
}

fn buildPool(w: *def.World, zone: i32, defs: *[def.MAX_ENCOUNTER]i32, weights: *[def.MAX_ENCOUNTER]i32) i32 {
    var i: usize = 0;
    while (i < def.MAX_ENCOUNTER) : (i += 1) {
        defs[i] = 0;
        weights[i] = 0;
    }
    return encounter.apportion(w, zone, defs, weights);
}

fn poolSum(weights: *const [def.MAX_ENCOUNTER]i32, n: i32) i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        total += weights[@intCast(usize, i)];
    }
    return total;
}

fn poolRareSum(defs: *const [def.MAX_ENCOUNTER]i32, weights: *const [def.MAX_ENCOUNTER]i32, n: i32) i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (isRareDef(defs[u])) total += weights[u];
    }
    return total;
}

fn poolCommonSum(defs: *const [def.MAX_ENCOUNTER]i32, weights: *const [def.MAX_ENCOUNTER]i32, n: i32) i32 {
    var total: i32 = 0;
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (!isRareDef(defs[u])) total += weights[u];
    }
    return total;
}

fn poolWeightOf(defs: *const [def.MAX_ENCOUNTER]i32, weights: *const [def.MAX_ENCOUNTER]i32, n: i32, wanted: i32) i32 {
    var i: i32 = 0;
    while (i < n) : (i += 1) {
        const u: usize = @intCast(usize, i);
        if (defs[u] == wanted) return weights[u];
    }
    return -1;
}

fn tDefsGrown() bool {
    if (creatures.defCount() != 18) return false;
    if (creatures.DEFS.len != 18) return false;
    if (creatures.defAt(0).id != 1) return false;
    if (creatures.defAt(1).id != 2) return false;
    if (creatures.defAt(2).id != 4) return false;
    if (creatures.defAt(3).id != 18) return false;
    if (creatures.defAt(4).id != 19) return false;

    if (creatures.defAt(5).id != 5) return false; // Rust Tuna
    if (creatures.defAt(6).id != 7) return false; // Kelp Crab
    if (creatures.defAt(7).id != 8) return false; // Brine Jelly
    if (creatures.defAt(8).id != 9) return false; // Chitin Barnacle
    if (creatures.defAt(9).id != 10) return false; // Spark Anemone
    if (creatures.defAt(10).id != 3) return false; // Mileel
    if (creatures.defAt(11).id != 6) return false; // Tunisteel
    if (creatures.defAt(12).id != 11) return false; // Coral Crab
    if (creatures.defAt(13).id != 12) return false; // Abyssal Lantern-Jelly
    if (creatures.defAt(14).id != 13) return false; // Neon Ghost-Ray
    if (creatures.defAt(15).id != 14) return false; // Glass Squid
    if (creatures.defAt(16).id != 15) return false; // Brine Angler
    if (creatures.defAt(17).id != 16) return false; // Ironclad Wrasse
    return true;
}

fn tZ1SumsCommonsOnly() bool {
    var phase: i32 = 0;
    while (phase < 2) : (phase += 1) {
        if (tableSum(0, phase) != 100) return false;
        const rows = tables.rows(0, phase);
        var i: usize = 0;
        while (i < rows.len) : (i += 1) {
            if (isRareDef(rows[i].def_index)) return false;
        }
    }
    return true;
}

fn tZ1RareChanceZero() bool {
    var w = dayWorld();
    if (world.rareChance(&w, 0) != 0) return false;

    w.phase = world.PHASE_NIGHT;
    w.cycle = 1;
    if (world.rareChance(&w, 0) != 0) return false;

    // Z1 base rare is zero, so releases still accrue (capped at 40) while
    // rareChance stays 0.
    var k: i32 = 0;
    while (k < 6) : (k += 1) {
        world.applyRelease(&w, 0, 0);
    }
    if (w.release_bonus[0] != 40) return false;
    if (world.rareChance(&w, 0) != 0) return false;

    // Other locked nodes cannot create rare weight in Z1 either.
    w.lockout_until[1] = w.cycle + 5;
    w.lockout_until[2] = w.cycle + 5;
    if (world.rareChance(&w, 0) != 0) return false;
    return true;
}

fn tBaseSumsAndRareEquality() bool {
    var zone: i32 = 1;
    while (zone <= 2) : (zone += 1) {
        var phase: i32 = 0;
        while (phase < 2) : (phase += 1) {
            if (tableSum(zone, phase) != 100) return false;
            const z: usize = @intCast(usize, zone);
            const p: usize = @intCast(usize, phase);
            if (tableRareSum(zone, phase) != world.BASE_RARE[z][p]) return false;
        }
    }
    return true;
}

fn tCooldownRenormalizes() bool {
    var w = dayWorld();
    world.markTaken(&w, 0, 0, def.OUT_SUBDUE); // Mystic Eel on cooldown

    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    const n = buildPool(&w, 0, &defs, &weights);
    if (n <= 0) return false;
    if (poolSum(&weights, n) != 100) return false;

    // Taken species are dropped from the pool entirely (weight -1 = absent)
    // or carry zero weight; either way they can never roll.
    if (poolWeightOf(&defs, &weights, n, 0) > 0) return false;

    var rolls: i32 = 0;
    while (rolls < 128) : (rolls += 1) {
        var out: i32 = -1;
        if (!encounter.rollEncounter(&w, 0, &out)) return false;
        if (out == 0) return false;
    }
    return true;
}

fn tRareShareScalesWithEcho() bool {
    // Z3 night base 75; one locked node elsewhere drops it to 70.
    var w = nightWorld();
    w.lockout_until[0] = w.cycle + 5;
    if (world.rareChance(&w, 2) != 70) return false;

    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    const n = buildPool(&w, 2, &defs, &weights);
    if (n <= 0) return false;
    if (poolSum(&weights, n) != 100) return false;
    if (poolRareSum(&defs, &weights, n) != 70) return false;
    if (poolCommonSum(&defs, &weights, n) != 30) return false;
    return true;
}

fn tRareShareExactWithRelease() bool {
    // Z3 night base 75 + release 8 = 83; commons must fill 17 exactly.
    var w = nightWorld();
    world.applyRelease(&w, 2, 4);
    if (world.rareChance(&w, 2) != 83) return false;

    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    const n = buildPool(&w, 2, &defs, &weights);
    if (n <= 0) return false;
    if (poolSum(&weights, n) != 100) return false;
    if (poolRareSum(&defs, &weights, n) != 83) return false;
    if (poolCommonSum(&defs, &weights, n) != 17) return false;

    // Z2 day base rare 15 + 8 = 23.
    var d = dayWorld();
    world.applyRelease(&d, 1, 4);
    if (world.rareChance(&d, 1) != 23) return false;
    var ddefs: [def.MAX_ENCOUNTER]i32 = undefined;
    var dweights: [def.MAX_ENCOUNTER]i32 = undefined;
    const dn = buildPool(&d, 1, &ddefs, &dweights);
    if (dn <= 0) return false;
    if (poolSum(&dweights, dn) != 100) return false;
    if (poolRareSum(&ddefs, &dweights, dn) != 23) return false;
    return true;
}

fn tLockedNodeRareZero() bool {
    var w = nightWorld();
    w.lockout_until[2] = w.cycle + 5;
    if (world.rareChance(&w, 2) != 0) return false;

    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    const n = buildPool(&w, 2, &defs, &weights);
    if (n <= 0) return false;
    if (poolSum(&weights, n) != 100) return false;
    if (poolRareSum(&defs, &weights, n) != 0) return false;
    if (poolCommonSum(&defs, &weights, n) != 100) return false;
    return true;
}

fn tEmptyPoolFalse() bool {
    var w = dayWorld();

    // Take every Z1 species across both phases.
    var phase: i32 = 0;
    while (phase < 2) : (phase += 1) {
        const rows = tables.rows(0, phase);
        var i: usize = 0;
        while (i < rows.len) : (i += 1) {
            world.markTaken(&w, 0, rows[i].def_index, def.OUT_SUBDUE);
        }
    }

    var defs: [def.MAX_ENCOUNTER]i32 = undefined;
    var weights: [def.MAX_ENCOUNTER]i32 = undefined;
    if (buildPool(&w, 0, &defs, &weights) != encounter.NO_ROW) return false;

    var out: i32 = -1;
    if (encounter.rollEncounter(&w, 0, &out)) return false;

    w.phase = world.PHASE_NIGHT;
    if (encounter.rollEncounter(&w, 0, &out)) return false;
    return true;
}

fn tReleaseResetOnRare() bool {
    var w = nightWorld();
    w.release_bonus[1] = 40;
    w.rng_state = 0x12345678;
    if (world.rareChance(&w, 1) != 60) return false; // 20 + 40

    var hit = false;
    var iter: i32 = 0;
    while (iter < 1000) : (iter += 1) {
        var out: i32 = -1;
        if (!encounter.rollEncounter(&w, 1, &out)) return false;
        if (isRareDef(out)) {
            if (w.release_bonus[1] != 0) return false;
            hit = true;
            break;
        }
    }
    if (!hit) return false;
    return true;
}

// Mirror of the rare-clear test: a common or named pick must leave the release
// bonus intact. Locking the node zeroes rare weight, so the pool only yields
// common/named rows and the test is guaranteed to exercise both roles.
fn tReleaseSurvivesCommonAndNamed() bool {
    var w = dayWorld();
    w.release_bonus[1] = 40;
    w.lockout_until[1] = w.cycle + 5;
    w.rng_state = 0x9abcdef0;
    if (world.rareChance(&w, 1) != 0) return false;

    var saw_common = false;
    var saw_named = false;
    var iter: i32 = 0;
    while (iter < 4096 and (!saw_common or !saw_named)) : (iter += 1) {
        var out: i32 = -1;
        if (!encounter.rollEncounter(&w, 1, &out)) return false;
        const role = creatures.defAt(out).role;
        if (role == creatures.ROLE_RARE) return false;
        if (w.release_bonus[1] != 40) return false;
        if (role == creatures.ROLE_COMMON) saw_common = true;
        if (role == creatures.ROLE_NAMED) saw_named = true;
    }
    return saw_common and saw_named;
}

fn tDenseIndexMapping() bool {
    const z1d = [5]i32{ 1, 4, 5, 7, 10 };
    const z1n = [5]i32{ 2, 1, 5, 7, 10 };
    const z2d = [10]i32{ 6, 1, 4, 5, 3, 7, 9, 10, 11, 18 };
    const z2n = [8]i32{ 2, 8, 1, 5, 7, 9, 11, 18 };
    const z3d = [6]i32{ 16, 11, 5, 7, 9, 19 };
    const z3n = [8]i32{ 11, 12, 13, 14, 15, 8, 9, 19 };

    if (!checkIds(0, 0, z1d[0..])) return false;
    if (!checkIds(0, 1, z1n[0..])) return false;
    if (!checkIds(1, 0, z2d[0..])) return false;
    if (!checkIds(1, 1, z2n[0..])) return false;
    if (!checkIds(2, 0, z3d[0..])) return false;
    if (!checkIds(2, 1, z3n[0..])) return false;
    return true;
}

fn checkIds(zone: i32, phase: i32, ids: []const i32) bool {
    const rows = tables.rows(zone, phase);
    if (rows.len != ids.len) return false;
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (creatures.defAt(rows[i].def_index).id != ids[i]) return false;
    }
    return true;
}

pub fn main() void {
    report("defs_grow_5_to_18_dense_mapping", tDefsGrown());
    report("z1_day_night_sum_100_commons_only", tZ1SumsCommonsOnly());
    report("z1_rare_chance_zero_always", tZ1RareChanceZero());
    report("z2_z3_sums_100_rare_equals_base", tBaseSumsAndRareEquality());
    report("cooldown_renormalizes_and_never_rolls", tCooldownRenormalizes());
    report("z3_night_rare_share_scales_with_echo", tRareShareScalesWithEcho());
    report("rare_share_exact_with_release", tRareShareExactWithRelease());
    report("locked_node_rare_share_zero", tLockedNodeRareZero());
    report("empty_pool_returns_false", tEmptyPoolFalse());
    report("rare_roll_clears_release_bonus", tReleaseResetOnRare());
    report("common_and_named_picks_keep_release_bonus", tReleaseSurvivesCommonAndNamed());
    report("table_rows_resolve_intended_roster_id", tDenseIndexMapping());

    if (fails != 0) os.exit(1);
    io.write("encounter_test PASS\n");
}
