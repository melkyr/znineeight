// dock.zig — UNDERSANDED dock actions (spec §10, §11, §16, §17, P22).
//
// Pure: no I/O and no RNG. Every successful Refine/Upgrade/Craft/Buy costs
// exactly one phase (`world.advancePhase`); every refusal costs none. Tool
// selection is free (P22.5). Parts are the persistent `Expedition.hold`;
// materials are `World.materials` keyed by R7 ids 1..7.

const def = @import("def.zig");
const world = @import("world.zig");
const tables = @import("tables_t1.zig");
const items = @import("items.zig");
const economy = @import("economy.zig");

// Result vocabulary (0 = success; every other value is a documented refusal).
pub const DOCK_OK: i32 = 0;
pub const DOCK_ERR_NO_PARTS: i32 = 1; // refine with nothing of that type
pub const DOCK_ERR_NEED_PARTS: i32 = 2; // craft is short of parts
pub const DOCK_ERR_NEED_MATERIALS: i32 = 3; // upgrade is short of materials/parts
pub const DOCK_ERR_EXPERTISE: i32 = 4; // T2/T3 expertise gate not met
pub const DOCK_ERR_MAX_TIER: i32 = 5; // axis already at T3
pub const DOCK_ERR_ALREADY: i32 = 6; // tool or cosmetic already owned
pub const DOCK_ERR_LOCKED: i32 = 7; // cosmetic milestone not reached
pub const DOCK_ERR_COINS: i32 = 8; // cosmetic price not affordable
pub const DOCK_ERR_NOT_OWNED: i32 = 9; // tool not crafted
pub const DOCK_ERR_INVALID: i32 = 10; // bad id / not a refineable material

pub fn resultText(code: i32) []const u8 {
    switch (code) {
        DOCK_OK => return "Done.",
        DOCK_ERR_NO_PARTS => return "No parts of that type to refine.",
        DOCK_ERR_NEED_PARTS => return "Not enough parts.",
        DOCK_ERR_NEED_MATERIALS => return "Not enough materials.",
        DOCK_ERR_EXPERTISE => return "Expertise too low for that tier.",
        DOCK_ERR_MAX_TIER => return "That axis is already at its highest tier.",
        DOCK_ERR_ALREADY => return "You already own that.",
        DOCK_ERR_LOCKED => return "This is for an experienced adventurer.",
        DOCK_ERR_COINS => return "Not enough coins.",
        DOCK_ERR_NOT_OWNED => return "That tool is not owned.",
        else => return "Invalid choice.",
    }
}

pub fn isRareRefine(material: i32) bool {
    return material == economy.MAT_LUM or material == economy.MAT_GLASS;
}

pub fn refineParts(g: *const def.GameState, material: i32) i32 {
    if (material < economy.MAT_CHITIN or material > economy.MAT_GLASS) return 0;
    return g.exp.hold[@intCast(usize, material)];
}

pub fn refinePerPart(g: *const def.GameState, material: i32) i32 {
    if (material < economy.MAT_CHITIN or material > economy.MAT_GLASS) return 0;
    const exp = g.world.expertise[@intCast(usize, material)];
    return economy.refineYield(exp, economy.isDeepMaterial(material));
}

pub fn cosmeticBit(index: i32) u32 {
    if (index < 0 or index >= def.MAX_COSMETICS) return 0;
    return @intCast(u32, 1) << @intCast(u32, index);
}

pub fn cosmeticOwned(w: *const def.World, index: i32) bool {
    const bit = cosmeticBit(index);
    return bit != 0 and (w.cosmetics_owned & bit) != 0;
}

pub fn cosmeticUnlocked(w: *const def.World, index: i32) bool {
    const bit = cosmeticBit(index);
    return bit != 0 and (w.cosmetics_unlocked & bit) != 0;
}

fn recountHold(g: *def.GameState) void {
    var n: i32 = 0;
    var i: usize = 0;
    while (i < def.MAX_PARTS) : (i += 1) {
        if (g.exp.hold[i] > 0) n += 1;
    }
    g.exp.hold_n = n;
}

fn findTool(tool: i32) ?*const def.ToolRow {
    const rows = tables.tools();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (rows[i].id == tool) return &rows[i];
    }
    return null;
}

fn findUpgrade(axis: i32, tier: i32) ?*const def.UpgradeRow {
    const rows = tables.upgrades();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (rows[i].axis == axis and rows[i].tier == tier) {
            return &rows[i];
        }
    }
    return null;
}

// True when every cost slot is covered. Kinds 1..7 spend World.materials;
// keystone parts 8/9 spend Expedition.hold (P22).
fn canPayUpgrade(g: *const def.GameState, cost: *const [3]economy.MaterialAmt) bool {
    var i: usize = 0;
    while (i < cost.len) : (i += 1) {
        const kind = cost[i].kind;
        const amt = cost[i].amt;
        if (kind == 0 or amt <= 0) continue;
        if (kind >= economy.MAT_CHITIN and kind <= economy.MAT_GLASS) {
            if (g.world.materials[@intCast(usize, kind)] < amt) return false;
        } else if (kind == economy.MAT_HOOKED_BARBEL or kind == economy.MAT_STEEL_FINS) {
            if (g.exp.hold[@intCast(usize, kind)] < amt) return false;
        } else {
            return false;
        }
    }
    return true;
}

