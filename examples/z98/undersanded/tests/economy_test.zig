// economy_test.zig — UNDERSANDED M5 Task 1 economy arithmetic tests.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/economy_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/economy_test"
//   "$OUT/economy_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const world = @import("../world.zig");
const tables = @import("../tables_t1.zig");
const economy = @import("../economy.zig");

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

fn fillExpertise(e: *[10]i32, level: i32) void {
    var i: usize = 0;
    while (i < e.len) : (i += 1) e[i] = level;
}

fn findUpgrade(axis: i32, tier: i32) ?*const tables.UpgradeRow {
    var i: usize = 0;
    while (i < tables.UPGRADES.len) : (i += 1) {
        const row = &tables.UPGRADES[i];
        if (row.axis == axis and row.tier == tier) return row;
    }
    return null;
}

// 7 materials × E0–E5: commons 1/2/2/3/3/3; deep 0/1/1/2/2/3.
fn expectedYield(m: i32, exp: i32) i32 {
    const common = [6]i32{ 1, 2, 2, 3, 3, 3 };
    const deep = [6]i32{ 0, 1, 1, 2, 2, 3 };
    const idx: usize = @intCast(usize, exp);
    if (economy.isDeepMaterial(m)) return deep[idx];
    return common[idx];
}

fn tYieldGrid() bool {
    var m: i32 = 1;
    while (m <= 7) : (m += 1) {
        var exp: i32 = 0;
        while (exp <= 5) : (exp += 1) {
            const got = economy.refineYield(exp, economy.isDeepMaterial(m));
            if (got != expectedYield(m, exp)) return false;
        }
    }
    // Explicit anchors from the task.
    if (economy.refineYield(0, true) != 0) return false;
    if (economy.refineYield(5, true) != 3) return false;
    if (economy.refineYield(0, false) != 1) return false;
    if (economy.refineYield(5, false) != 3) return false;
    return true;
}

fn tGateMatrix() bool {
    var t2 = [3]economy.MaterialAmt{ .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 } };
    economy.upgradeCost(world.BOAT_HULL, 2, &t2);
    var e1 = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var e2 = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    fillExpertise(&e1, 1);
    fillExpertise(&e2, 2);
    if (economy.canBuyTier(world.BOAT_HULL, 2, &e1, t2)) return false;
    if (!economy.canBuyTier(world.BOAT_HULL, 2, &e2, t2)) return false;

    var t3 = [3]economy.MaterialAmt{ .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 } };
    economy.upgradeCost(world.BOAT_HULL, 3, &t3);
    var e3 = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var e4 = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    fillExpertise(&e3, 3);
    fillExpertise(&e4, 4);
    if (economy.canBuyTier(world.BOAT_HULL, 3, &e3, t3)) return false;
    if (!economy.canBuyTier(world.BOAT_HULL, 3, &e4, t3)) return false;

    // T1 has no gate, even at E0.
    var e0 = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var t1 = [3]economy.MaterialAmt{ .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 } };
    economy.upgradeCost(world.BOAT_HULL, 1, &t1);
    if (!economy.canBuyTier(world.BOAT_HULL, 1, &e0, t1)) return false;

    // Two-material cost where only one is short must fail.
    const pair = [3]economy.MaterialAmt{
        .{ .kind = economy.MAT_CHITIN, .amt = 1 },
        .{ .kind = economy.MAT_PLATE, .amt = 1 },
        .{ .kind = 0, .amt = 0 },
    };
    var short = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    fillExpertise(&short, 4);
    short[economy.MAT_PLATE] = 3;
    if (economy.canBuyTier(world.BOAT_HULL, 3, &short, pair)) return false;
    short[economy.MAT_PLATE] = 4;
    if (!economy.canBuyTier(world.BOAT_HULL, 3, &short, pair)) return false;

    // Keystone parts (8/9) and unused slots (0) skip the gate.
    const keyed = [3]economy.MaterialAmt{
        .{ .kind = economy.MAT_CHITIN, .amt = 1 },
        .{ .kind = economy.MAT_HOOKED_BARBEL, .amt = 1 },
        .{ .kind = economy.MAT_STEEL_FINS, .amt = 2 },
    };
    var only_chitin = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    only_chitin[economy.MAT_CHITIN] = 4;
    if (!economy.canBuyTier(world.BOAT_SPEED, 3, &only_chitin, keyed)) return false;
    return true;
}

