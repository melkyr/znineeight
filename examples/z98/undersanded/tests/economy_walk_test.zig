// economy_walk_test.zig — UNDERSANDED M5 real-E0 economy walk (spec §17,
// §21.5, §38 P22.7).
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/economy_walk_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/economy_walk_test"
//   "$OUT/economy_walk_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const economy = @import("../economy.zig");
const dock = @import("../dock.zig");
const tables = @import("../tables_t1.zig");

var fails: usize = 0;

// §17 per-material totals keyed by R7 material id (1..7). The spec table is
// printed in Chitin/Steel/Gland/Lum/Brine/Coral/Glass order, so Lum=5 is id 6
// and Brine/Coral are ids 4/5; `economy.targetTotal` is the same mapping.
const TARGETS = [8]i32{ 0, 19, 6, 21, 26, 26, 5, 8 };

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
    game.newGame(&g);
    return g;
}

// Z98 lowers `g.exp.hold[i]` through a struct copy; seed via a pointer (D18).
fn setHold(g: *def.GameState, part: i32, n: i32) void {
    const ep = &g.exp;
    ep.hold[@intCast(usize, part)] = n;
}

fn setMaterial(g: *def.GameState, material: i32, n: i32) void {
    const wp = &g.world;
    wp.materials[@intCast(usize, material)] = n;
}

fn setExpertise(g: *def.GameState, material: i32, n: i32) void {
    const wp = &g.world;
    wp.expertise[@intCast(usize, material)] = n;
}

fn setBoat(g: *def.GameState, axis: i32, tier: i32) void {
    const wp = &g.world;
    wp.boat[@intCast(usize, axis)] = tier;
}

fn ceilDiv(a: i32, b: i32) i32 {
    if (a <= 0) return 0;
    return (a + b - 1) / b;
}

fn countsNonNegative(g: *const def.GameState) bool {
    if (g.exp.hold_n < 0) return false;
    var i: usize = 0;
    while (i < def.MAX_MATERIALS) : (i += 1) {
        if (g.world.materials[i] < 0) return false;
    }
    i = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (g.exp.hold[i] < 0) return false;
    }
    return true;
}

fn printIntLine(label: []const u8, value: i32) void {
    io.write(label);
    io.printInt(value);
    io.write("\n");
}

