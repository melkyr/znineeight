const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const AstNode = @import("ast.zig").AstNode;
const StringInterner = @import("string_interner.zig").StringInterner;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const sym_mod = @import("symbol_table.zig");
const type_mod = @import("type_registry.zig");
const ast_mod = @import("ast.zig");
const interner_mod = @import("string_interner.zig");
const type_resolver = @import("type_resolver.zig");
const diag_mod = @import("diagnostics.zig");

pub const ComptimeVal = struct {
    bits: u64,
    width_bits: u32,
    sig: bool,
};

// Float-valued folds carry this distinctive width_bits sentinel so the integer
// fold operators (binop / negate / bit_not / int_cast) reject them: a float's
// IEEE-754 bit pattern must never enter integer arithmetic. No integer fold can
// legitimately carry this width (literal=0, char=8, bool=1, intCast<=64).
const WIDTH_FLOAT: u32 = @intCast(u32, 4294967295);

pub const ComptimeEval = struct {
    registry: *TypeRegistry,
    store: *AstStore,
    interner: *StringInterner,
    symbol_reg: *SymbolRegistry,
    size_of_id: u32,
    align_of_id: u32,
    offset_of_id: u32,
    bit_size_of_id: u32,
    bit_offset_of_id: u32,
    int_cast_id: u32,
    as_id: u32,
    float_cast_id: u32,
    int_to_float_id: u32,
    is_windows_id: u32,
    host_is_windows: bool,
    // Task 9D (Gap B): the enclosing function's local-const scope, consulted by
    // the ident_expr arm before the module symbol registry so a function-local
    // `const` participates in the fold (mirrors type_resolver's evalConstU32Full
    // variant (e)). null outside a function body or when the caller has no scope.
    local_consts: ?*type_resolver.LocalConstScope,
    // Task 11S (c): the fold pass may reject an out-of-range comptime
    // `@intCast` (error[3000]); null when no collector is available.
    diag: ?*diag_mod.DiagnosticCollector,
};

pub fn comptimeEvalInit(registry: *TypeRegistry, store: *AstStore, interner: *StringInterner, symbol_reg: *SymbolRegistry) ComptimeEval {
    var s_size: []const u8 = "@sizeOf";
    var s_align: []const u8 = "@alignOf";
    var s_intc: []const u8 = "@intCast";
    var intc_id = interner_mod.stringInternerIntern(interner, s_intc);
    var s_as: []const u8 = "@as";
    var as_id = interner_mod.stringInternerIntern(interner, s_as);
    var s_fc: []const u8 = "@floatCast";
    var fc_id = interner_mod.stringInternerIntern(interner, s_fc);
    var s_itf: []const u8 = "@intToFloat";
    var itf_id = interner_mod.stringInternerIntern(interner, s_itf);
    var size_id = interner_mod.stringInternerIntern(interner, s_size);
    var align_id = interner_mod.stringInternerIntern(interner, s_align);
    var s_off: []const u8 = "@offsetOf";
    var s_bitsz: []const u8 = "@bitSizeOf";
    var s_bitoff: []const u8 = "@bitOffsetOf";
    var off_id = interner_mod.stringInternerIntern(interner, s_off);
    var bitsz_id = interner_mod.stringInternerIntern(interner, s_bitsz);
    var bitoff_id = interner_mod.stringInternerIntern(interner, s_bitoff);
    var s_iw: []const u8 = "@isWindows";
    var iw_id = interner_mod.stringInternerIntern(interner, s_iw);
    return ComptimeEval{
        .registry = registry, .store = store, .interner = interner, .symbol_reg = symbol_reg,
        .size_of_id = size_id, .align_of_id = align_id, .int_cast_id = intc_id, .as_id = as_id,
        .float_cast_id = fc_id, .int_to_float_id = itf_id,
        .offset_of_id = off_id, .bit_size_of_id = bitsz_id, .bit_offset_of_id = bitoff_id,
        .is_windows_id = iw_id,
        .host_is_windows = false,
        .local_consts = null,
        .diag = null,
    };
}

