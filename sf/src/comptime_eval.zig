const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const AstNode = @import("ast.zig").AstNode;
const StringInterner = @import("string_interner.zig").StringInterner;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const type_mod = @import("type_registry.zig");
const ast_mod = @import("ast.zig");
const interner_mod = @import("string_interner.zig");
const type_resolver = @import("type_resolver.zig");

pub const ComptimeVal = struct {
    bits: u64,
    width_bits: u8,
    sig: bool,
};

pub const ComptimeEval = struct {
    registry: *TypeRegistry,
    store: *AstStore,
    interner: *StringInterner,
    symbol_reg: *SymbolRegistry,
    size_of_id: u32,
    align_of_id: u32,
    int_cast_id: u32,
};

pub fn comptimeEvalInit(registry: *TypeRegistry, store: *AstStore, interner: *StringInterner, symbol_reg: *SymbolRegistry) ComptimeEval {
    var s_size: []const u8 = "@sizeOf";
    var s_align: []const u8 = "@alignOf";
    var s_intc: []const u8 = "@intCast";
    var size_id = interner_mod.stringInternerIntern(interner, s_size);
    var align_id = interner_mod.stringInternerIntern(interner, s_align);
    var intc_id = interner_mod.stringInternerIntern(interner, s_intc);
    return ComptimeEval{
        .registry = registry, .store = store, .interner = interner, .symbol_reg = symbol_reg,
        .size_of_id = size_id, .align_of_id = align_id, .int_cast_id = intc_id,
    };
}

fn comptimeEvalBinOp(self: *ComptimeEval, node_idx: u32, op_kind: AstKind) ?ComptimeVal {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = comptimeEvalEvaluate(self, node.child_0);
    var rhs = comptimeEvalEvaluate(self, node.child_1);
    if (lhs) |l| {
        if (rhs) |r| {
            var lv: u64 = l.bits;
            var rv: u64 = r.bits;
            var use_signed = l.sig or r.sig;
            var maxw: u8 = l.width_bits;
            if (r.width_bits > maxw) { maxw = r.width_bits; }
            if (op_kind == AstKind.add) return ComptimeVal{ .bits = lv + rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.sub) return ComptimeVal{ .bits = lv - rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.mul) return ComptimeVal{ .bits = lv * rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.div) {
                if (rv == @intCast(u64, 0)) return null;
                if (use_signed) {
                    var sl: u64 = (lv >> @intCast(u64, 63)) & @intCast(u64, 1);
                    var sr: u64 = (rv >> @intCast(u64, 63)) & @intCast(u64, 1);
                    var al: u64 = undefined; var ar: u64 = undefined;
                    if (sl == @intCast(u64, 1)) { al = @intCast(u64, 0) - lv; } else { al = lv; }
                    if (sr == @intCast(u64, 1)) { ar = @intCast(u64, 0) - rv; } else { ar = rv; }
                    var q: u64 = al / ar;
                    if (sl != sr) { q = @intCast(u64, 0) - q; }
                    return ComptimeVal{ .bits = q, .width_bits = maxw, .sig = true };
                }
                return ComptimeVal{ .bits = lv / rv, .width_bits = maxw, .sig = false };
            }
            if (op_kind == AstKind.mod_op) {
                if (rv == @intCast(u64, 0)) return null;
                if (use_signed) {
                    var sl: u64 = (lv >> @intCast(u64, 63)) & @intCast(u64, 1);
                    var sr: u64 = (rv >> @intCast(u64, 63)) & @intCast(u64, 1);
                    var al: u64 = undefined; var ar: u64 = undefined;
                    if (sl == @intCast(u64, 1)) { al = @intCast(u64, 0) - lv; } else { al = lv; }
                    if (sr == @intCast(u64, 1)) { ar = @intCast(u64, 0) - rv; } else { ar = rv; }
                    var rem: u64 = al % ar;
                    if (sl == @intCast(u64, 1)) { rem = @intCast(u64, 0) - rem; }
                    return ComptimeVal{ .bits = rem, .width_bits = maxw, .sig = true };
                }
                return ComptimeVal{ .bits = lv % rv, .width_bits = maxw, .sig = false };
            }
            if (op_kind == AstKind.bit_and) return ComptimeVal{ .bits = lv & rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.bit_or) return ComptimeVal{ .bits = lv | rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.bit_xor) return ComptimeVal{ .bits = lv ^ rv, .width_bits = maxw, .sig = use_signed };
            if (op_kind == AstKind.shl) {
                if (rv >= @intCast(u64, 64)) return null;
                return ComptimeVal{ .bits = lv << rv, .width_bits = maxw, .sig = use_signed };
            }
            if (op_kind == AstKind.shr) {
                if (rv >= @intCast(u64, 64)) return null;
                return ComptimeVal{ .bits = lv >> rv, .width_bits = maxw, .sig = use_signed };
            }
        }
    }
    return null;
}

