const value_mod = @import("value.zig");
const util = @import("util.zig");
const sand_mod = @import("sand.zig");

pub const EnvNode = struct {
    symbol: []const u8,
    value: *value_mod.Value,
    next: ?*EnvNode,
};

pub fn env_lookup(name: []const u8, env: ?*EnvNode) anyerror!*value_mod.Value {
    var cur: ?*EnvNode = env;
    while (cur) |node| {
        if (util.mem_eql(node.symbol, name)) {
            return node.value;
        }
        cur = node.next;
    }
    return error.UnboundSymbol;
}

pub fn env_extend(name: []const u8, val: *value_mod.Value, env: ?*EnvNode, sand: *sand_mod.LispSand) anyerror!*EnvNode {
    const node_mem = try sand_mod.lisp_sand_alloc(sand, @sizeOf(EnvNode), @alignOf(EnvNode));
    const node = @ptrCast(*EnvNode, node_mem);
    node.symbol = name;
    node.value = val;
    node.next = env;
    return node;
}