fn comptimeEvalBinOp(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    var rhs = comptimeEvalEvaluateDepth(self, node.child_1, depth);
    if (lhs) |l| {
        if (rhs) |r| {
            if (l.width_bits == WIDTH_FLOAT or r.width_bits == WIDTH_FLOAT) return null;
            var lv: u64 = l.bits;
            var rv: u64 = r.bits;
            var use_signed = l.sig or r.sig;
            var maxw: u32 = l.width_bits;
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

// Task 9D: fold a comparison (`==`/`!=`/`<`/`<=`/`>`/`>=`) of two comptime
// integers to a bool ComptimeVal. Both operands must fold; a float operand
// (WIDTH_FLOAT) is a bounded residual and stays unfolded. Signedness is the
// DECLARED integer type of a typed operand (fix round 1): a `u64` const above
// i64 max must compare UNSIGNED, not by the initializer literal's `sig`. With no
// declared type on either side, a syntactically definitely-negative operand
// makes the comparison signed (so `-1 < 0` holds and `18446744073709551615 > 0`
// compares unsigned).
fn comptimeEvalCompare(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    var rhs = comptimeEvalEvaluateDepth(self, node.child_1, depth);
    if (lhs) |l| {
        if (rhs) |r| {
            if (l.width_bits == WIDTH_FLOAT or r.width_bits == WIDTH_FLOAT) return null;
            var use_signed: bool = false;
            var have_decl: bool = false;
            if (comptimeEvalOperandDeclaredSigned(self, node.child_0)) |ls| {
                use_signed = ls;
                have_decl = true;
            }
            if (comptimeEvalOperandDeclaredSigned(self, node.child_1)) |rs| {
                if (have_decl) { use_signed = use_signed or rs; } else { use_signed = rs; have_decl = true; }
            }
            if (!have_decl) {
                if (comptimeEvalSignClass(self, node.child_0, @intCast(u32, 0)) == SignClass.negative) use_signed = true;
                if (comptimeEvalSignClass(self, node.child_1, @intCast(u32, 0)) == SignClass.negative) use_signed = true;
            }
            var res: bool = false;
            if (use_signed) {
                var sl: i64 = @bitCast(i64, l.bits);
                var sr: i64 = @bitCast(i64, r.bits);
                if (op_kind == AstKind.cmp_eq) res = sl == sr;
                if (op_kind == AstKind.cmp_ne) res = sl != sr;
                if (op_kind == AstKind.cmp_lt) res = sl < sr;
                if (op_kind == AstKind.cmp_le) res = sl <= sr;
                if (op_kind == AstKind.cmp_gt) res = sl > sr;
                if (op_kind == AstKind.cmp_ge) res = sl >= sr;
            } else {
                if (op_kind == AstKind.cmp_eq) res = l.bits == r.bits;
                if (op_kind == AstKind.cmp_ne) res = l.bits != r.bits;
                if (op_kind == AstKind.cmp_lt) res = l.bits < r.bits;
                if (op_kind == AstKind.cmp_le) res = l.bits <= r.bits;
                if (op_kind == AstKind.cmp_gt) res = l.bits > r.bits;
                if (op_kind == AstKind.cmp_ge) res = l.bits >= r.bits;
            }
            var rb: u64 = @intCast(u64, 0);
            if (res) rb = @intCast(u64, 1);
            return ComptimeVal{ .bits = rb, .width_bits = @intCast(u32, 1), .sig = false };
        }
    }
    return null;
}

// Task 9D: fold `and`/`or`/`!` on comptime bools. `and`/`or` short-circuit:
// when the lhs folds, a decisive lhs (`0` for `and`, `1` for `or`) returns
// without evaluating the rhs; when the lhs does NOT fold, a decisive RHS still
// decides (`<runtime> or true` -> true, `<runtime> and false` -> false) without
// requiring the lhs — matching Zig's comptime-known-true acceptance (fix round
// 1). Any other operand that does not fold, or is not bool-width, yields null.
fn comptimeEvalLogical(self: *ComptimeEval, node_idx: u32, op_kind: AstKind, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var lhs = comptimeEvalEvaluateDepth(self, node.child_0, depth);
    if (op_kind == AstKind.bool_not) {
        if (lhs) |l| {
            if (l.width_bits != @intCast(u32, 1)) return null;
            var nb: u64 = @intCast(u64, 1) - (l.bits & @intCast(u64, 1));
            return ComptimeVal{ .bits = nb, .width_bits = @intCast(u32, 1), .sig = false };
        }
        return null;
    }
    if (op_kind == AstKind.bool_and) {
        if (lhs) |l| {
            if (l.width_bits != @intCast(u32, 1)) return null;
            if (l.bits == @intCast(u64, 0)) return ComptimeVal{ .bits = @intCast(u64, 0), .width_bits = @intCast(u32, 1), .sig = false };
            var rhs_a = comptimeEvalEvaluateDepth(self, node.child_1, depth);
            if (rhs_a) |ra| {
                if (ra.width_bits != @intCast(u32, 1)) return null;
                return ComptimeVal{ .bits = ra.bits & @intCast(u64, 1), .width_bits = @intCast(u32, 1), .sig = false };
            }
            return null;
        }
        // lhs does not fold: a false rhs decides the conjunction.
        if (comptimeEvalEvaluateDepth(self, node.child_1, depth)) |ra2| {
            if (ra2.width_bits != @intCast(u32, 1)) return null;
            if (ra2.bits == @intCast(u64, 0)) return ComptimeVal{ .bits = @intCast(u64, 0), .width_bits = @intCast(u32, 1), .sig = false };
        }
        return null;
    }
    if (op_kind == AstKind.bool_or) {
        if (lhs) |l| {
            if (l.width_bits != @intCast(u32, 1)) return null;
            if (l.bits != @intCast(u64, 0)) return ComptimeVal{ .bits = @intCast(u64, 1), .width_bits = @intCast(u32, 1), .sig = false };
            var rhs_o = comptimeEvalEvaluateDepth(self, node.child_1, depth);
            if (rhs_o) |ro| {
                if (ro.width_bits != @intCast(u32, 1)) return null;
                return ComptimeVal{ .bits = ro.bits & @intCast(u64, 1), .width_bits = @intCast(u32, 1), .sig = false };
            }
            return null;
        }
        // lhs does not fold: a true rhs decides the disjunction.
        if (comptimeEvalEvaluateDepth(self, node.child_1, depth)) |ro2| {
            if (ro2.width_bits != @intCast(u32, 1)) return null;
            if (ro2.bits != @intCast(u64, 0)) return ComptimeVal{ .bits = @intCast(u64, 1), .width_bits = @intCast(u32, 1), .sig = false };
        }
        return null;
    }
    return null;
}

// Task 9D fix round 1: the DECLARED integer signedness of a comparison operand,
// or null when the operand has no declared integer type (an untyped comptime_int
// literal / expression). Unlike `comptimeEvalOperandSigned`, this does not fall
// back to `cv.sig`, and it consults the function-local const scope first (Task
// 9D Gap B): a function-local `u64` const above i64 max must compare UNSIGNED.
fn comptimeEvalOperandDeclaredSigned(self: *ComptimeEval, node_idx: u32) ?bool {
    var idx = node_idx;
    var guard: u32 = 0;
    while (guard < @intCast(u32, 32)) : (guard += 1) {
        var wn = ast_mod.astStoreNodeAt(self.store, idx);
        if (wn.kind == AstKind.paren_expr) { idx = wn.child_0; } else { break; }
    }
    var node = ast_mod.astStoreNodeAt(self.store, idx);
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, idx);
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (comptimeEvalResolveTypeArg(self, l_decl.child_0)) |lt| {
                    if (type_mod.typeRegistryIsInteger(self.registry, lt)) return type_mod.typeRegistryIntIsSigned(self.registry, lt);
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (comptimeEvalResolveTypeArg(self, c_decl.child_0)) |t| {
                        if (type_mod.typeRegistryIsInteger(self.registry, t)) return type_mod.typeRegistryIntIsSigned(self.registry, t);
                    }
                }
            }
        }
        return null;
    }
    if (node.kind == AstKind.char_literal) return false;
    if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
            if (comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, idx, @intCast(u32, 0)))) |t2| {
                if (type_mod.typeRegistryIsInteger(self.registry, t2)) return type_mod.typeRegistryIntIsSigned(self.registry, t2);
            }
        }
        return null;
    }
    return null;
}

