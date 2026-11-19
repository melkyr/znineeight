// tools.zig — UNDERSANDED tool lifecycle helpers (spec §10, P22.2/P22.5).
//
// Every id/kind/cost reads `tables_t1.TOOLS`; this module only owns the
// behaviour that depends on the current GameState: ownership, EQUIP gating,
// and the fragile-tool break roll. No I/O, no RNG, flat state only.

const def = @import("def.zig");
const world = @import("world.zig");
const tables = @import("tables_t1.zig");

// §10 fragile rule: Precision T2+ and one incoming hit of at least 15 Hull.
pub const FRAGILE_MIN_PRECISION_TIER: i32 = 2;
pub const FRAGILE_MIN_HIT: i32 = 15;

fn findKind(tool: i32) i32 {
    const rows = tables.tools();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (rows[i].id == tool) return rows[i].kind;
    }
    return -1;
}

pub fn isRigged(tool: i32) bool {
    return findKind(tool) == tables.TOOL_KIND_RIGGED;
}

pub fn isActivated(tool: i32) bool {
    return findKind(tool) == tables.TOOL_KIND_ACTIVATED;
}

// Owned-tool bits are keyed by tool id (R6: tool 1..7 -> bit 1..7).
pub fn isOwned(w: *const def.World, tool: i32) bool {
    if (tool < 1 or tool > 7) return false;
    const bit: u32 = @intCast(u32, tool);
    const mask: u32 = @intCast(u32, 1) << bit;
    return (w.tools_owned & mask) != 0;
}

// Activated tools only: one charge per expedition, spent via EQUIP. Rigged
// tools are always on at fight start and are never valid EQUIP targets.
pub fn canEquip(g: *const def.GameState, tool: i32) bool {
    if (!isActivated(tool)) return false;
    if (!isOwned(&g.world, tool)) return false;
    if (g.fight.tool != tool and g.exp.tool != tool) return false;
    if (g.fight.tool_broken != 0 or g.exp.tool_broken != 0) return false;
    if (g.fight.tool_active != 0) return false;

    var charge = g.exp.tool_charge;
    if (g.fight.tool == tool) charge = g.fight.tool_charge;
    if (charge <= 0) return false;
    return true;
}

// One incoming creature hit: at Precision T2+ a hit of 15+ Hull disables the
// equipped tool for the rest of the expedition. The break is copied into the
// Expedition so it survives the fight and clears only at the next Depart.
pub fn onHullHit(g: *def.GameState, dmg: i32) void {
    if (dmg < FRAGILE_MIN_HIT) return;
    if (g.world.boat[world.BOAT_PRECISION] < FRAGILE_MIN_PRECISION_TIER) return;
    if (g.fight.tool == 0 and g.exp.tool == 0) return;
    if (g.fight.tool_broken != 0 or g.exp.tool_broken != 0) return;

    g.fight.tool_broken = 1;
    g.fight.tool_active = 0;
    g.exp.tool_broken = 1;
}
