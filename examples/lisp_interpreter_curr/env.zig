const value_mod = @import("value.zig");
const sand_mod = @import("sand.zig");
const util = @import("util.zig");

pub const EnvNode = struct {
    symbol: []const u8,
    value: *value_mod.Value,
    next: ?*EnvNode,
};

pub fn env_lookup(name: []const u8, env: ?*EnvNode) util.LispError!*value_mod.Value {
    var cur = env;
    while (cur) |node| {
        if (util.mem_eql(node.symbol, name)) {
            return node.value;
        }
        cur = node.next;
    }
    return error.UnboundSymbol;
}

pub fn env_extend(name: []const u8, val: *value_mod.Value, env: ?*EnvNode, arena: *sand_mod.Sand) util.LispError!*EnvNode {
    const mem = try sand_mod.sand_alloc(arena, @sizeOf(EnvNode), @alignOf(EnvNode));
    const node = @ptrCast(*EnvNode, mem);
    node.symbol = name;
    node.value = val;
    node.next = env;
    return node;
}