fn comptimeEvalResolveTypeArg(self: *ComptimeEval, node_idx: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    var env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbol_reg, .interner = self.interner, .module_id = type_resolver.MODULE_ID_NONE, .source_file_id = @intCast(u32, 0), .diag = null, .local_consts = null, .local_types = null };
    var tid = type_resolver.resolveTypeExprFull(&env, node_idx, @intCast(u32, 0));
    if (tid == type_mod.TYPE_UNDEFINED) return null;
    return tid;
}

// Task 11S (c): does the folded value `cv` fit the integer type `t`? The
// comptime `@intCast` arm used to mask to the target width, silently folding
// `@intCast(u8, 300)` to 44. A negative source never fits an unsigned target;
// a positive source must not exceed the target's max. Widths >= 64 are left
// alone (no masking, existing behavior preserved).
//
// M3 note: this intentionally mirrors `type_resolver.intValueFitsType` (same
// width/signedness range rule) because the two evaluators hold values in
// different representations (`ComptimeVal` bits+sig vs `i64`); a shared helper
// would need a conversion shim, so the small duplication is deliberate.
//
// Task B3 item 2: a 64-bit target is no longer a blanket accept. The 64-bit
// bit pattern alone cannot distinguish a negative source from a large
// non-negative literal (both have the top bit set), so the OPERAND is
// classified syntactically (see `comptimeEvalSignClass`): a definitely-negative
// source cannot fit an unsigned 64-bit target, and a definitely-non-negative
// source above i64 max cannot fit a signed 64-bit target. An unrecognized shape
// (`unknown`) is never rejected (no over-rejection of valid programs).
fn comptimeValFitsType(self: *ComptimeEval, cv: ComptimeVal, t: u32, operand_idx: u32) bool {
    if (!type_mod.typeRegistryIsInteger(self.registry, t)) return false;
    var wb: u32 = @intCast(u32, type_mod.typeRegistryIntWidthBits(self.registry, t));
    if (wb >= @intCast(u32, 64)) {
        var sc64 = comptimeEvalSignClass(self, operand_idx, @intCast(u32, 0));
        var sval64: i64 = @bitCast(i64, cv.bits);
        if (type_mod.typeRegistryIntIsSigned(self.registry, t)) {
            if (sc64 == SignClass.non_negative and sval64 < @intCast(i64, 0)) return false;
            return true;
        }
        if (sc64 == SignClass.negative and sval64 < @intCast(i64, 0)) return false;
        return true;
    }
    if (wb == @intCast(u32, 0)) return false;
    var tsig: bool = type_mod.typeRegistryIntIsSigned(self.registry, t);
    var sval: i64 = @bitCast(i64, cv.bits);
    if (sval < @intCast(i64, 0)) {
        if (!tsig) return false;
        var mag: u64 = @intCast(u64, @intCast(i64, 0) - sval);
        var smin_mag: u64 = @intCast(u64, 1) << @intCast(u64, wb - @intCast(u32, 1));
        return mag <= smin_mag;
    }
    if (tsig) {
        var smax: u64 = (@intCast(u64, 1) << @intCast(u64, wb - @intCast(u32, 1))) - @intCast(u64, 1);
        return cv.bits <= smax;
    }
    var umax: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
    return cv.bits <= umax;
}
// Task B3 item 2: syntactic sign classification of a cast operand, used only
// by the 64-bit range check in `comptimeValFitsType`. Unlike
// `comptimeEvalOperandSigned` (which collapses every unclassified shape to
// `cv.sig`), this is a tri-state so an unrecognized shape is NOT treated as
// either sign. int/char/bool literals are comptime_int non-negative; a
// `negate` is negative; an ident or `@as`/`@intCast` is classified by its
// declared/target integer type, recursing into a const initializer when no
// declared type is present.
const SignClass = enum(u8) { unknown, negative, non_negative };

