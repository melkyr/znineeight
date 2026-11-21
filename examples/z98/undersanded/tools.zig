// tools.zig — UNDERSANDED tool lifecycle helpers (spec §10, P22.2/P22.5).
//
// Id/kind/ownership live in items.zig; this module keeps the public lifecycle
// API and owns only the behaviour that depends on the current GameState:
// EQUIP gating and the fragile-tool break roll. No I/O, no RNG, flat state.

const def = @import("def.zig");
const world = @import("world.zig");
const items = @import("items.zig");

// §10 fragile rule: Precision T2+ and one incoming hit of at least 15 Hull.
pub const FRAGILE_MIN_PRECISION_TIER: i32 = 2;
pub const FRAGILE_MIN_HIT: i32 = 15;

// EQUIP refusal reasons (spec §7.1); 0 means the tool can be activated.
pub const REFUSE_NONE: i32 = 0;
pub const REFUSE_NO_TOOL: i32 = 1;
pub const REFUSE_BROKEN: i32 = 2;
pub const REFUSE_NO_CHARGE: i32 = 3;
pub const REFUSE_RIGGED: i32 = 4;

pub fn isRigged(tool: i32) bool {
    return items.isRigged(tool);
}

pub fn isActivated(tool: i32) bool {
    return items.isActivated(tool);
}

// Owned-tool bits are keyed by tool id (R6: tool 1..7 -> bit 1..7).
pub fn isOwned(w: *const def.World, tool: i32) bool {
    return items.toolOwned(w, tool);
}

// Activated tools only: one charge per expedition, spent via EQUIP. Rigged
// tools are always on at fight start and are never valid EQUIP targets.
pub fn equipRefusal(g: *const def.GameState, tool: i32) i32 {
    if (tool == 0) return REFUSE_NO_TOOL;
    if (g.fight.tool != tool and g.exp.tool != tool) return REFUSE_NO_TOOL;
    if (!isOwned(&g.world, tool)) return REFUSE_NO_TOOL;
    if (g.fight.tool_broken != 0 or g.exp.tool_broken != 0) return REFUSE_BROKEN;
    if (!isActivated(tool)) return REFUSE_RIGGED;
    if (g.fight.tool_active != 0) return REFUSE_NO_CHARGE;

    var charge = g.exp.tool_charge;
    if (g.fight.tool == tool) charge = g.fight.tool_charge;
    if (charge <= 0) return REFUSE_NO_CHARGE;
    return REFUSE_NONE;
}

pub fn canEquip(g: *const def.GameState, tool: i32) bool {
    return equipRefusal(g, tool) == REFUSE_NONE;
}

// One incoming creature hit: at Precision T2+ a hit of 15+ Hull disables the
// equipped tool for the rest of the expedition. The break is copied into the
// Expedition so it survives the fight and clears only at the next Depart.
pub fn onHullHit(g: *def.GameState, dmg: i32) void {
    if (dmg < FRAGILE_MIN_HIT) return;
    if (g.world.boat[world.BOAT_PRECISION] < FRAGILE_MIN_PRECISION_TIER) return;
    if (g.fight.tool == 0 and g.exp.tool == 0) return;
    if (g.fight.tool_broken != 0 or g.exp.tool_broken != 0) return;

    const broken_tool = if (g.fight.tool != 0) g.fight.tool else g.exp.tool;
    g.fight.tool_broken = 1;
    g.fight.tool_active = 0;
    g.exp.tool_broken = 1;
    def.appendLog(g, def.LOG_NORMAL, def.MSG_TOOL_BROKEN, broken_tool, 0);
}
