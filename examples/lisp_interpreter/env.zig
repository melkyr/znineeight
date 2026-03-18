const value_mod = @import("value.zig");
const util = @import("util.zig");

pub const EnvNode = struct {
    symbol: []const u8,
    value: *value_mod.Value,
    next: ?*EnvNode,
};

pub fn env_lookup(name: []const u8, env: ?*EnvNode) !*value_mod.Value {
    var cur = env;
    while (true) {
        if (cur) |node| {
            if (util.mem_eql(node.symbol, name)) {
                return node.value;
            }
            cur = node.next;
        } else {
            break;
        }
    }
    return error.UnboundSymbol;
}

pub fn env_extend(name: []const u8, val: *value_mod.Value, env: ?*EnvNode, arena: *value_mod.arena_mod.LispArena) !*EnvNode {
    const node_mem = try value_mod.arena_mod.lisp_alloc(arena, @sizeOf(EnvNode), @alignOf(EnvNode));
    const node = @ptrCast(*EnvNode, node_mem);
    node.symbol = name;
    node.value = val;
    node.next = env;
    return node;
}