fn comptimeEvalSignClass(self: *ComptimeEval, node_idx: u32, depth: u32) SignClass {
    if (node_idx == @intCast(u32, 0)) return SignClass.unknown;
    if (depth >= @intCast(u32, 16)) return SignClass.unknown;
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.int_literal or node.kind == AstKind.char_literal or node.kind == AstKind.bool_literal) return SignClass.non_negative;
    if (node.kind == AstKind.negate) return SignClass.negative;
    if (node.kind == AstKind.paren_expr) return comptimeEvalSignClass(self, node.child_0, depth + @intCast(u32, 1));
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
        // Task 9D fix round 1: consult the function-local const scope first
        // (mirrors the ident_expr fold arm); only set when the sema probe runs,
        // so the global phase_ComptimeEvaluation fold is unaffected.
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                var ldt = comptimeEvalResolveTypeArg(self, l_decl.child_0);
                if (ldt) |lt| {
                    if (type_mod.typeRegistryIsInteger(self.registry, lt)) {
                        if (type_mod.typeRegistryIntIsSigned(self.registry, lt)) return SignClass.negative;
                        return SignClass.non_negative;
                    }
                }
                if (l_decl.child_1 != @intCast(u32, 0)) {
                    return comptimeEvalSignClass(self, l_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    var dt = comptimeEvalResolveTypeArg(self, c_decl.child_0);
                    if (dt) |t| {
                        if (type_mod.typeRegistryIsInteger(self.registry, t)) {
                            if (type_mod.typeRegistryIntIsSigned(self.registry, t)) return SignClass.negative;
                            return SignClass.non_negative;
                        }
                    }
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        return comptimeEvalSignClass(self, c_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
        return SignClass.unknown;
    }
    if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
            var dt2 = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
            if (dt2) |t2| {
                if (type_mod.typeRegistryIsInteger(self.registry, t2)) {
                    if (type_mod.typeRegistryIntIsSigned(self.registry, t2)) return SignClass.negative;
                    return SignClass.non_negative;
                }
            }
        }
        return SignClass.unknown;
    }
    return SignClass.unknown;
}


