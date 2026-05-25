const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const TypeId = @import("type_registry.zig").TypeId;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const ResolvedTypeTable = @import("resolved_type_table.zig").ResolvedTypeTable;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;
const AstStore = @import("ast.zig").AstStore;
const AstKind = @import("ast.zig").AstKind;
const rtt_mod = @import("resolved_type_table.zig");
const type_mod = @import("type_registry.zig");
const diag_mod = @import("diagnostics.zig");
const sym_mod = @import("symbol_table.zig");
const ast_mod = @import("ast.zig");
const coercion_mod = @import("coercion.zig");
const hash_mod = @import("util/hash.zig");
const pal_mod = @import("pal.zig");

pub const SemanticAnalyzer = struct {
    type_table: *ResolvedTypeTable,
    diag: *DiagnosticCollector,
    registry: *TypeRegistry,
    symbols: *SymbolRegistry,
    store: *AstStore,
    module_id: u32,
    expected_type_stack_items: [*]TypeId,
    expected_type_stack_len: usize,
    expected_type_stack_cap: usize,
    expected_type_stack_alloc: *Sand,
    current_fn_return: TypeId,
    current_fn_name: u32,
    coercion_table: *coercion_mod.CoercionTable,
    enum_value_table: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
};

pub fn semanticAnalyzerInit(alloc: *Sand, type_table: *ResolvedTypeTable, diag: *DiagnosticCollector, registry: *TypeRegistry, symbols: *SymbolRegistry, store: *AstStore, module_id: u32, coercion_tab: *coercion_mod.CoercionTable, enum_val_tab: *hash_mod.U32ToU32Map) SemanticAnalyzer {
    return SemanticAnalyzer{
        .type_table = type_table,
        .diag = diag,
        .registry = registry,
        .symbols = symbols,
        .store = store,
        .module_id = module_id,
        .expected_type_stack_items = undefined,
        .expected_type_stack_len = @intCast(usize, 0),
        .expected_type_stack_cap = @intCast(usize, 0),
        .expected_type_stack_alloc = alloc,
        .current_fn_return = @intCast(u32, 0),
        .current_fn_name = @intCast(u32, 0),
        .coercion_table = coercion_tab,
        .enum_value_table = enum_val_tab,
        .current_switch_cond_tu = @intCast(u32, 0),
        .local_decl_names = undefined,
        .local_decl_types = undefined,
        .local_decl_count = @intCast(usize, 0),
        .local_decl_cap = @intCast(usize, 0),
    };
}