fn payUpgrade(g: *def.GameState, cost: *const [3]economy.MaterialAmt) void {
    // Z98 lowers `g.world.field` through a struct copy; write through explicit
    // pointers so the spends reach the real arrays.
    const wp = &g.world;
    const ep = &g.exp;
    var spent_hold = false;
    var i: usize = 0;
    while (i < cost.len) : (i += 1) {
        const kind = cost[i].kind;
        const amt = cost[i].amt;
        if (kind == 0 or amt <= 0) continue;
        if (kind >= economy.MAT_CHITIN and kind <= economy.MAT_GLASS) {
            wp.materials[@intCast(usize, kind)] -= amt;
        } else if (kind == economy.MAT_HOOKED_BARBEL or kind == economy.MAT_STEEL_FINS) {
            ep.hold[@intCast(usize, kind)] -= amt;
            spent_hold = true;
        }
    }
    if (spent_hold) recountHold(g);
}

// Refine all parts of one type (§16). Deep/rare batches below E5 may yield 0;
// that is still a success and still grants +1 expertise (P22.1). Keystones
// (8/9) are not materials and are refused.
pub fn dockRefine(g: *def.GameState, material: i32) i32 {
    if (material < economy.MAT_CHITIN or material > economy.MAT_GLASS) {
        return DOCK_ERR_INVALID;
    }
    const u: usize = @intCast(usize, material);
    const wp = &g.world;
    const ep = &g.exp;
    const count = ep.hold[u];
    if (count <= 0) return DOCK_ERR_NO_PARTS;

    const exp = wp.expertise[u];
    const per = economy.refineYield(exp, economy.isDeepMaterial(material));
    wp.materials[u] += count * per;
    ep.hold[u] = 0;

    var next_exp = exp + 1;
    if (next_exp > 5) next_exp = 5;
    wp.expertise[u] = next_exp;
    recountHold(g);
    world.advancePhase(&g.world);
    return DOCK_OK;
}

// Buy the next tier of one axis (only the next tier, §11). The expertise gate
// is checked before any spend; keystone costs come from the hold.
pub fn dockUpgrade(g: *def.GameState, axis: i32) i32 {
    if (axis < 0 or axis > 4) return DOCK_ERR_INVALID;
    const wp = &g.world;
    const current = wp.boat[@intCast(usize, axis)];
    if (current >= 3) return DOCK_ERR_MAX_TIER;
    const tier = current + 1;

    var cost: [3]economy.MaterialAmt = [3]economy.MaterialAmt{
        .{ .kind = 0, .amt = 0 },
        .{ .kind = 0, .amt = 0 },
        .{ .kind = 0, .amt = 0 },
    };
    if (findUpgrade(axis, tier) == null) return DOCK_ERR_INVALID;
    economy.upgradeCost(axis, tier, &cost);

    if (!economy.canBuyTier(axis, tier, &wp.expertise, cost)) {
        return DOCK_ERR_EXPERTISE;
    }
    if (!canPayUpgrade(g, &cost)) return DOCK_ERR_NEED_MATERIALS;

    payUpgrade(g, &cost);
    wp.boat[@intCast(usize, axis)] = tier;
    world.advancePhase(&g.world);
    return DOCK_OK;
}

// Craft one tool from parts (§10), owned forever. Refuses at the first
// missing part or when the bit is already set; no phase on refusal.
pub fn dockCraft(g: *def.GameState, tool: i32) i32 {
    if (tool < 1 or tool > 7) return DOCK_ERR_INVALID;
    if (items.toolOwned(&g.world, tool)) return DOCK_ERR_ALREADY;
    const row = findTool(tool) orelse return DOCK_ERR_INVALID;
    const ep = &g.exp;

    var i: usize = 0;
    while (i < row.cost.len) : (i += 1) {
        const kind = row.cost[i].kind;
        const amt = row.cost[i].amt;
        if (kind <= 0 or amt <= 0) continue;
        if (kind >= def.MAX_PARTS) return DOCK_ERR_INVALID;
        if (ep.hold[@intCast(usize, kind)] < amt) return DOCK_ERR_NEED_PARTS;
    }

    i = 0;
    while (i < row.cost.len) : (i += 1) {
        const kind = row.cost[i].kind;
        const amt = row.cost[i].amt;
        if (kind <= 0 or amt <= 0) continue;
        ep.hold[@intCast(usize, kind)] -= amt;
    }
    recountHold(g);

    const bit: u32 = @intCast(u32, tool);
    const wp = &g.world;
    wp.tools_owned = wp.tools_owned | (@intCast(u32, 1) << bit);
    world.advancePhase(&g.world);
    return DOCK_OK;
}

// Buy one cosmetic (§11). The item bit must be unlocked by a zone milestone
// (or, from M11, the Derelict); locked/owned/poor purchases are free refusals.
pub fn dockBuy(g: *def.GameState, cosmetic: i32) i32 {
    if (cosmetic < 0 or cosmetic >= def.MAX_COSMETICS) return DOCK_ERR_INVALID;
    if (cosmeticOwned(&g.world, cosmetic)) return DOCK_ERR_ALREADY;
    if (!cosmeticUnlocked(&g.world, cosmetic)) return DOCK_ERR_LOCKED;

    const row = tables.cosmetics()[@intCast(usize, cosmetic)];
    const wp = &g.world;
    if (wp.money < row.price) return DOCK_ERR_COINS;

    wp.money -= row.price;
    wp.cosmetics_owned = wp.cosmetics_owned | cosmeticBit(cosmetic);
    world.advancePhase(&g.world);
    return DOCK_OK;
}

// Select the equipped tool (P22.5): free, no phase, requires ownership.
// Tool 0 clears the selection.
pub fn dockSelectTool(g: *def.GameState, tool: i32) i32 {
    if (tool < 0 or tool > 7) return DOCK_ERR_INVALID;
    if (tool != 0 and !items.toolOwned(&g.world, tool)) return DOCK_ERR_NOT_OWNED;
    g.world.tool_selected = tool;
    return DOCK_OK;
}