fn comptimeEvalBuiltin(self: *ComptimeEval, node_idx: u32, depth: u32) ?ComptimeVal {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.child_0 == self.size_of_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ComptimeVal{ .bits = @intCast(u64, ty.size), .width_bits = @intCast(u32, 0), .sig = false };
        }
        return null;
    }
    if (node.child_0 == self.align_of_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        if (tid) |t| {
            var ty = self.registry.types_items[@intCast(usize, t)];
            if (ty.state == @intCast(u8, 2)) return ComptimeVal{ .bits = @intCast(u64, ty.alignment), .width_bits = @intCast(u32, 0), .sig = false };
        }
        return null;
    }
    if (node.child_0 == self.offset_of_id or node.child_0 == self.bit_offset_of_id) {
        var ec2_n = ast_mod.astStoreNodeExtraChildCount(self.store, node_idx);
        if (ec2_n >= @intCast(u32, 2)) {
            var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
            if (tid) |t| {
                var ty = self.registry.types_items[@intCast(usize, t)];
                if (ty.state == @intCast(u8, 2) and ty.kind == type_mod.TypeKind.struct_type) {
                    var fields: []type_mod.FieldEntry = undefined;
                    type_mod.typeRegistryGetStructFields(self.registry, t, &fields);
                    var packed_fields: []type_mod.PackedBitField = undefined;
                    var has_pk = type_mod.typeRegistryGetPackedBitFields(self.registry, t, &packed_fields);
                    var fname_node = ast_mod.astStoreNodeAt(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                    if (fname_node.kind == AstKind.string_literal) {
                        var sv_idx = ast_mod.astStoreNodePayload(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                        var want_id = self.store.string_values.items[@intCast(usize, sv_idx)];
                        var fi: usize = 0;
                        while (fi < fields.len) : (fi += 1) {
                            if (fields[fi].name_id == want_id) {
                                var bo: u64 = @intCast(u64, fields[fi].offset);
                                if (has_pk) {
                                    var pk_bo: u64 = @intCast(u64, 0);
                                    if (fi < packed_fields.len) {
                                        pk_bo = @intCast(u64, packed_fields[fi].bit_offset);
                                    }
                                    if (node.child_0 == self.bit_offset_of_id) {
                                        bo = pk_bo;
                                    } else {
                                        bo = pk_bo / @intCast(u64, 8);
                                    }
                                } else {
                                    if (node.child_0 == self.bit_offset_of_id) {
                                        bo = bo * @intCast(u64, 8);
                                    }
                                }
                                return ComptimeVal{ .bits = bo, .width_bits = @intCast(u32, 0), .sig = false };
                            }
                        }
                    }
                } else if (ty.state == @intCast(u8, 2) and ty.kind == type_mod.TypeKind.packed_union_type) {
                    var u_fields: []type_mod.FieldEntry = undefined;
                    type_mod.typeRegistryGetUnionFields(self.registry, t, &u_fields);
                    var fname_node2 = ast_mod.astStoreNodeAt(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                    if (fname_node2.kind == AstKind.string_literal) {
                        var sv_idx2 = ast_mod.astStoreNodePayload(self.store, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)));
                        var want_id2 = self.store.string_values.items[@intCast(usize, sv_idx2)];
                        var fi2: usize = 0;
                        while (fi2 < u_fields.len) : (fi2 += 1) {
                            if (u_fields[fi2].name_id == want_id2) {
                                var ubo: u64 = @intCast(u64, 0);
                                if (node.child_0 == self.offset_of_id) {
                                    ubo = @intCast(u64, 0);
                                }
                                return ComptimeVal{ .bits = ubo, .width_bits = @intCast(u32, 0), .sig = false };
                            }
                        }
                    }
                }
            }
        }
        return null;
    }
    if (node.child_0 == self.bit_size_of_id) {
        var ec3_n = ast_mod.astStoreNodeExtraChildCount(self.store, node_idx);
        if (ec3_n >= @intCast(u32, 1)) {
            var tid2 = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
            if (tid2) |t2| {
                var ty2 = self.registry.types_items[@intCast(usize, t2)];
                if (ty2.state == @intCast(u8, 2)) {
                    var bsz: u64 = @intCast(u64, ty2.size) * @intCast(u64, 8);
                    if (ty2.kind == type_mod.TypeKind.struct_type and (ty2.flags & @intCast(u8, 0x10)) != @intCast(u8, 0)) {
                        bsz = @intCast(u64, type_mod.typeRegistryGetPackedTotalBits(self.registry, t2));
                    }
                    if (ty2.kind == type_mod.TypeKind.packed_union_type) {
                        bsz = @intCast(u64, type_mod.typeRegistryGetPackedUnionTotalBits(self.registry, t2));
                    }
                    if (type_mod.typeRegistryIsInteger(self.registry, t2)) {
                        bsz = @intCast(u64, type_mod.typeRegistryIntWidthBits(self.registry, t2));
                    }
                    if (ty2.kind == type_mod.TypeKind.enum_type) {
                        var ebt = type_mod.typeRegistryEnumBackingType(self.registry, t2);
                        bsz = @intCast(u64, type_mod.typeRegistryIntWidthBits(self.registry, ebt));
                    }
                    if (ty2.kind == type_mod.TypeKind.bool_type) {
                        bsz = @intCast(u64, 1);
                    }
                    return ComptimeVal{ .bits = bsz, .width_bits = @intCast(u32, 0), .sig = false };
                }
            }
        }
        return null;
    }
    if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        var inner = comptimeEvalEvaluateDepth(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)), depth);
        if (tid) |t| {
            if (inner) |cv| {
                if (cv.width_bits == WIDTH_FLOAT) return null;
                var ty = self.registry.types_items[@intCast(usize, t)];
                var is_int_t: bool = type_mod.typeRegistryIsInteger(self.registry, t);
                var wb: u32 = @intCast(u32, type_mod.typeRegistryIntWidthBits(self.registry, t));
                var sig: bool = type_mod.typeRegistryIntIsSigned(self.registry, t);
                // @as with a NON-integer target must NOT fold here: the arm
                // yields an integer ComptimeVal, which enters the integer
                // binop evaluator and silently miscompiles float arithmetic
                // (e.g. `@as(f64,3)/2` -> integer 3/2). Fold @as only when the
                // target is an integer. (@intCast's non-integer behavior is
                // deliberately left unchanged, out of scope.)
                if (node.child_0 == self.as_id and !is_int_t) return null;
                if (!is_int_t) {
                    wb = @intCast(u32, ty.size * @intCast(u32, 8));
                    sig = false;
                }
                // Task 11S (c): an out-of-range comptime `@intCast` is invalid
                // Zig (`@intCast(u8, 300)` must not mask to 44). Emit
                // error[3000] and stop folding; the pass's post-phase diag
                // check exits rc=2 before any emission. Task B3 item 3: the
                // arm is shared with `@as`, so the message names the builtin
                // actually used. Task B3 item 4: the comptime sweep is a single
                // global node walk with no module context and the AST store
                // carries no node->source_file map, so `source_file_id` stays 0
                // and the diagnostic prints the message without a file:line
                // (the span is still recorded). Threading a real location needs
                // a structural change (per-module node ranges or a node->module
                // table), out of scope here.
                if (is_int_t and !comptimeValFitsType(self, cv, t, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)))) {
                    if (self.diag) |dg| {
                        if (diag_mod.diagnosticCollectorMarkNodeOnce(dg, node_idx)) {
                            var ic_msg: []const u8 = "@intCast value does not fit the target type";
                            if (node.child_0 == self.as_id) { ic_msg = "@as value does not fit the target type"; }
                            _ = diag_mod.diagnosticCollectorAdd(dg, @intCast(u8, 0),
                                @intCast(u16, 3000),
                                @intCast(u32, 0), node.span_start,
                                node.span_start + @intCast(u32, node.span_len), ic_msg);
                        }
                    }
                    return null;
                }
                if (wb >= @intCast(u32, 64)) {
                    return ComptimeVal{ .bits = cv.bits, .width_bits = wb, .sig = sig };
                }
                var mask: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
                var masked = cv.bits & mask;
                if (sig and (cv.bits & (@intCast(u64, 1) << @intCast(u64, wb - @intCast(u32, 1)))) != @intCast(u64, 0)) {
                    var not_mask: u64 = (@intCast(u64, 0) - mask) - @intCast(u64, 1);
                    masked = cv.bits | not_mask;
                }
                return ComptimeVal{ .bits = masked, .width_bits = wb, .sig = sig };
            }
        }
        return null;
    }
    if (node.child_0 == self.is_windows_id) {
        var wb2: u64 = @intCast(u64, 0);
        if (self.host_is_windows) {
            wb2 = @intCast(u64, 1);
        }
        return ComptimeVal{ .bits = wb2, .width_bits = @intCast(u32, 1), .sig = false };
    }
    if (node.child_0 == self.int_to_float_id or node.child_0 == self.float_cast_id) {
        var fv = comptimeEvalFloatBuiltin(self, node_idx, depth);
        if (fv) |v| {
            // Z98 @bitCast is integer-only, so transport the f64 bit pattern
            // through a pointer reinterpretation (no value conversion).
            var fb: f64 = v;
            var fbp: *u64 = @ptrCast(*u64, &fb);
            return ComptimeVal{ .bits = fbp.*, .width_bits = WIDTH_FLOAT, .sig = false };
        }
        return null;
    }
    return null;
}