fn semanticAnalyzerGrowLocalDecls(self: *SemanticAnalyzer) void {
    var new_cap: usize = if (self.local_decl_cap < @intCast(usize, 8)) @intCast(usize, 8) else self.local_decl_cap * @intCast(usize, 2);
    var raw_names = alloc_mod.sandAlloc(self.expected_type_stack_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var raw_types = alloc_mod.sandAlloc(self.expected_type_stack_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
    var ndst = @ptrCast([*]u32, raw_names);
    var tdst = @ptrCast([*]u32, raw_types);
    if (self.local_decl_count > @intCast(usize, 0)) {
        var ci: usize = 0;
        while (ci < self.local_decl_count) : (ci += 1) {
            ndst[ci] = self.local_decl_names[ci];
            tdst[ci] = self.local_decl_types[ci];
        }
    }
    self.local_decl_names = ndst;
    self.local_decl_types = tdst;
    self.local_decl_cap = new_cap;
}

pub fn semanticAnalyzerResolveIdent(self: *SemanticAnalyzer, module_id: u32, name_id: u32) u32 {
    var li = self.local_decl_count;
    while (li > @intCast(usize, 0)) {
        li -= @intCast(usize, 1);
        if (self.local_decl_names[li] == name_id) {
            var ri: []const u8 = "R"; pal_mod.stderr_write(ri);
            return self.local_decl_types[li];
        }
    }
    var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, name_id);
    if (sym) |s| {
        if (s.kind == sym_mod.SymbolKind.type_alias) return s.type_id;
        if (s.type_id != @intCast(u32, 0)) return s.type_id;
        return type_mod.TYPE_VOID;
    }
    var key = @intCast(u64, name_id);
    var tid = type_mod.nameCacheGet(self.registry, key);
    if (tid) |t| return t;
    return type_mod.TYPE_VOID;
}

pub fn semanticAnalyzerResolveFieldAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var base_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var field_name_id = node.payload;

    if (base_node.kind == AstKind.ident_expr) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, self.store.identifiers.items[@intCast(usize, base_node.payload)]);
        if (sym) |s| {
            if (s.kind == sym_mod.SymbolKind.type_alias) {
                var alias_type_id = s.type_id;
                if (alias_type_id != @intCast(u32, 0)) {
                    var aty = self.registry.types_items[@intCast(usize, alias_type_id)];
                    if (aty.kind == type_mod.TypeKind.tagged_union_type) {
                        var tp = self.registry.tu_items[@intCast(usize, aty.payload_idx)];
                        var fstart: usize = @intCast(usize, tp.fields_start);
                        var fcount: usize = @intCast(usize, tp.fields_count);
                        var fi: usize = 0;
                        while (fi < fcount) : (fi += 1) {
                            if (self.registry.fe_items[fstart + fi].name_id == field_name_id) {
                                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_U32);
                                return type_mod.TYPE_U32;
                            }
                        }
                    }
                }
            }
            if (s.kind == sym_mod.SymbolKind.module) {
                var target_mod = s.module_id;
                var field_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, target_mod, field_name_id);
                if (field_sym) |fs| {
                    if ((fs.flags & @intCast(u16, 2)) != @intCast(u16, 0)) {
                        if (fs.kind == sym_mod.SymbolKind.type_alias) {
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fs.type_id);
                            return fs.type_id;
                        }
                        if (fs.type_id != @intCast(u32, 0)) {
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fs.type_id);
                            return fs.type_id;
                        }
                    }
                }
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
                return type_mod.TYPE_VOID;
            }
        }
    }

    var base_type_id = semanticAnalyzerResolveExpr(self, node.child_0);
    if (base_type_id == type_mod.TYPE_VOID) {
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }
    var base_ty = self.registry.types_items[@intCast(usize, base_type_id)];

    var fields_start: usize = 0;
    var fields_count: usize = 0;
    if (base_ty.kind == type_mod.TypeKind.struct_type) {
        var sp = self.registry.st_items[@intCast(usize, base_ty.payload_idx)];
        fields_start = @intCast(usize, sp.fields_start);
        fields_count = @intCast(usize, sp.fields_count);
    } else if (base_ty.kind == type_mod.TypeKind.union_type) {
        var up = self.registry.un_items[@intCast(usize, base_ty.payload_idx)];
        fields_start = @intCast(usize, up.fields_start);
        fields_count = @intCast(usize, up.fields_count);
    } else if (base_ty.kind == type_mod.TypeKind.tagged_union_type) {
        var tp = self.registry.tu_items[@intCast(usize, base_ty.payload_idx)];
        fields_start = @intCast(usize, tp.fields_start);
        fields_count = @intCast(usize, tp.fields_count);
    } else {
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }

    var fi: usize = 0;
    while (fi < fields_count) {
        var fe = self.registry.fe_items[fields_start + fi];
        if (fe.name_id == field_name_id) {
            var result = fe.type_id;
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
            return result;
        }
        fi += 1;
    }

    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveArithmetic(self: *SemanticAnalyzer, node_idx: u32, op_kind: AstKind) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) return type_mod.TYPE_VOID;

    if (op_kind == AstKind.add or op_kind == AstKind.sub) {
        var lhs_ptr = type_mod.typeRegistryIsPointer(self.registry, lhs) or type_mod.typeRegistryIsSlice(self.registry, lhs);
        var rhs_uint = type_mod.typeRegistryIsUnsigned(self.registry, rhs);
        var rhs_ptr = type_mod.typeRegistryIsPointer(self.registry, rhs) or type_mod.typeRegistryIsSlice(self.registry, rhs);
        if (lhs_ptr and rhs_uint) return lhs;
        if (op_kind == AstKind.add and type_mod.typeRegistryIsUnsigned(self.registry, lhs) and rhs_ptr) return rhs;
        if (op_kind == AstKind.sub and lhs_ptr and rhs_ptr) return type_mod.TYPE_ISIZE;
    }

    if (lhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, rhs)) return rhs;
    if (rhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, lhs)) return lhs;

    if (lhs != rhs or !type_mod.typeRegistryIsNumeric(self.registry, lhs)) return type_mod.TYPE_VOID;
    return lhs;
}