fn comptimeEvalResolveTypeArg(self: *ComptimeEval, node_idx: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    var env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbol_reg, .interner = self.interner };
    var tid = type_resolver.resolveTypeExprFull(&env, node_idx, @intCast(u32, 0));
    if (tid == type_mod.TYPE_UNDEFINED) return null;
    return tid;
}

fn comptimeEvalBuiltin(self: *ComptimeEval, node: AstNode) ?ComptimeVal {
    if (node.child_0 == self.size_of_id) {
        var ec: []const u32 = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var tid = comptimeEvalResolveTypeArg(self, ec[@intCast(usize, 0)]);
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ComptimeVal{ .bits = @intCast(u64, ty.size), .width_bits = @intCast(u8, 0), .sig = false };
        }
        return null;
    }
    if (node.child_0 == self.align_of_id) {
        var ec: []const u32 = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var tid = comptimeEvalResolveTypeArg(self, ec[@intCast(usize, 0)]);
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ComptimeVal{ .bits = @intCast(u64, ty.alignment), .width_bits = @intCast(u8, 0), .sig = false };
        }
        return null;
    }
    if (node.child_0 == self.int_cast_id) {
        var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var tid = comptimeEvalResolveTypeArg(self, ec[@intCast(usize, 0)]);
        var inner = comptimeEvalEvaluate(self, ec[@intCast(usize, 1)]);
        if (tid) |t| {
            if (inner) |cv| {
                var ty = self.registry.types_items[@intCast(usize, t)];
                var wb: u8 = @intCast(u8, ty.size * @intCast(u32, 8));
                var sig: bool = (ty.kind == type_mod.TypeKind.i8_type or ty.kind == type_mod.TypeKind.i16_type or ty.kind == type_mod.TypeKind.i32_type or ty.kind == type_mod.TypeKind.i64_type or ty.kind == type_mod.TypeKind.isize_type);
                if (wb == @intCast(u8, 64)) {
                    return ComptimeVal{ .bits = cv.bits, .width_bits = wb, .sig = sig };
                }
                var mask: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
                var masked = cv.bits & mask;
                if (sig and (cv.bits & (@intCast(u64, 1) << @intCast(u64, wb - @intCast(u8, 1)))) != @intCast(u64, 0)) {
                    var not_mask: u64 = (@intCast(u64, 0) - mask) - @intCast(u64, 1);
                    masked = cv.bits | not_mask;
                }
                return ComptimeVal{ .bits = masked, .width_bits = wb, .sig = sig };
            }
        }
        return null;
    }
    return null;
}

pub fn comptimeEvalEvaluate(self: *ComptimeEval, node_idx: u32) ?ComptimeVal {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.int_literal) {
        return ComptimeVal{ .bits = self.store.int_values.items[@intCast(usize, node.payload)], .width_bits = @intCast(u8, 0), .sig = true };
    } else if (node.kind == AstKind.char_literal) {
        return ComptimeVal{ .bits = self.store.int_values.items[@intCast(usize, node.payload)], .width_bits = @intCast(u8, 8), .sig = false };
    } else if (node.kind == AstKind.bool_literal) {
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) return ComptimeVal{ .bits = @intCast(u64, 1), .width_bits = @intCast(u8, 1), .sig = false };
        return ComptimeVal{ .bits = @intCast(u64, 0), .width_bits = @intCast(u8, 1), .sig = false };
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalEvaluate(self, node.child_0);
        if (inner) |cv| {
            var nv: u64 = @intCast(u64, 0) - cv.bits;
            if (cv.width_bits != @intCast(u8, 0)) {
                var wb: u8 = cv.width_bits;
                if (wb == @intCast(u8, 64)) {
                    return ComptimeVal{ .bits = nv, .width_bits = wb, .sig = cv.sig };
                }
                var mask: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
                var masked = nv & mask;
                if (cv.sig and (nv & (@intCast(u64, 1) << @intCast(u64, wb - @intCast(u8, 1)))) != @intCast(u64, 0)) {
                    var not_mask: u64 = (@intCast(u64, 0) - mask) - @intCast(u64, 1);
                    masked = nv | not_mask;
                }
                return ComptimeVal{ .bits = masked, .width_bits = wb, .sig = cv.sig };
            }
            return ComptimeVal{ .bits = nv, .width_bits = @intCast(u8, 0), .sig = true };
        }
        return null;
    } else if (node.kind == AstKind.bit_not) {
        var bnv = comptimeEvalEvaluate(self, node.child_0);
        if (bnv) |bv| {
            var bnb = ~bv.bits;
            return ComptimeVal{ .bits = bnb, .width_bits = bv.width_bits, .sig = false };
        }
        return null;
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
               node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
               node.kind == AstKind.shl or node.kind == AstKind.shr) {
        return comptimeEvalBinOp(self, node_idx, node.kind);
    } else if (node.kind == AstKind.builtin_call) {
        return comptimeEvalBuiltin(self, node);
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalEvaluate(self, node.child_0);
    } else {
        return null;
    }
}
