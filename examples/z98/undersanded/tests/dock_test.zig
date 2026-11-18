// dock_test.zig — UNDERSANDED M5 Task 2 dock action tests.
//
// Build/run (repo root):
//   "$ZIG" -fsafe -W -osl --output-dir "$OUT" \
//       examples/z98/undersanded/tests/dock_test.zig
//   sh "$OUT/build_target.sh" linux "$OUT/dock_test"
//   "$OUT/dock_test"
// Prints `ok - <case>` / `FAIL - <case>`; non-zero exit on any failure.

const io = @import("std_io");
const os = @import("std_os");
const def = @import("../def.zig");
const world = @import("../world.zig");
const game = @import("../game.zig");
const expedition = @import("../expedition.zig");
const dock = @import("../dock.zig");
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

fn newGame() def.GameState {
    var g: def.GameState = undefined;
    game.newGame(&g);
    return g;
}

fn toolMask(tool: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, tool);
}

fn cosmeticMask(index: i32) u32 {
    return @intCast(u32, 1) << @intCast(u32, index);
}

// Z98 lowers `g.exp.hold[i]` / `g.world.array[i]` through a struct copy, so
// tests seed arrays through explicit pointers.
fn setHold(g: *def.GameState, part: i32, n: i32) void {
    const ep = &g.exp;
    ep.hold[@intCast(usize, part)] = n;
}

fn setExpertise(g: *def.GameState, material: i32, n: i32) void {
    const wp = &g.world;
    wp.expertise[@intCast(usize, material)] = n;
}

fn setMaterial(g: *def.GameState, material: i32, n: i32) void {
    const wp = &g.world;
    wp.materials[@intCast(usize, material)] = n;
}

fn setBoat(g: *def.GameState, axis: i32, tier: i32) void {
    const wp = &g.world;
    wp.boat[@intCast(usize, axis)] = tier;
}

// Refine consumes all parts of exactly one type and grants +1 expertise.
fn tRefineConsumesOneType() bool {
    var g = newGame();
    setHold(&g, 1, 3);
    setHold(&g, 4, 2);
    g.exp.hold_n = 2;
    setExpertise(&g, 1, 1);
    const rng = g.world.rng_state;

    if (dock.dockRefine(&g, 1) != dock.DOCK_OK) return false;
    if (g.world.materials[1] != 6) return false; // E1 common = 2/part
    if (g.exp.hold[1] != 0) return false;
    if (g.exp.hold[4] != 2) return false;
    if (g.exp.hold_n != 1) return false;
    if (g.world.expertise[1] != 2) return false;
    if (g.world.field_phases != 1) return false;
    if (g.world.rng_state != rng) return false;
    return true;
}

// Refusals (none, invalid, keystone) cost no phase and draw no RNG.
fn tRefineRefusals() bool {
    var g = newGame();
    const rng = g.world.rng_state;

    if (dock.dockRefine(&g, 1) != dock.DOCK_ERR_NO_PARTS) return false;
    if (dock.dockRefine(&g, 8) != dock.DOCK_ERR_INVALID) return false;
    if (dock.dockRefine(&g, 9) != dock.DOCK_ERR_INVALID) return false;
    setHold(&g, 8, 4);
    if (dock.dockRefine(&g, 8) != dock.DOCK_ERR_INVALID) return false;
    if (g.exp.hold[8] != 4) return false;

    if (g.world.field_phases != 0) return false;
    if (g.world.rng_state != rng) return false;
    if (g.world.materials[1] != 0) return false;
    return true;
}

// Expertise caps at 5; refining still succeeds and keeps the cap.
fn tExpertiseCap() bool {
    var g = newGame();
    setExpertise(&g, 1, 5);
    setHold(&g, 1, 1);

    if (dock.dockRefine(&g, 1) != dock.DOCK_OK) return false;
    if (g.world.expertise[1] != 5) return false;
    if (g.world.materials[1] != 3) return false;
    if (g.world.field_phases != 1) return false;
    return true;
}