fn semanticAnalyzerResolveBitwise(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    if (lhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsInteger(self.registry, rhs)) return rhs;
    if (rhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsInteger(self.registry, lhs)) return lhs;
    if (lhs != rhs or !type_mod.typeRegistryIsInteger(self.registry, lhs)) return type_mod.TYPE_VOID;
    return lhs;
}

fn semanticAnalyzerResolveComparison(self: *SemanticAnalyzer, node_idx: u32, op_kind: AstKind) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    if (lhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, rhs)) return type_mod.TYPE_BOOL;
    if (rhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, lhs)) return type_mod.TYPE_BOOL;
    var lhs_num = type_mod.typeRegistryIsNumeric(self.registry, lhs);
    if (lhs_num and lhs == rhs) return type_mod.TYPE_BOOL;
    if (op_kind == AstKind.cmp_eq or op_kind == AstKind.cmp_ne) {
        if (type_mod.typeRegistryIsOptional(self.registry, lhs) and rhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsOptional(self.registry, rhs) and lhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsErrorSet(self.registry, lhs) and type_mod.typeRegistryIsErrorSet(self.registry, rhs)) return type_mod.TYPE_BOOL;
    }
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveLogical(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == type_mod.TYPE_BOOL and rhs == type_mod.TYPE_BOOL) return type_mod.TYPE_BOOL;
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveNegate(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var inner = semanticAnalyzerResolveExpr(self, node.child_0);
    if (inner == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    if (inner == type_mod.TYPE_INT_LIT) return type_mod.TYPE_INT_LIT;
    if (type_mod.typeRegistryIsNumeric(self.registry, inner)) return inner;
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveBitNot(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var inner = semanticAnalyzerResolveExpr(self, node.child_0);
    if (inner == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    if (inner == type_mod.TYPE_INT_LIT) return type_mod.TYPE_INT_LIT;
    if (type_mod.typeRegistryIsInteger(self.registry, inner)) return inner;
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveFnCall(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var callee_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var direct_ret: u32 = @intCast(u32, 0);
    if (callee_node.kind == AstKind.ident_expr) {
        var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, self.store.identifiers.items[@intCast(usize, callee_node.payload)]);
        if (sym) |s| { var xf: []const u8 = "XF"; pal_mod.stderr_write(xf);
            if (s.kind == sym_mod.SymbolKind.function and s.decl_node != @intCast(u32, 0)) {
                var dn = self.store.nodes.items[@intCast(usize, s.decl_node)];
                if (dn.kind == AstKind.fn_decl) {
                    var proto = self.store.fn_protos.items[@intCast(usize, dn.payload)];
                    if (proto.return_type_node != @intCast(u32, 0)) {
                        var rt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                        if (rt) |t| { direct_ret = t; }
                        else {
                            var rn = self.store.nodes.items[@intCast(usize, proto.return_type_node)];
                            if (rn.kind == AstKind.ident_expr) {
                                var rnid = self.store.identifiers.items[@intCast(usize, rn.payload)];
                                var nc = type_mod.nameCacheGet(self.registry, @intCast(u64, rnid));
                                if (nc == null) {
                                    var mti: usize = 0;
                                    while (mti < self.symbols.tables_len) : (mti += 1) {
                                        var nck: u64 = @intCast(u64, mti) * @intCast(u64, 4294967296) + @intCast(u64, rnid);
                                        nc = type_mod.nameCacheGet(self.registry, nck);
                                        if (nc != null) break;
                                    }
                                }
                                if (nc) |t| { direct_ret = t; }
                            }
                        }
                    }
                }
            }
        } else { var xs: []const u8 = "xS"; pal_mod.stderr_write(xs); }
    }
    if (direct_ret != @intCast(u32, 0)) {
        var xd: []const u8 = "xD"; pal_mod.stderr_write(xd);
        var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var ai: usize = 0;
        while (ai < args.len) : (ai += 1) {
            _ = semanticAnalyzerResolveExpr(self, args[ai]);
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, direct_ret);
        return direct_ret;
    }
    var callee_type = semanticAnalyzerResolveExpr(self, node.child_0);
    if (callee_type == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    var callee_ty = self.registry.types_items[@intCast(usize, callee_type)];
    if (callee_ty.kind != type_mod.TypeKind.fn_type) {
        return type_mod.TYPE_VOID;
    }
    var fnp = self.registry.fn_items[@intCast(usize, callee_ty.payload_idx)];
    var pcount: usize = @intCast(usize, fnp.params_count);
    var pstart: usize = @intCast(usize, fnp.params_start);
    var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (args.len != pcount) {
        return fnp.return_type;
    }
    var ai: usize = 0;
    while (ai < args.len) : (ai += 1) {
        var param_type = self.registry.xt_items[pstart + ai];
        var arg_type = semanticAnalyzerResolveExpr(self, args[ai]);
        if (arg_type != param_type) {
            if (type_mod.typeRegistryIsAssignable(self.registry, arg_type, param_type)) {
                var ck = coercion_mod.classifyCoercion(self.registry, arg_type, param_type);
                if (ck != coercion_mod.CoercionKind.none) {
                    coercion_mod.coercionTableAdd(self.coercion_table, args[ai], ck, param_type);
                }
            }
        }
    }
    return fnp.return_type;
}

fn semanticAnalyzerResolveTryExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var inner = semanticAnalyzerResolveExpr(self, node.child_0);
    if (inner == @intCast(u32, 0) or inner == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var ty = self.registry.types_items[@intCast(usize, inner)];
    if (ty.kind != type_mod.TypeKind.error_union_type) {
        return type_mod.TYPE_VOID;
    }
    var eu = self.registry.eu_items[@intCast(usize, ty.payload_idx)];
    return eu.payload;
}

fn semanticAnalyzerResolveIfExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var then_type = semanticAnalyzerResolveExpr(self, node.child_1);
    if (node.child_2 == @intCast(u32, 0)) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    var else_type = semanticAnalyzerResolveExpr(self, node.child_2);
    if (then_type == else_type) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_NORETURN) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_NORETURN) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, else_type)) { coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, coercion_mod.CoercionKind.int_literal_coerce, else_type); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, then_type)) { coercion_mod.coercionTableAdd(self.coercion_table, node.child_2, coercion_mod.CoercionKind.int_literal_coerce, then_type); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_VOID) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_VOID) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveEnumLiteral(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var name_id = node.payload;
    if (self.current_switch_cond_tu != @intCast(u32, 0)) {
        var tu_ty = self.registry.types_items[@intCast(usize, self.current_switch_cond_tu)];
        if (tu_ty.kind == type_mod.TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
            var fstart: usize = @intCast(usize, tp.fields_start);
            var fcount: usize = @intCast(usize, tp.fields_count);
            var fi: usize = 0;
            while (fi < fcount) : (fi += 1) {
                if (self.registry.fe_items[fstart + fi].name_id == name_id) {
                    hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, @intCast(u32, fi));
                    var re: []const u8 = "E"; pal_mod.stderr_write(re);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_U32);
                    return type_mod.TYPE_U32;
                }
            }
        }
    }
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveStructInit(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var target_type: u32 = @intCast(u32, 0);
    if (node.child_0 != @intCast(u32, 0)) {
        target_type = semanticAnalyzerResolveExpr(self, node.child_0);
    }
    if (target_type == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    var tgt = self.registry.types_items[@intCast(usize, target_type)];
    if (tgt.kind == type_mod.TypeKind.tagged_union_type) {
        var tp = self.registry.tu_items[@intCast(usize, tgt.payload_idx)];
        var fstart: usize = @intCast(usize, tp.fields_start);
        var fcount: usize = @intCast(usize, tp.fields_count);
        var field_inits = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var fii: usize = 0;
        while (fii < field_inits.len) : (fii += 1) {
            var fi_node = self.store.nodes.items[@intCast(usize, field_inits[fii])];
            if (fi_node.child_0 != @intCast(u32, 0)) {
                var fname_node = self.store.nodes.items[@intCast(usize, fi_node.child_0)];
                var fname_id = fname_node.payload;
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.registry.fe_items[fstart + fi].name_id == fname_id) {
                        if (fi_node.child_1 != @intCast(u32, 0)) {
                            _ = semanticAnalyzerResolveExpr(self, fi_node.child_1);
                        }
                        break;
                    }
                }
            }
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, target_type);
        return target_type;
    }
    if (tgt.kind == type_mod.TypeKind.struct_type) {
        var sp = self.registry.st_items[@intCast(usize, tgt.payload_idx)];
        var fstart: usize = @intCast(usize, sp.fields_start);
        var fcount: usize = @intCast(usize, sp.fields_count);
        var field_inits = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var fii: usize = 0;
        while (fii < field_inits.len) : (fii += 1) {
            var fi_node = self.store.nodes.items[@intCast(usize, field_inits[fii])];
            if (fi_node.child_0 != @intCast(u32, 0)) {
                var fname_node = self.store.nodes.items[@intCast(usize, fi_node.child_0)];
                var fname_id = fname_node.payload;
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.registry.fe_items[fstart + fi].name_id == fname_id) {
                        if (fi_node.child_1 != @intCast(u32, 0)) {
                            _ = semanticAnalyzerResolveExpr(self, fi_node.child_1);
                        }
                        break;
                    }
                }
            }
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, target_type);
        return target_type;
    }
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveAssign(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) return type_mod.TYPE_VOID;
    if (type_mod.typeRegistryIsAssignable(self.registry, rhs, lhs)) {
        if (lhs != rhs) {
            var ck = coercion_mod.classifyCoercion(self.registry, rhs, lhs);
            if (ck != coercion_mod.CoercionKind.none) {
                coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, ck, lhs);
            }
        }
        return lhs;
    }
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveSwitchExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.payload == @intCast(u32, 0)) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
    var cond_type = semanticAnalyzerResolveExpr(self, node.child_0);
    self.current_switch_cond_tu = @intCast(u32, 0);
    if (cond_type != @intCast(u32, 0) and cond_type != type_mod.TYPE_VOID) {
        var cond_ty = self.registry.types_items[@intCast(usize, cond_type)];
        if (cond_ty.kind == type_mod.TypeKind.tagged_union_type) {
            self.current_switch_cond_tu = cond_type;
            var rs: []const u8 = "Z"; pal_mod.stderr_write(rs);
        }
    }
    var prongs = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (prongs.len == @intCast(usize, 0)) { self.current_switch_cond_tu = @intCast(u32, 0); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
    var unified: u32 = @intCast(u32, 0);
    var has_else: u8 = 0;
    var i: usize = 0;

    while (i < prongs.len) : (i += 1) {
        var prong = self.store.nodes.items[@intCast(usize, prongs[i])];
        if ((prong.flags & @intCast(u8, 1)) != @intCast(u8, 0)) has_else = 1;
        if (self.current_switch_cond_tu != @intCast(u32, 0) and prong.payload != @intCast(u32, 0)) {
            var case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong.payload);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                var case_node = self.store.nodes.items[@intCast(usize, case_ec[ci])];
                if (case_node.kind == AstKind.enum_literal) {
                    _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                }
            }
        }
        var bt = semanticAnalyzerResolveExpr(self, prong.child_0);
        if (i == @intCast(usize, 0)) { unified = bt; }
        else if (bt == type_mod.TYPE_NORETURN) {}
        else if (bt == unified) {}
        else {
            var unum: u32 = @intCast(u32, 0);
            if (type_mod.typeRegistryIsNumeric(self.registry, bt)) { unum = @intCast(u32, 1); }
            if (unified == type_mod.TYPE_INT_LIT and unum != @intCast(u32, 0)) { unified = bt; }
            else { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
        }
    }

    self.current_switch_cond_tu = @intCast(u32, 0);
    if (has_else == @intCast(u8, 0)) {
    }
    if (unified == @intCast(u32, 0)) unified = type_mod.TYPE_VOID;
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, unified);
    return unified;
}

pub fn semanticAnalyzerResolveExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var result: u32;
    result = @intCast(u32, 0);
    if (node_idx == @intCast(u32, 0)) return result;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    result = type_mod.TYPE_VOID;

    if (node.kind == AstKind.int_literal) {
        result = type_mod.TYPE_INT_LIT;
    } else if (node.kind == AstKind.float_literal) {
        result = type_mod.TYPE_F64;
    } else if (node.kind == AstKind.char_literal) {
        result = type_mod.TYPE_U8;
    } else if (node.kind == AstKind.bool_literal) {
        result = type_mod.TYPE_BOOL;
    } else if (node.kind == AstKind.null_literal) {
        result = type_mod.TYPE_NULL;
    } else if (node.kind == AstKind.undefined_literal) {
        result = type_mod.TYPE_UNDEFINED;
    } else if (node.kind == AstKind.unreachable_expr) {
        result = type_mod.TYPE_NORETURN;
    } else if (node.kind == AstKind.string_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.enum_literal) {
        result = semanticAnalyzerResolveEnumLiteral(self, node_idx);
    } else if (node.kind == AstKind.error_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.ident_expr) {
        result = semanticAnalyzerResolveIdent(self, self.module_id, self.store.identifiers.items[@intCast(usize, node.payload)]);
    } else if (node.kind == AstKind.field_access) {
        result = semanticAnalyzerResolveFieldAccess(self, node_idx);
    } else if (node.kind == AstKind.index_access) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.slice_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.deref) {
        var base = semanticAnalyzerResolveExpr(self, node.child_0);
        if (base != @intCast(u32, 0) and base != type_mod.TYPE_VOID) {
            var bt = self.registry.types_items[@intCast(usize, base)];
            if (bt.kind == type_mod.TypeKind.ptr_type or bt.kind == type_mod.TypeKind.many_ptr_type) {
                var pp = self.registry.ptr_items[@intCast(usize, bt.payload_idx)];
                result = pp.base;
            } else {
                result = base;
            }
        } else {
            result = type_mod.TYPE_VOID;
        }
    } else if (node.kind == AstKind.address_of) {
        var base = semanticAnalyzerResolveExpr(self, node.child_0);
        if (base != @intCast(u32, 0) and base != type_mod.TYPE_VOID) {
            result = type_mod.typeRegistryGetOrCreatePtr(self.registry, base, false);
        } else {
            result = type_mod.TYPE_VOID;
        }
    } else if (node.kind == AstKind.fn_call) {
        result = semanticAnalyzerResolveFnCall(self, node_idx);
    } else if (node.kind == AstKind.builtin_call) {
        var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        if (ec.len >= @intCast(usize, 1)) {
            result = semanticAnalyzerResolveExpr(self, ec[0]);
        } else {
            result = type_mod.TYPE_VOID;
        }
    } else if (node.kind == AstKind.bool_not) {
        result = type_mod.TYPE_BOOL;
    } else if (node.kind == AstKind.negate) {
        result = semanticAnalyzerResolveNegate(self, node_idx);
    } else if (node.kind == AstKind.bit_not) {
        result = semanticAnalyzerResolveBitNot(self, node_idx);
    } else if (node.kind == AstKind.try_expr) {
        result = semanticAnalyzerResolveTryExpr(self, node_idx);
    } else if (node.kind == AstKind.catch_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.orelse_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.if_expr) {
        result = semanticAnalyzerResolveIfExpr(self, node_idx);
    } else if (node.kind == AstKind.switch_expr) {
        result = semanticAnalyzerResolveSwitchExpr(self, node_idx);
    } else if (node.kind == AstKind.tuple_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.struct_init) {
        result = semanticAnalyzerResolveStructInit(self, node_idx);
    } else if (node.kind == AstKind.array_init) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.ptr_type or node.kind == AstKind.many_ptr_type or
               node.kind == AstKind.array_type or node.kind == AstKind.slice_type or
               node.kind == AstKind.optional_type or node.kind == AstKind.error_union_type or
               node.kind == AstKind.fn_type or node.kind == AstKind.struct_decl or
               node.kind == AstKind.enum_decl or node.kind == AstKind.union_decl or
               node.kind == AstKind.error_set_decl) {
        result = type_mod.TYPE_TYPE;
    } else if (node.kind == AstKind.paren_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.expr_stmt) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.block) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.add or node.kind == AstKind.sub or
               node.kind == AstKind.mul or node.kind == AstKind.div or
               node.kind == AstKind.mod_op) {
        result = semanticAnalyzerResolveArithmetic(self, node_idx, node.kind);
    } else if (node.kind == AstKind.bit_and or node.kind == AstKind.bit_or or
               node.kind == AstKind.bit_xor or node.kind == AstKind.shl or
               node.kind == AstKind.shr) {
        result = semanticAnalyzerResolveBitwise(self, node_idx);
    } else if (node.kind == AstKind.bool_and or node.kind == AstKind.bool_or) {
        result = semanticAnalyzerResolveLogical(self, node_idx);
    } else if (node.kind == AstKind.cmp_eq or node.kind == AstKind.cmp_ne or
               node.kind == AstKind.cmp_lt or node.kind == AstKind.cmp_le or
               node.kind == AstKind.cmp_gt or node.kind == AstKind.cmp_ge) {
        result = semanticAnalyzerResolveComparison(self, node_idx, node.kind);
    } else if (node.kind == AstKind.assign or
               node.kind == AstKind.add_assign or node.kind == AstKind.sub_assign or
               node.kind == AstKind.mul_assign or node.kind == AstKind.div_assign or
               node.kind == AstKind.mod_assign or node.kind == AstKind.shl_assign or
               node.kind == AstKind.shr_assign or node.kind == AstKind.and_assign or
               node.kind == AstKind.or_assign or node.kind == AstKind.xor_assign) {
        result = semanticAnalyzerResolveAssign(self, node_idx);
    } else {
        result = type_mod.TYPE_VOID;
    }

    if (result != type_mod.TYPE_VOID) {
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
    }
    return result;
}