fn tAllUpgradeRowsExist() bool {
    var axis: i32 = world.BOAT_HULL;
    while (axis <= world.BOAT_PRECISION) : (axis += 1) {
        var tier: i32 = 1;
        while (tier <= 3) : (tier += 1) {
            const row = findUpgrade(axis, tier) orelse return false;
            var slots: usize = 0;
            var i: usize = 0;
            while (i < row.cost.len) : (i += 1) {
                if (row.cost[i].kind != 0 and row.cost[i].amt > 0) slots += 1;
            }
            if (slots == 0 or slots > 3) return false;

            var cost = [3]economy.MaterialAmt{ .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 }, .{ .kind = 0, .amt = 0 } };
            economy.upgradeCost(axis, tier, &cost);
            i = 0;
            while (i < cost.len) : (i += 1) {
                if (cost[i].kind != row.cost[i].kind) return false;
                if (cost[i].amt != row.cost[i].amt) return false;
            }
        }
    }
    return true;
}

fn tMaterialTotals() bool {
    var sums = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var i: usize = 0;
    while (i < tables.UPGRADES.len) : (i += 1) {
        const row = tables.UPGRADES[i];
        var s: usize = 0;
        while (s < row.cost.len) : (s += 1) {
            const kind = row.cost[s].kind;
            if (kind > 0 and kind < 10) {
                sums[@intCast(usize, kind)] += row.cost[s].amt;
            }
        }
    }

    // §17 per-material totals.
    if (sums[economy.MAT_CHITIN] != 19) return false;
    if (sums[economy.MAT_PLATE] != 6) return false;
    if (sums[economy.MAT_GLAND] != 21) return false;
    if (sums[economy.MAT_BRINE] != 26) return false;
    if (sums[economy.MAT_CORAL] != 26) return false;
    if (sums[economy.MAT_LUM] != 5) return false;
    if (sums[economy.MAT_GLASS] != 8) return false;
    if (sums[economy.MAT_STEEL_FINS] != 2) return false;

    var total: i32 = 0;
    var m: i32 = economy.MAT_CHITIN;
    while (m <= economy.MAT_GLASS) : (m += 1) {
        const got = sums[@intCast(usize, m)];
        if (got != economy.targetTotal(m)) return false;
        if (got != economy.materialTotal(m)) return false;
        total += got;
    }
    if (total != 111) return false;

    // Non-materials have no §17 target.
    if (economy.targetTotal(0) != 0) return false;
    if (economy.targetTotal(economy.MAT_HOOKED_BARBEL) != 0) return false;
    if (economy.targetTotal(economy.MAT_STEEL_FINS) != 0) return false;
    return true;
}

fn tCosmeticTotal() bool {
    var total: i32 = 0;
    var i: usize = 0;
    while (i < tables.COSMETICS.len) : (i += 1) {
        total += tables.COSMETICS[i].price;
    }
    return total == 2100;
}

pub fn main() void {
    report("yield_grid_7_materials_e0_e5", tYieldGrid());
    report("gate_matrix_t2_t3_and_short_material", tGateMatrix());
    report("all_axis_tier_costs_exist_and_fit", tAllUpgradeRowsExist());
    report("material_totals_match_s17_111_steel_fins_2", tMaterialTotals());
    report("cosmetic_prices_total_2100", tCosmeticTotal());

    if (fails != 0) os.exit(1);
    io.write("economy_test PASS\n");
}