// Float-valued sub-evaluator. Deliberately SEPARATE from
// comptimeEvalEvaluateDepth so a float bit pattern can never enter the integer
// binop/negate/bit_not/int_cast paths (see WIDTH_FLOAT). Handles float
// literals, `negate` (a negative float literal is `negate(float_literal)`),
// parentheses, nested @intToFloat/@floatCast, and const ident chains.
fn comptimeEvalFloat(self: *ComptimeEval, node_idx: u32, depth: u32) ?f64 {
    if (node_idx == @intCast(u32, 0)) return null;
    if (depth >= @intCast(u32, 16)) return null;
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.float_literal) {
        return self.store.float_values.items[@intCast(usize, ast_mod.astStoreNodePayload(self.store, node_idx))];
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalFloat(self, node.child_0, depth + @intCast(u32, 1));
        // Unary minus (not `0.0 - fv`) so `-0.0` keeps its sign bit.
        if (inner) |fv| { return -fv; }
        return null;
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalFloat(self, node.child_0, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_to_float_id or node.child_0 == self.float_cast_id) {
            return comptimeEvalFloatBuiltin(self, node_idx, depth + @intCast(u32, 1));
        }
        return null;
    } else if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        var inner = comptimeEvalFloat(self, c_decl.child_1, depth + @intCast(u32, 1));
                        if (inner) |fv| {
                            // Round through the const's DECLARED type: a typed
                            // `const S: f32 = 0.1` is f32(0.1), not the raw f64
                            // literal. Skipping this silently changes semantics
                            // when the const is later widened to f64.
                            var dt = comptimeEvalResolveTypeArg(self, c_decl.child_0);
                            if (dt) |t| {
                                if (t == type_mod.TYPE_F32) {
                                    var f32v: f32 = @floatCast(f32, fv);
                                    return @floatCast(f64, f32v);
                                }
                            }
                            return fv;
                        }
                        return null;
                    }
                }
            }
        }
        return null;
    } else {
        return null;
    }
}