// Deep E0 refine is legal and yields exactly 0 materials, +1 expertise (P22.1).
fn tDeepZeroYield() bool {
    var g = newGame();
    setHold(&g, 6, 3);
    setExpertise(&g, 6, 0);
    const rng = g.world.rng_state;

    if (dock.dockRefine(&g, 6) != dock.DOCK_OK) return false;
    if (g.world.materials[6] != 0) return false;
    if (g.world.expertise[6] != 1) return false;
    if (g.exp.hold[6] != 0) return false;
    if (g.world.field_phases != 1) return false;
    if (g.world.rng_state != rng) return false;
    return true;
}

// Upgrade buys only the next tier, applies the cumulative total, and gates T2
// on E2 / T3 on E4 in every material spent.
fn tUpgradeTierOrderTotals() bool {
    var g = newGame();
    const rng = g.world.rng_state;

    // Hull T1: Chitin 3, no gate.
    setMaterial(&g, 1, 3);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_OK) return false;
    if (g.world.boat[world.BOAT_HULL] != 1) return false;
    if (world.hullMax(&g.world) != 125) return false;
    if (g.world.materials[1] != 0) return false;
    if (g.world.field_phases != 1) return false;

    // Hull T2 at E1 is refused: no spend, no phase, still T1.
    setMaterial(&g, 1, 6);
    setMaterial(&g, 2, 2);
    setExpertise(&g, 1, 2);
    setExpertise(&g, 2, 1);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_ERR_EXPERTISE) return false;
    if (g.world.boat[world.BOAT_HULL] != 1) return false;
    if (g.world.materials[1] != 6 or g.world.materials[2] != 2) return false;
    if (g.world.field_phases != 1) return false;

    // At E2 it succeeds.
    setExpertise(&g, 1, 2);
    setExpertise(&g, 2, 2);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_OK) return false;
    if (g.world.boat[world.BOAT_HULL] != 2) return false;
    if (world.hullMax(&g.world) != 150) return false;
    if (g.world.materials[1] != 0 or g.world.materials[2] != 0) return false;
    if (g.world.field_phases != 2) return false;

    // T3 needs E4; then the total is 200 and T4 is refused.
    setMaterial(&g, 1, 10);
    setMaterial(&g, 2, 4);
    setExpertise(&g, 1, 3);
    setExpertise(&g, 2, 3);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_ERR_EXPERTISE) return false;
    setExpertise(&g, 1, 4);
    setExpertise(&g, 2, 4);
    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_OK) return false;
    if (g.world.boat[world.BOAT_HULL] != 3) return false;
    if (world.hullMax(&g.world) != 200) return false;
    if (g.world.field_phases != 3) return false;

    if (dock.dockUpgrade(&g, world.BOAT_HULL) != dock.DOCK_ERR_MAX_TIER) return false;
    if (g.world.field_phases != 3) return false;
    if (g.world.rng_state != rng) return false;
    return true;
}

// Speed T3 spends Steel Fins from the persistent hold, not from materials.
fn tUpgradeKeystoneFromHold() bool {
    var g = newGame();
    setBoat(&g, world.BOAT_SPEED, 2);
    setExpertise(&g, economy.MAT_GLASS, 4);
    setExpertise(&g, economy.MAT_GLAND, 4);
    setMaterial(&g, economy.MAT_GLASS, 4);
    setMaterial(&g, economy.MAT_GLAND, 4);
    setHold(&g, economy.MAT_STEEL_FINS, 2);
    g.exp.hold_n = 1;
    const rng = g.world.rng_state;

    if (dock.dockUpgrade(&g, world.BOAT_SPEED) != dock.DOCK_OK) return false;
    if (g.world.boat[world.BOAT_SPEED] != 3) return false;
    if (world.speedMax(&g.world) != 19) return false;
    if (g.exp.hold[economy.MAT_STEEL_FINS] != 0) return false;
    if (g.exp.hold_n != 0) return false;
    if (g.world.materials[economy.MAT_GLASS] != 0) return false;
    if (g.world.materials[economy.MAT_GLAND] != 0) return false;
    if (g.world.field_phases != 1) return false;
    if (g.world.rng_state != rng) return false;

    // Short one Steel Fin: refusal spends nothing.
    var h = newGame();
    setBoat(&h, world.BOAT_SPEED, 2);
    setExpertise(&h, economy.MAT_GLASS, 4);
    setExpertise(&h, economy.MAT_GLAND, 4);
    setMaterial(&h, economy.MAT_GLASS, 4);
    setMaterial(&h, economy.MAT_GLAND, 4);
    setHold(&h, economy.MAT_STEEL_FINS, 1);
    if (dock.dockUpgrade(&h, world.BOAT_SPEED) != dock.DOCK_ERR_NEED_MATERIALS) return false;
    if (h.world.boat[world.BOAT_SPEED] != 2) return false;
    if (h.world.materials[economy.MAT_GLASS] != 4) return false;
    if (h.exp.hold[economy.MAT_STEEL_FINS] != 1) return false;
    if (h.world.field_phases != 0) return false;
    return true;
}

