// items.zig — UNDERSANDED tool ownership/kind owner (spec §10, §14.5).
//
// Single source for owned-tool bits and tool-row kind lookup. No I/O, no
// rendering; dock/expedition/tools/fight consume this module.

const def = @import("def.zig");
const tables = @import("tables_t1.zig");

pub fn toolKind(tool: i32) i32 {
    const rows = tables.tools();
    var i: usize = 0;
    while (i < rows.len) : (i += 1) {
        if (rows[i].id == tool) return rows[i].kind;
    }
    return -1;
}

pub fn isRigged(tool: i32) bool {
    return toolKind(tool) == def.TOOL_KIND_RIGGED;
}

pub fn isActivated(tool: i32) bool {
    return toolKind(tool) == def.TOOL_KIND_ACTIVATED;
}

// Owned-tool bits are keyed by tool id (R6: tool 1..7 -> bit 1..7).
pub fn toolOwned(w: *const def.World, tool: i32) bool {
    if (tool < 1 or tool > 7) return false;
    const bit: u32 = @intCast(u32, tool);
    const mask: u32 = @intCast(u32, 1) << bit;
    return (w.tools_owned & mask) != 0;
}
