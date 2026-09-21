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
    float_cast_id: u32,
    int_to_float_id: u32,
    is_windows_id: u32,
    host_is_windows: bool,
};

pub fn comptimeEvalInit(registry: *TypeRegistry, store: *AstStore, interner: *StringInterner, symbol_reg: *SymbolRegistry) ComptimeEval {
    var s_size: []const u8 = "@sizeOf";
    var s_align: []const u8 = "@alignOf";
    var s_intc: []const u8 = "@intCast";
    var intc_id = interner_mod.stringInternerIntern(interner, s_intc);
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
        .size_of_id = size_id, .align_of_id = align_id, .int_cast_id = intc_id,
        .float_cast_id = fc_id, .int_to_float_id = itf_id,
        .offset_of_id = off_id, .bit_size_of_id = bitsz_id, .bit_offset_of_id = bitoff_id,
        .is_windows_id = iw_id,
        .host_is_windows = false,
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

fn comptimeEvalResolveTypeArg(self: *ComptimeEval, node_idx: u32) ?u32 {
    if (node_idx == @intCast(u32, 0)) return null;
    var env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbol_reg, .interner = self.interner, .module_id = type_resolver.MODULE_ID_NONE, .source_file_id = @intCast(u32, 0), .diag = null, .local_consts = null };
    var tid = type_resolver.resolveTypeExprFull(&env, node_idx, @intCast(u32, 0));
    if (tid == type_mod.TYPE_UNDEFINED) return null;
    return tid;
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
    if (node.child_0 == self.int_cast_id) {
        var tid = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
        var inner = comptimeEvalEvaluateDepth(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 1)), depth);
        if (tid) |t| {
            if (inner) |cv| {
                if (cv.width_bits == WIDTH_FLOAT) return null;
                var ty = self.registry.types_items[@intCast(usize, t)];
                var is_int_t: bool = type_mod.typeRegistryIsInteger(self.registry, t);
                var wb: u32 = @intCast(u32, type_mod.typeRegistryIntWidthBits(self.registry, t));
                var sig: bool = type_mod.typeRegistryIntIsSigned(self.registry, t);
                if (!is_int_t) {
                    wb = @intCast(u32, ty.size * @intCast(u32, 8));
                    sig = false;
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
    var node = ast_mod.astStoreNodeAt(self.store, node_idx);
    if (node.kind == AstKind.ident_expr) {
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
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
        if (node.child_0 == self.int_cast_id) {
            var dt2 = comptimeEvalResolveTypeArg(self, ast_mod.astStoreNodeExtraChildAt(self.store, node_idx, @intCast(u32, 0)));
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
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op or node.kind == AstKind.bit_and or
               node.kind == AstKind.bit_or or node.kind == AstKind.bit_xor or
               node.kind == AstKind.shl or node.kind == AstKind.shr) {
        return comptimeEvalBinOp(self, node_idx, node.kind, depth);
    } else if (node.kind == AstKind.builtin_call) {
        return comptimeEvalBuiltin(self, node_idx, depth);
    } else if (node.kind == AstKind.paren_expr) {
        return comptimeEvalEvaluateDepth(self, node.child_0, depth);
    } else if (node.kind == AstKind.ident_expr) {
        if (depth >= @intCast(u32, 16)) return null;
        var name_id = ast_mod.astStoreIdentifier(self.store, node_idx);
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