// Craft deducts the exact parts, sets the owned bit, and refuses a re-craft.
fn tCraftDeductsParts() bool {
    var g = newGame();
    setHold(&g, 3, 4); // Gland Sac x4; Electric Gland needs x3
    g.exp.hold_n = 1;
    const rng = g.world.rng_state;

    if (dock.dockCraft(&g, 3) != dock.DOCK_OK) return false;
    if (g.exp.hold[3] != 1) return false;
    if (!dock.toolOwned(&g.world, 3)) return false;
    if (g.world.field_phases != 1) return false;
    if (g.world.rng_state != rng) return false;

    if (dock.dockCraft(&g, 3) != dock.DOCK_ERR_ALREADY) return false;
    if (g.world.field_phases != 1) return false;
    if (g.exp.hold[3] != 1) return false;

    // Short of parts: no bit, no phase, no spend.
    var h = newGame();
    setHold(&h, 2, 2); // Plate Scrap x2; Steel Plate Tool needs x3
    if (dock.dockCraft(&h, 1) != dock.DOCK_ERR_NEED_PARTS) return false;
    if (dock.toolOwned(&h.world, 1)) return false;
    if (h.exp.hold[2] != 2) return false;
    if (h.world.field_phases != 0) return false;
    return true;
}

// Buy spends coins, sets the owned bit, and refuses locked/owned/poor.
fn tBuyCosmetic() bool {
    var g = newGame();
    g.world.cosmetics_unlocked = cosmeticMask(0);
    g.world.money = 150;
    const rng = g.world.rng_state;

    if (dock.dockBuy(&g, 0) != dock.DOCK_OK) return false;
    if (g.world.money != 0) return false;
    if (!dock.cosmeticOwned(&g.world, 0)) return false;
    if (g.world.field_phases != 1) return false;
    if (g.world.rng_state != rng) return false;

    if (dock.dockBuy(&g, 0) != dock.DOCK_ERR_ALREADY) return false;
    if (g.world.field_phases != 1) return false;

    // Locked items never sell, even with coins.
    g.world.money = 200;
    if (dock.dockBuy(&g, 1) != dock.DOCK_ERR_LOCKED) return false;
    if (g.world.money != 200) return false;
    if (g.world.field_phases != 1) return false;

    // Unlocked but unaffordable.
    g.world.cosmetics_unlocked = g.world.cosmetics_unlocked | cosmeticMask(1);
    g.world.money = 174;
    if (dock.dockBuy(&g, 1) != dock.DOCK_ERR_COINS) return false;
    if (dock.cosmeticOwned(&g.world, 1)) return false;
    if (g.world.money != 174) return false;
    if (g.world.field_phases != 1) return false;

    // Invalid index.
    if (dock.dockBuy(&g, 12) != dock.DOCK_ERR_INVALID) return false;
    return true;
}