// Determine whether an @intToFloat operand is a SIGNED integer from its
// declared type / literal shape, rather than ComptimeVal.sig (which is true for
// every int literal and would misread an unsigned value above i64 max as
// negative, e.g. a `u64` const = 18446744073709551615 folding to -1.0).
fn comptimeEvalOperandSigned(self: *ComptimeEval, node_idx: u32, cv: ComptimeVal) bool {
    // Unwrap parenthesization (recursively) so `@intToFloat(f64, (U))` is
    // classified by U's declared type, not the wrapper's shape. The value in
    // `cv` already came from the raw node (comptimeEvalEvaluateDepth unwraps
    // parens), so only the signedness classification needs the unwrap.
    var idx = node_idx;
    var guard: u32 = 0;
    while (guard < @intCast(u32, 32)) : (guard += 1) {
        var wn = ast_mod.astStoreNodeAt(self.store, idx);
        if (wn.kind == AstKind.paren_expr) { idx = wn.child_0; } else { break; }
    }
    var node = ast_mod.astStoreNodeAt(self.store, idx);
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, idx);
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    var dt = comptimeEvalResolveTypeArg(self, c_decl.child_0);
                    if (dt) |t| {
                        if (type_mod.typeRegistryIsInteger(self.registry, t)) {
                            return type_mod.typeRegistryIntIsSigned(self.registry, t);
                        }
                    }
                }
            }
        }
    } else if (node.kind == AstKind.int_literal) {
        return cv.bits <= @intCast(u64, 9223372036854775807);
    } else if (node.kind == AstKind.char_literal) {
        return false;
    } else if (node.kind == AstKind.builtin_call) {
        if (node.child_0 == self.int_cast_id or node.child_0 == self.as_id) {
            var dt2 = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, idx, @intCast(u32, 0)));
            if (dt2) |t2| {
                if (type_mod.typeRegistryIsInteger(self.registry, t2)) {
                    return type_mod.typeRegistryIntIsSigned(self.registry, t2);
                }
            }
        }
    }
    return cv.sig;
}

// Evaluate one @intToFloat/@floatCast call to an f64. The target must resolve
// to TYPE_F32/TYPE_F64; an f32 target rounds through f32. @intToFloat's operand
// is evaluated with the integer evaluator (honoring its declared signedness);
// @floatCast's with comptimeEvalFloat. A non-float target or non-foldable
// operand returns null (no fold; the runtime lowering is unchanged).
fn comptimeEvalFloatBuiltin(self: *ComptimeEval, node_idx: u32, depth: u32) ?f64 {
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
    if (tid) |t| {
        if (t != type_mod.TYPE_F32 and t != type_mod.TYPE_F64) return null;
        var inner_idx = ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1));
        var fv: f64 = 0.0;
        if (node.child_0 == self.int_to_float_id) {
            var iv = comptimeEvalEvaluateDepth(self, inner_idx, depth);
            if (iv) |cv| {
                if (cv.width_bits == WIDTH_FLOAT) return null;
                if (comptimeEvalOperandSigned(self, inner_idx, cv)) {
                    var sv: i64 = @bitCast(i64, cv.bits);
                    fv = @intToFloat(f64, sv);
                } else {
                    fv = @intToFloat(f64, cv.bits);
                }
            } else {
                return null;
            }
        } else if (node.child_0 == self.float_cast_id) {
            var xv = comptimeEvalFloat(self, inner_idx, depth);
            if (xv) |x| { fv = x; } else { return null; }
        } else {
            return null;
        }
        if (t == type_mod.TYPE_F32) {
            var f32v: f32 = @floatCast(f32, fv);
            return @floatCast(f64, f32v);
        }
        return fv;
    }
    return null;
}

pub fn comptimeEvalEvaluate(self: *ComptimeEval, node_idx: u32) ?ComptimeVal {
    return comptimeEvalEvaluateDepth(self, node_idx, @intCast(u32, 0));
}