pub fn semanticAnalyzerResolveFnBody(self: *SemanticAnalyzer, fn_decl_node: u32) void {
    var decl = self.store.nodes.items[@intCast(usize, fn_decl_node)];
    if (decl.kind != AstKind.fn_decl) return;
    var store = self.store;
    var proto = store.fn_protos.items[@intCast(usize, decl.payload)];
    if (decl.child_0 == @intCast(u32, 0)) return;
    if (proto.params_count > @intCast(u16, 0)) {
        var p_payload: u32 = (@intCast(u32, proto.params_start) << @intCast(u32, 16)) | @intCast(u32, proto.params_count);
        var pnodes = ast_mod.astStoreGetExtraChildren(store, p_payload);
        var pi: usize = @intCast(usize, 0);
        while (pi < pnodes.len) : (pi += @intCast(usize, 1)) {
            var pnode = store.nodes.items[@intCast(usize, pnodes[pi])];
            if (pnode.child_0 != @intCast(u32, 0)) {
                if (self.local_decl_count >= self.local_decl_cap) {
                    semanticAnalyzerGrowLocalDecls(self);
                }
                self.local_decl_names[self.local_decl_count] = pnode.payload;
                var rt = rtt_mod.resolvedTypeTableGet(self.type_table, pnode.child_0);
                if (rt) |t| {
                    self.local_decl_types[self.local_decl_count] = t;
                } else {
                    self.local_decl_types[self.local_decl_count] = type_mod.TYPE_UNDEFINED;
                }
                self.local_decl_count += @intCast(usize, 1);
            }
        }
    }
    semanticAnalyzerResolveStmt(self, decl.child_0);
}

