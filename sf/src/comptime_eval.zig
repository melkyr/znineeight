const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const AstNode = @import("ast.zig").AstNode;
const StringInterner = @import("string_interner.zig").StringInterner;
const type_mod = @import("type_registry.zig");

pub const ComptimeEval = struct {
    registry: *TypeRegistry,
    store: *AstStore,
    interner: *StringInterner,
};

pub fn comptimeEvalInit(registry: *TypeRegistry, store: *AstStore, interner: *StringInterner) ComptimeEval {
    return ComptimeEval{ .registry = registry, .store = store, .interner = interner };
}

fn comptimeEvalBinOp(self: *ComptimeEval, node_idx: u32, op_kind: AstKind) ?u64 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = comptimeEvalEvaluate(self, node.child_0);
    var rhs = comptimeEvalEvaluate(self, node.child_1);
    var lv: u64;
    var rv: u64;
    if (lhs) |l| { lv = l; } else return null;
    if (rhs) |r| { rv = r; } else return null;
    if (op_kind == AstKind.add) return lv + rv;
    if (op_kind == AstKind.sub) return lv - rv;
    if (op_kind == AstKind.mul) return lv * rv;
    if (op_kind == AstKind.div) {
        if (rv == @intCast(u64, 0)) return null;
        return lv / rv;
    }
    if (op_kind == AstKind.mod_op) {
        if (rv == @intCast(u64, 0)) return null;
        return lv % rv;
    }
    return null;
}

fn comptimeEvalBuiltin(self: *ComptimeEval, node: AstNode) ?u64 {
    _ = self;
    _ = node;
    return null;
}

pub fn comptimeEvalEvaluate(self: *ComptimeEval, node_idx: u32) ?u64 {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.int_literal) {
            return self.store.int_values.items[@intCast(usize, node.payload)];
    } else if (node.kind == AstKind.char_literal) {
        var cv: u64 = @intCast(u64, node.payload);
        return cv;
    } else if (node.kind == AstKind.bool_literal) {
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) return @intCast(u64, 1);
        return @intCast(u64, 0);
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalEvaluate(self, node.child_0);
        if (inner) |v| {
            var nv: u64 = @intCast(u64, 0) - v;
            return nv;
        }
        return null;
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op) {
        return comptimeEvalBinOp(self, node_idx, node.kind);
    } else if (node.kind == AstKind.builtin_call) {
        return comptimeEvalBuiltin(self, node);
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalEvaluate(self, node.child_0);
    } else {
        return null;
    }
}