// P22.7: start cold (0 materials, E0) and drive the real dock actions. Four
// one-part refines take every material to E4; one measured batch at E4 then
// covers the §17 target. Steel Fins are granted as the fixed keystone cost.
fn tRealE0Walk() bool {
    var g = newGame();
    var produced = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var granted = [10]i32{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
    var refines: i32 = 0;
    var upgrades: i32 = 0;

    var m: i32 = 1;
    while (m <= economy.MAT_GLASS) : (m += 1) {
        const target = TARGETS[@intCast(usize, m)];
        if (target != economy.targetTotal(m)) return false;
        if (g.world.materials[@intCast(usize, m)] != 0) return false;
        if (g.world.expertise[@intCast(usize, m)] != 0) return false;

        const deep = economy.isDeepMaterial(m);
        var r: i32 = 0;
        while (r < 4) : (r += 1) {
            setHold(&g, m, 1);
            g.exp.hold_n = 1;
            granted[@intCast(usize, m)] += 1;
            const phases = g.world.field_phases;
            if (dock.dockRefine(&g, m) != dock.DOCK_OK) return false;
            if (g.world.field_phases != phases + 1) return false;
            if (!countsNonNegative(&g)) return false;
            refines += 1;
        }
        if (g.world.expertise[@intCast(usize, m)] != 4) return false;

        const made = g.world.materials[@intCast(usize, m)];
        const per4 = economy.refineYield(4, deep);
        if (made < target) {
            if (per4 <= 0) return false;
            const need = ceilDiv(target - made, per4);
            if (need <= 0) return false;
            setHold(&g, m, need);
            g.exp.hold_n = 1;
            granted[@intCast(usize, m)] += need;
            const phases = g.world.field_phases;
            if (dock.dockRefine(&g, m) != dock.DOCK_OK) return false;
            if (g.world.field_phases != phases + 1) return false;
            if (!countsNonNegative(&g)) return false;
            refines += 1;
        }

        if (g.world.expertise[@intCast(usize, m)] < 4) return false;
        if (g.world.materials[@intCast(usize, m)] < target) return false;
        produced[@intCast(usize, m)] = g.world.materials[@intCast(usize, m)];
    }

    setHold(&g, economy.MAT_STEEL_FINS, 2);
    g.exp.hold_n = 1;
    if (g.exp.hold[economy.MAT_STEEL_FINS] != 2) return false;
    if (g.exp.hold_n < 0) return false;

    var tier: i32 = 1;
    while (tier <= 3) : (tier += 1) {
        var axis: i32 = world.BOAT_HULL;
        while (axis <= world.BOAT_PRECISION) : (axis += 1) {
            var cost = [3]economy.MaterialAmt{
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
                .{ .kind = 0, .amt = 0 },
            };
            economy.upgradeCost(axis, tier, &cost);
            if (!economy.canBuyTier(axis, tier, &g.world.expertise, cost)) return false;

            const phases = g.world.field_phases;
            if (dock.dockUpgrade(&g, axis) != dock.DOCK_OK) return false;
            if (g.world.boat[@intCast(usize, axis)] != tier) return false;
            if (g.world.field_phases != phases + 1) return false;
            if (!countsNonNegative(&g)) return false;
            upgrades += 1;
        }
    }

    var spent: i32 = 0;
    m = 1;
    while (m <= economy.MAT_GLASS) : (m += 1) {
        const left = g.world.materials[@intCast(usize, m)];
        if (left > produced[@intCast(usize, m)]) return false;
        const used = produced[@intCast(usize, m)] - left;
        spent += used;
        io.write("walk m=");
        io.printInt(m);
        io.write(" target=");
        io.printInt(TARGETS[@intCast(usize, m)]);
        io.write(" granted=");
        io.printInt(granted[@intCast(usize, m)]);
        io.write(" produced=");
        io.printInt(produced[@intCast(usize, m)]);
        io.write(" spent=");
        io.printInt(used);
        io.write(" left=");
        io.printInt(left);
        io.write(" exp=");
        io.printInt(g.world.expertise[@intCast(usize, m)]);
        io.write("\n");
    }

    printIntLine("walk_total_materials_spent=", spent);
    printIntLine("walk_field_phases=", g.world.field_phases);
    printIntLine("walk_refines=", refines);
    printIntLine("walk_upgrades=", upgrades);

    if (spent != 111) return false;
    if (g.exp.hold[economy.MAT_STEEL_FINS] != 0) return false;
    if (g.world.field_phases != refines + upgrades) return false;
    if (g.exp.hold_n < 0) return false;

    var axis: i32 = world.BOAT_HULL;
    while (axis <= world.BOAT_PRECISION) : (axis += 1) {
        if (g.world.boat[@intCast(usize, axis)] != 3) return false;
    }
    return true;
}

// The walk must pass through the real gates: the same cost is refused at E1
// and accepted at E2, with no spend and no phase on the refusal.
fn tWalkGatesEnforced() bool {
    var g = newGame();
    setBoat(&g, world.BOAT_HULL, 1);
    setMaterial(&g, economy.MAT_CHITIN, 6);
    setMaterial(&g, economy.MAT_PLATE, 2);
    setExpertise(&g, economy.MAT_CHITIN, 1);
    setExpertise(&g, economy.MAT_PLATE, 1);

    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_ERR_EXPERTISE) return false;
    if (g.world.boat[world.BOAT_HULL] != 1) return false;
    if (g.world.materials[economy.MAT_CHITIN] != 6) return false;
    if (g.world.materials[economy.MAT_PLATE] != 2) return false;
    if (g.world.field_phases != 0) return false;

    setExpertise(&g, economy.MAT_CHITIN, 2);
    setExpertise(&g, economy.MAT_PLATE, 2);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_OK) return false;
    return g.world.boat[world.BOAT_HULL] == 2 and g.world.field_phases == 1;
}

fn tPartsAtE3() bool {
    var total: i32 = 0;
    var parts: i32 = 0;
    var m: i32 = 1;
    while (m <= economy.MAT_GLASS) : (m += 1) {
        const target = TARGETS[@intCast(usize, m)];
        if (target != economy.targetTotal(m)) return false;
        const per = economy.refineYield(3, economy.isDeepMaterial(m));
        if (per <= 0) return false;
        total += target;
        parts += ceilDiv(target, per);
    }
    if (total != 111) return false;
    if (parts != 41) return false;
    return true;
}

fn tCosmeticTotal() bool {
    var coins: i32 = 0;
    var i: usize = 0;
    while (i < tables.COSMETICS.len) : (i += 1) {
        coins += tables.COSMETICS[i].price;
    }
    return coins == 2100;
}

pub fn main() void {
    report("real_e0_walk_spends_111_steel_fins_2", tRealE0Walk());
    report("walk_expertise_gates_enforced", tWalkGatesEnforced());
    report("walk_s17_parts_e3_41_targets_111", tPartsAtE3());
    report("walk_cosmetics_total_2100", tCosmeticTotal());

    if (fails != 0) os.exit(1);
    io.write("economy_walk_test PASS\n");
}