// Selection is free and requires ownership; 0 clears.
fn tSelectToolFree() bool {
    var g = newGame();
    g.world.tools_owned = toolMask(1);
    g.world.tool_selected = 0;
    const rng = g.world.rng_state;

    if (dock.dockSelectTool(&g, 1) != dock.DOCK_OK) return false;
    if (g.world.tool_selected != 1) return false;
    if (g.world.field_phases != 0) return false;
    if (g.world.rng_state != rng) return false;

    if (dock.dockSelectTool(&g, 2) != dock.DOCK_ERR_NOT_OWNED) return false;
    if (g.world.tool_selected != 1) return false;
    if (g.world.field_phases != 0) return false;

    if (dock.dockSelectTool(&g, 0) != dock.DOCK_OK) return false;
    if (g.world.tool_selected != 0) return false;
    if (g.world.field_phases != 0) return false;

    if (dock.dockSelectTool(&g, 8) != dock.DOCK_ERR_INVALID) return false;
    return true;
}

// Depart keeps the hold, copies the selected tool (activated charge 1, rigged
// 0, unowned none), clears broken, and unlocks zone cosmetic bits.
fn tDepartToolAndCosmetics() bool {
    var g = newGame();
    g.world.tools_owned = toolMask(3);
    g.world.tool_selected = 3;
    setHold(&g, 1, 4);
    g.exp.hold_n = 1;
    const before_hold = g.exp.hold[1];

    _ = expedition.depart(&g, 1); // Z2
    if (g.exp.hold[1] != before_hold) return false;
    if (g.exp.hold_n != 1) return false;
    if (g.exp.tool != 3) return false;
    if (g.exp.tool_charge != 1) return false;
    if (g.exp.tool_broken != 0) return false;

    // Z2 condition unlocks cosmetic items 1, 4, 9 only.
    const z2 = cosmeticMask(1) | cosmeticMask(4) | cosmeticMask(9);
    if (g.world.cosmetics_unlocked != z2) return false;

    var h = newGame();
    h.world.tools_owned = toolMask(2); // Brine Net is rigged
    h.world.tool_selected = 2;
    _ = expedition.depart(&h, 0); // Z1
    if (h.exp.tool != 2) return false;
    if (h.exp.tool_charge != 0) return false;

    // Z1 condition unlocks items 0, 3, 6; Derelict bits stay clear.
    const z1 = cosmeticMask(0) | cosmeticMask(3) | cosmeticMask(6);
    if (h.world.cosmetics_unlocked != z1) return false;
    if ((h.world.cosmetics_unlocked & cosmeticMask(5)) != 0) return false;
    if ((h.world.cosmetics_unlocked & cosmeticMask(8)) != 0) return false;
    if ((h.world.cosmetics_unlocked & cosmeticMask(11)) != 0) return false;

    var k = newGame();
    k.world.tool_selected = 3; // not owned
    _ = expedition.depart(&k, 2); // Z3
    if (k.exp.tool != 0) return false;
    if (k.exp.tool_charge != 0) return false;
    const z3 = cosmeticMask(2) | cosmeticMask(7) | cosmeticMask(10);
    if (k.world.cosmetics_unlocked != z3) return false;
    return true;
}

// A reused GameState must not carry stale stun state into a fresh fight.
fn tStartFightResetsPendingStun() bool {
    var g = newGame();
    g.fight.pending_stun = 7;
    game.startFight(&g, 0);
    if (g.fight.pending_stun != 0) return false;
    return true;
}

pub fn main() void {
    report("refine_consumes_one_type", tRefineConsumesOneType());
    report("refine_refusals_free", tRefineRefusals());
    report("expertise_cap_five", tExpertiseCap());
    report("deep_zero_yield_success", tDeepZeroYield());
    report("upgrade_tier_order_totals", tUpgradeTierOrderTotals());
    report("upgrade_keystone_from_hold", tUpgradeKeystoneFromHold());
    report("craft_deducts_parts", tCraftDeductsParts());
    report("buy_cosmetic_gates", tBuyCosmetic());
    report("select_tool_free", tSelectToolFree());
    report("depart_tool_and_cosmetics", tDepartToolAndCosmetics());
    report("start_fight_resets_pending_stun", tStartFightResetsPendingStun());

    if (fails != 0) os.exit(1);
    io.write("dock_test PASS\n");
}