pub fn semanticAnalyzerResolveStmtDepth(self: *SemanticAnalyzer, node_idx: u32, depth: u32) void {
    if (depth > @intCast(u32, 16)) return;
    if (node_idx == @intCast(u32, 0)) return;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.block) {
        var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        var i: usize = 0;
        while (i < children.len) : (i += 1) {
            semanticAnalyzerResolveStmtDepth(self, children[i], depth + @intCast(u32, 1));
        }
    } else if (node.kind == AstKind.var_decl) {
        var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (node.child_0 != @intCast(u32, 0)) {
            _ = semanticAnalyzerResolveExpr(self, node.child_0);
            var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
            if (rt) |t| { decl_type = t; }
        }
        if (node.child_1 != @intCast(u32, 0)) {
            var it = semanticAnalyzerResolveExpr(self, node.child_1);
            if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED)) { decl_type = it; }
        }
        if (self.local_decl_count >= self.local_decl_cap) {
            semanticAnalyzerGrowLocalDecls(self);
        }
        self.local_decl_names[self.local_decl_count] = node.payload;
        self.local_decl_types[self.local_decl_count] = decl_type;
        self.local_decl_count += @intCast(usize, 1);
    } else if (node.kind == AstKind.if_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
        if (node.child_2 != @intCast(u32, 0)) {
            semanticAnalyzerResolveStmtDepth(self, node.child_2, depth + @intCast(u32, 1));
        }
    } else if (node.kind == AstKind.while_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.for_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.switch_expr) {
        _ = semanticAnalyzerResolveExpr(self, node_idx);
        if (node.payload != @intCast(u32, 0)) {
            var prongs = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
            var pi: usize = 0;
            while (pi < prongs.len) : (pi += 1) {
                var prong_node = self.store.nodes.items[@intCast(usize, prongs[pi])];
                if (prong_node.child_0 != @intCast(u32, 0)) {
                    semanticAnalyzerResolveStmtDepth(self, prong_node.child_0, depth + @intCast(u32, 1));
                }
            }
        }
    } else if (node.kind == AstKind.return_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            _ = semanticAnalyzerResolveExpr(self, node.child_0);
        }
    } else if (node.kind == AstKind.assign or
               node.kind == AstKind.add_assign or node.kind == AstKind.sub_assign or
               node.kind == AstKind.mul_assign or node.kind == AstKind.div_assign or
               node.kind == AstKind.mod_assign or node.kind == AstKind.shl_assign or
               node.kind == AstKind.shr_assign or node.kind == AstKind.and_assign or
               node.kind == AstKind.or_assign or node.kind == AstKind.xor_assign) {
        _ = semanticAnalyzerResolveExpr(self, node_idx);
    } else if (node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt) {
        semanticAnalyzerResolveStmtDepth(self, node.child_0, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.break_stmt) {
    } else if (node.kind == AstKind.continue_stmt) {
    } else {
        _ = semanticAnalyzerResolveExpr(self, node_idx);
    }
    if (node.child_0 != @intCast(u32, 0)) {
        var nc = self.store.nodes.items[@intCast(usize, node.child_0)];
        if (nc.kind == AstKind.fn_decl) return;
    }
    if (node.child_1 != @intCast(u32, 0)) {
        var nc = self.store.nodes.items[@intCast(usize, node.child_1)];
        if (nc.kind == AstKind.fn_decl) return;
    }
}

pub fn semanticAnalyzerResolveStmt(self: *SemanticAnalyzer, node_idx: u32) void {
    semanticAnalyzerResolveStmtDepth(self, node_idx, @intCast(u32, 0));
}