fn comptimeEvalEvaluateDepth(self: *ComptimeEval, node_idx: u32, depth: u32) ?ComptimeVal {
    if (node_idx == @intCast(u32, 0)) return null;
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.int_literal) {
        return ComptimeVal{ .bits = ast_mod.astStoreIntValue(self.store, node_idx), .width_bits = @intCast(u32, 0), .sig = true };
    } else if (node.kind == AstKind.char_literal) {
        return ComptimeVal{ .bits = ast_mod.astStoreIntValue(self.store, node_idx), .width_bits = @intCast(u32, 8), .sig = false };
    } else if (node.kind == AstKind.bool_literal) {
        if ((node.flags & @intCast(u8, 1)) != @intCast(u8, 0)) return ComptimeVal{ .bits = @intCast(u64, 1), .width_bits = @intCast(u32, 1), .sig = false };
        return ComptimeVal{ .bits = @intCast(u64, 0), .width_bits = @intCast(u32, 1), .sig = false };
    } else if (node.kind == AstKind.negate) {
        var inner = comptimeEvalEvaluateDepth(self, node.child_0, depth);
        if (inner) |cv| {
            if (cv.width_bits == WIDTH_FLOAT) return null;
            var nv: u64 = @intCast(u64, 0) - cv.bits;
            if (cv.width_bits != @intCast(u32, 0)) {
                var wb: u32 = cv.width_bits;
                if (wb >= @intCast(u32, 64)) {
                    return ComptimeVal{ .bits = nv, .width_bits = wb, .sig = cv.sig };
                }
                var mask: u64 = (@intCast(u64, 1) << @intCast(u64, wb)) - @intCast(u64, 1);
                var masked = nv & mask;
                if (cv.sig and (nv & (@intCast(u64, 1) << @intCast(u64, wb - @intCast(u32, 1)))) != @intCast(u64, 0)) {
                    var not_mask: u64 = (@intCast(u64, 0) - mask) - @intCast(u64, 1);
                    masked = nv | not_mask;
                }
                return ComptimeVal{ .bits = masked, .width_bits = wb, .sig = cv.sig };
            }
            return ComptimeVal{ .bits = nv, .width_bits = @intCast(u32, 0), .sig = true };
        }
        return null;
    } else if (node.kind == AstKind.bit_not) {
        var bnv = comptimeEvalEvaluateDepth(self, node.child_0, depth);
        if (bnv) |bv| {
            if (bv.width_bits == WIDTH_FLOAT) return null;
            var bnb = ~bv.bits;
            return ComptimeVal{ .bits = bnb, .width_bits = bv.width_bits, .sig = false };
        }
        return null;
    } else if (node.kind == AstKind.bool_not) {
        return comptimeEvalLogical(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
               node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
               node.kind == AstKind.shl or node.kind == AstKind.shr) {
        return comptimeEvalBinOp(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.cmp_eq or node.kind == AstKind.cmp_ne or
               node.kind == AstKind.cmp_lt or node.kind == AstKind.cmp_le or
               node.kind == AstKind.cmp_gt or node.kind == AstKind.cmp_ge) {
        return comptimeEvalCompare(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.bool_and or node.kind == AstKind.bool_or) {
        return comptimeEvalLogical(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.builtin_call) {
        return comptimeEvalBuiltin(self, node_idx, depth);
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalEvaluateDepth(self, node.child_0, depth);
    } else if (node.kind == AstKind.ident_expr) {
        if (depth >= @intCast(u32, 16)) return null;
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
        // Task 9D (Gap B): consult the enclosing function's local-const scope
        // before the module symbol registry. A local `const` is a statement, not
        // a module symbol, so only this scope can see it; it shadows a module
        // const of the same name (mirrors evalConstU32Full variant (e)).
        if (self.local_consts) |lcs| {
            if (type_resolver.localConstScopeLookup(lcs, name_id)) |l_decl_node| {
                var l_decl = ast_mod.astStoreNodeAt(self.store, l_decl_node);
                if (l_decl.child_1 != @intCast(u32, 0)) {
                    return comptimeEvalEvaluateDepth(self, l_decl.child_1, depth + @intCast(u32, 1));
                }
            }
        }
        var mi: usize = 0;
        while (mi < @intCast(usize, self.symbol_reg.tables_len)) : (mi += 1) {
            var c_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbol_reg, @intCast(u32, mi), name_id);
            if (c_sym) |cs| {
                if ((cs.flags & @intCast(u16, 0x01)) == @intCast(u16, 0)) {
                    var c_decl = ast_mod.astStoreNodeAt(self.store, cs.decl_node);
                    if (c_decl.child_1 != @intCast(u32, 0)) {
                        return comptimeEvalEvaluateDepth(self, c_decl.child_1, depth + @intCast(u32, 1));
                    }
                }
            }
        }
        return null;
    } else {
        return null;
    }
}
