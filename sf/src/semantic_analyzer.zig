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
const itoa_mod = @import("util/itoa.zig");
const interner_mod = @import("string_interner.zig");

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
    call_arg_types: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
};

pub fn semanticAnalyzerInit(alloc: *Sand, type_table: *ResolvedTypeTable, diag: *DiagnosticCollector, registry: *TypeRegistry, symbols: *SymbolRegistry, store: *AstStore, module_id: u32, coercion_tab: *coercion_mod.CoercionTable, enum_val_tab: *hash_mod.U32ToU32Map, interner: *interner_mod.StringInterner, cal_typs: *hash_mod.U32ToU32Map) SemanticAnalyzer {
    var und_text: []const u8 = "_";
    var und_name_id = interner_mod.stringInternerIntern(interner, und_text);
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
        ._stub_0 = und_name_id,
        ._stub_1 = @intCast(u32, 0),
        .call_arg_types = cal_typs,
        .interner = interner,
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

pub fn semanticAnalyzerResolveIdent(self: *SemanticAnalyzer, module_id: u32, name_id: u32, node_idx: u32) u32 {
    var ide: []const u8 = "IDE"; pal_mod.stderr_write(ide);
    var li = self.local_decl_count;
    while (li > @intCast(usize, 0)) {
        li -= @intCast(usize, 1);
            if (self.local_decl_names[li] == name_id) {
                var lcl_t = self.local_decl_types[li];
                var d7m: []const u8 = "D7:Yn"; pal_mod.stderr_write(d7m);
                var d7nb: [10]u8 = undefined; var d7nl = itoa_mod.itoa(name_id, d7nb[0..]); var d7ns: usize = @intCast(usize, 9) - @intCast(usize, d7nl); pal_mod.stderr_write(d7nb[d7ns..@intCast(usize, 9)]);
                var d7tm: []const u8 = "t"; pal_mod.stderr_write(d7tm);
                var d7tb: [10]u8 = undefined; var d7tl = itoa_mod.itoa(lcl_t, d7tb[0..]); var d7ts: usize = @intCast(usize, 9) - @intCast(usize, d7tl); pal_mod.stderr_write(d7tb[d7ts..@intCast(usize, 9)]);
                var d7sp: []const u8 = " "; pal_mod.stderr_write(d7sp);
                var ri: []const u8 = "R"; pal_mod.stderr_write(ri);
            var id1: []const u8 = "L"; pal_mod.stderr_write(id1);
            var lcl_b: [20]u8 = undefined; var lcl_l = itoa_mod.itoa(lcl_t, lcl_b[0..]); var lcl_s: usize = @intCast(usize, 19) - @intCast(usize, lcl_l); pal_mod.stderr_write(lcl_b[lcl_s..@intCast(usize, 19)]);
            return lcl_t;
        }
    }
    var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, name_id);
    if (sym) |s| {
        var id2: []const u8 = "S"; pal_mod.stderr_write(id2);
        if (s.kind == sym_mod.SymbolKind.type_alias) return s.type_id;
        if (s.type_id != @intCast(u32, 0)) return s.type_id;
        return type_mod.TYPE_VOID;
    }
    var key = @intCast(u64, name_id);
    var tid = type_mod.nameCacheGet(self.registry, key);
    if (tid) |t| { var id3: []const u8 = "C"; pal_mod.stderr_write(id3); return t; }
     var id4: []const u8 = "D8:Nn"; pal_mod.stderr_write(id4);
     var d8nb: [10]u8 = undefined; var d8nl = itoa_mod.itoa(name_id, d8nb[0..]); var d8ns: usize = @intCast(usize, 9) - @intCast(usize, d8nl); pal_mod.stderr_write(d8nb[d8ns..@intCast(usize, 9)]);
     var d8cm: []const u8 = "c"; pal_mod.stderr_write(d8cm);
     var d8cb: [10]u8 = undefined; var d8cl = itoa_mod.itoa(@intCast(u32, self.local_decl_count), d8cb[0..]); var d8cs: usize = @intCast(usize, 9) - @intCast(usize, d8cl); pal_mod.stderr_write(d8cb[d8cs..@intCast(usize, 9)]);
     if (self.local_decl_count > @intCast(usize, 0)) {
         var d8fm: []const u8 = "f"; pal_mod.stderr_write(d8fm);
         var d8fb: [10]u8 = undefined; var d8fl = itoa_mod.itoa(self.local_decl_names[@intCast(usize, 0)], d8fb[0..]); var d8fs: usize = @intCast(usize, 9) - @intCast(usize, d8fl); pal_mod.stderr_write(d8fb[d8fs..@intCast(usize, 9)]);
         var d8lm: []const u8 = "l"; pal_mod.stderr_write(d8lm);
         var d8lb: [10]u8 = undefined; var d8ll = itoa_mod.itoa(self.local_decl_names[self.local_decl_count - @intCast(usize, 1)], d8lb[0..]); var d8ls: usize = @intCast(usize, 9) - @intCast(usize, d8ll); pal_mod.stderr_write(d8lb[d8ls..@intCast(usize, 9)]);
     }
     if (self.local_decl_count > @intCast(usize, 4)) {
         var d8x: []const u8 = "x"; pal_mod.stderr_write(d8x);
         var d8x5: [10]u8 = undefined; var d8x5l = itoa_mod.itoa(self.local_decl_names[@intCast(usize, 4)], d8x5[0..]); var d8x5s: usize = @intCast(usize, 9) - @intCast(usize, d8x5l); pal_mod.stderr_write(d8x5[d8x5s..@intCast(usize, 9)]);
     }
     var d8sp: []const u8 = "i"; pal_mod.stderr_write(d8sp);
     var d8ib: [10]u8 = undefined; var d8il = itoa_mod.itoa(node_idx, d8ib[0..]); var d8is: usize = @intCast(usize, 9) - @intCast(usize, d8il); pal_mod.stderr_write(d8ib[d8is..@intCast(usize, 9)]);
      var d8nll: []const u8 = " "; pal_mod.stderr_write(d8nll);
       if (node_idx == @intCast(u32, 436) or name_id == @intCast(u32, 55)) {
           var cname = interner_mod.stringInternerGet(self.interner, name_id);
           pal_mod.stderr_write(cname);
           var d8kn: []const u8 = " k="; pal_mod.stderr_write(d8kn);
          var cnode = self.store.nodes.items[@intCast(usize, node_idx)];
          var d8kb: [10]u8 = undefined; var d8kl = itoa_mod.itoa(@intCast(u32, cnode.kind), d8kb[0..]); var d8ks: usize = @intCast(usize, 9) - @intCast(usize, d8kl); pal_mod.stderr_write(d8kb[d8ks..@intCast(usize, 9)]);
          var d8rt: []const u8 = "r"; pal_mod.stderr_write(d8rt);
          var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node_idx);
          if (rt) |t| { var d8tb: [10]u8 = undefined; var d8tl = itoa_mod.itoa(t, d8tb[0..]); var d8ts: usize = @intCast(usize, 9) - @intCast(usize, d8tl); pal_mod.stderr_write(d8tb[d8ts..@intCast(usize, 9)]); }
          else { var d8z: []const u8 = "Z"; pal_mod.stderr_write(d8z); }
          var d8nl2: []const u8 = "\n"; pal_mod.stderr_write(d8nl2);
      }
    if (name_id == self._stub_0) {
        return type_mod.TYPE_UNDEFINED;
    }
    return type_mod.TYPE_VOID;
}

pub fn semanticAnalyzerResolveFieldAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var fae: []const u8 = "FAE"; pal_mod.stderr_write(fae);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var base_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var field_name_id = node.payload;
    var pfa_bk: [20]u8 = undefined; var pfa_bkl = itoa_mod.itoa(@intCast(u32, @enumToInt(base_node.kind)), pfa_bk[0..]); var pfa_bks: usize = @intCast(usize, 19) - @intCast(usize, pfa_bkl); var pfa_bm: []const u8 = "BK"; pal_mod.stderr_write(pfa_bm); pal_mod.stderr_write(pfa_bk[pfa_bks..@intCast(usize, 19)]);
    var pfa_fn: [20]u8 = undefined; var pfa_fnl = itoa_mod.itoa(field_name_id, pfa_fn[0..]); var pfa_fns: usize = @intCast(usize, 19) - @intCast(usize, pfa_fnl); var pfa_fm: []const u8 = "FN"; pal_mod.stderr_write(pfa_fm); pal_mod.stderr_write(pfa_fn[pfa_fns..@intCast(usize, 19)]);

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
                                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, alias_type_id);
                                return alias_type_id;
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
        var fa1: []const u8 = "FB"; pal_mod.stderr_write(fa1);
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
    } else if (base_ty.kind == type_mod.TypeKind.module_type) {
        var mfa: []const u8 = "MFA"; pal_mod.stderr_write(mfa);
        var mod_field_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, base_ty.module_id, field_name_id);
        if (mod_field_sym) |mfs| {
            if (mfs.type_id != @intCast(u32, 0)) {
                var mf1: []const u8 = "MF1"; pal_mod.stderr_write(mf1);
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, mfs.type_id);
                return mfs.type_id;
            }
            if (mfs.kind == sym_mod.SymbolKind.function) {
                var fn_tid_opt = rtt_mod.resolvedTypeTableGet(self.type_table, mfs.decl_node);
                if (fn_tid_opt) |fn_tid| {
                    var mf1: []const u8 = "MF1"; pal_mod.stderr_write(mf1);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_tid);
                    return fn_tid;
                }
                var mff: []const u8 = "MFF"; pal_mod.stderr_write(mff);
                var dn = self.store.nodes.items[@intCast(usize, mfs.decl_node)];
                if (dn.kind == AstKind.fn_decl) {
                    var proto = self.store.fn_protos.items[@intCast(usize, dn.payload)];
                    var mfp_buf: [20]u8 = undefined; var mfp_len = itoa_mod.itoa(@intCast(u32, proto.params_start), mfp_buf[0..]); var mfp_s: usize = @intCast(usize, 19) - @intCast(usize, mfp_len); var mfp_m: []const u8 = "MFP"; pal_mod.stderr_write(mfp_m); pal_mod.stderr_write(mfp_buf[mfp_s..@intCast(usize, 19)]);
                    if (proto.return_type_node != @intCast(u32, 0)) {
                        var rtt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                        if (rtt) |rtv| {
                            var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, proto.params_start, proto.params_count, rtv);
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                            return fn_ty;
                        }
                    }
                    var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, proto.params_start, proto.params_count, type_mod.TYPE_VOID);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                    return fn_ty;
                }
            }
            var mf2: []const u8 = "MF2"; pal_mod.stderr_write(mf2);
            var mf2_k: [20]u8 = undefined; var mf2_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(mfs.kind)), mf2_k[0..]); var mf2_ks: usize = @intCast(usize, 19) - @intCast(usize, mf2_kl); pal_mod.stderr_write(mf2_k[mf2_ks..@intCast(usize, 19)]);
        } else {
            var mf3: []const u8 = "MF3"; pal_mod.stderr_write(mf3);
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    } else if (base_ty.kind == type_mod.TypeKind.slice_type) {
        var sp = self.registry.slice_items[@intCast(usize, base_ty.payload_idx)];
        var len_s: []const u8 = "len";
        var len_id = interner_mod.stringInternerIntern(self.interner, len_s);
        if (field_name_id == len_id) {
            var fsl: []const u8 = "FSL:USIZE\n"; pal_mod.stderr_write(fsl);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_USIZE);
            return type_mod.TYPE_USIZE;
        }
        var ptr_s: []const u8 = "ptr";
        var ptr_id = interner_mod.stringInternerIntern(self.interner, ptr_s);
        if (field_name_id == ptr_id) {
            var pty = type_mod.typeRegistryGetOrCreatePtr(self.registry, sp.elem, false);
            var fsp: []const u8 = "FSP:PTR\n"; pal_mod.stderr_write(fsp);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, pty);
            return pty;
        }
    } else {
        var fnf: []const u8 = "FF"; pal_mod.stderr_write(fnf);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }

    var fi: usize = 0;
    while (fi < fields_count) {
        var fe = self.registry.fe_items[fields_start + fi];
        if (fe.name_id == field_name_id) {
            var result = fe.type_id;
            if (base_ty.kind == type_mod.TypeKind.tagged_union_type) { result = base_type_id; }
            var ff: []const u8 = "FF:"; pal_mod.stderr_write(ff);
            var ff_b: [20]u8 = undefined; var ff_l = itoa_mod.itoa(result, ff_b[0..]); var ff_s: usize = @intCast(usize, 19) - @intCast(usize, ff_l); pal_mod.stderr_write(ff_b[ff_s..@intCast(usize, 19)]);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
            return result;
        }
        fi += 1;
    }

    var fnf2: []const u8 = "NF"; pal_mod.stderr_write(fnf2);
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

    if (!type_mod.typeRegistryIsNumeric(self.registry, lhs) or !type_mod.typeRegistryIsNumeric(self.registry, rhs)) return type_mod.TYPE_VOID;
    if (lhs == rhs) return lhs;
    var ls = self.registry.types_items[@intCast(usize, lhs)].size;
    var rs = self.registry.types_items[@intCast(usize, rhs)].size;
    if (ls >= rs) return lhs;
    return rhs;
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
    var cpe: []const u8 = "CPE"; pal_mod.stderr_write(cpe);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) { var cp0: []const u8 = "CP0"; pal_mod.stderr_write(cp0); return type_mod.TYPE_VOID; }
    if (lhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, rhs)) { var cp1: []const u8 = "CPB"; pal_mod.stderr_write(cp1); return type_mod.TYPE_BOOL; }
    if (rhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, lhs)) { var cp2: []const u8 = "CPB"; pal_mod.stderr_write(cp2); return type_mod.TYPE_BOOL; }
    var lhs_num = type_mod.typeRegistryIsNumeric(self.registry, lhs);
    if (lhs_num and lhs == rhs) { var cp3: []const u8 = "CPB"; pal_mod.stderr_write(cp3); return type_mod.TYPE_BOOL; }
    if (op_kind == AstKind.cmp_eq or op_kind == AstKind.cmp_ne) {
        if (type_mod.typeRegistryIsOptional(self.registry, lhs) and rhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsOptional(self.registry, rhs) and lhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsErrorSet(self.registry, lhs) and type_mod.typeRegistryIsErrorSet(self.registry, rhs)) { var cp4: []const u8 = "CPB"; pal_mod.stderr_write(cp4); return type_mod.TYPE_BOOL; }
    }
    var cpv: []const u8 = "CPV"; pal_mod.stderr_write(cpv);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveLogical(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var loe: []const u8 = "LOE"; pal_mod.stderr_write(loe);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == type_mod.TYPE_BOOL and rhs == type_mod.TYPE_BOOL) { var lo1: []const u8 = "LOB"; pal_mod.stderr_write(lo1); return type_mod.TYPE_BOOL; }
    var lo2: []const u8 = "LOV"; pal_mod.stderr_write(lo2);
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
    var fne: []const u8 = "FNE"; pal_mod.stderr_write(fne);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var callee_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var direct_ret: u32 = @intCast(u32, 0);
    var decl_cap: u32 = 0;
    if (callee_node.kind == AstKind.ident_expr) {
        var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, self.store.identifiers.items[@intCast(usize, callee_node.payload)]);
        if (sym) |s| { var xf: []const u8 = "XF"; pal_mod.stderr_write(xf);
            decl_cap = s.decl_node;
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
        var fn1: []const u8 = "FN1"; pal_mod.stderr_write(fn1);
        var fn1_rb: [20]u8 = undefined; var fn1_rl = itoa_mod.itoa(direct_ret, fn1_rb[0..]); var fn1_rs: usize = @intCast(usize, 19) - @intCast(usize, fn1_rl); var fn1_rm: []const u8 = "R"; pal_mod.stderr_write(fn1_rm); pal_mod.stderr_write(fn1_rb[fn1_rs..@intCast(usize, 19)]);
        var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        if (decl_cap != 0) {
            var ft = rtt_mod.resolvedTypeTableGet(self.type_table, decl_cap);
            if (ft) |ftid| { var sfm: []const u8 = "SF:H\n"; pal.stderr_write(sfm);
            var ft_ty = self.registry.types_items[@intCast(usize, ftid)];
            if (ft_ty.kind == type_mod.TypeKind.fn_type) {
                var ftp = self.registry.fn_items[@intCast(usize, ft_ty.payload_idx)];
                var ai2: usize = 0;
                while (ai2 < args.len and ai2 < @intCast(usize, ftp.params_count)) : (ai2 += 1) {
                    var pt = self.registry.xt_items[@intCast(usize, ftp.params_start) + ai2];
                    hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai2], pt);
                }
            }
            }
        }
        var ai: usize = 0;
        while (ai < args.len) : (ai += 1) {
            _ = semanticAnalyzerResolveExpr(self, args[ai]);
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, direct_ret);
        return direct_ret;
    }
    var callee_type = semanticAnalyzerResolveExpr(self, node.child_0);
    if (callee_type == @intCast(u32, 0)) { var fn2: []const u8 = "FN2"; pal_mod.stderr_write(fn2); return type_mod.TYPE_VOID; }
    var callee_ty = self.registry.types_items[@intCast(usize, callee_type)];
    if (callee_ty.kind != type_mod.TypeKind.fn_type) {
        var fn3: []const u8 = "FN3:"; pal_mod.stderr_write(fn3);
        var fn3_nid_buf: [20]u8 = undefined; var fn3_nid_len = itoa_mod.itoa(node_idx, fn3_nid_buf[0..]); var fn3_nid_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_nid_len); pal_mod.stderr_write(fn3_nid_buf[fn3_nid_s..@intCast(usize, 19)]);
        var fn3_ct_buf: [20]u8 = undefined; var fn3_ct_len = itoa_mod.itoa(callee_type, fn3_ct_buf[0..]); var fn3_ct_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_ct_len); var fn3_ct_m: []const u8 = "c"; pal_mod.stderr_write(fn3_ct_m); pal_mod.stderr_write(fn3_ct_buf[fn3_ct_s..@intCast(usize, 19)]);
        var fn3_ck_buf: [20]u8 = undefined; var fn3_ck_len = itoa_mod.itoa(@intCast(u32, @enumToInt(callee_ty.kind)), fn3_ck_buf[0..]); var fn3_ck_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_ck_len); var fn3_ck_m: []const u8 = "k"; pal_mod.stderr_write(fn3_ck_m); pal_mod.stderr_write(fn3_ck_buf[fn3_ck_s..@intCast(usize, 19)]);
        return type_mod.TYPE_VOID;
    }
    var fn4a: []const u8 = "FN4a"; pal_mod.stderr_write(fn4a);
    var fnp = self.registry.fn_items[@intCast(usize, callee_ty.payload_idx)];
    var fn4b: []const u8 = "FN4b"; pal_mod.stderr_write(fn4b);
    var pcount: usize = @intCast(usize, fnp.params_count);
    var pstart: usize = @intCast(usize, fnp.params_start);
    var fn4c: []const u8 = "FN4c"; pal_mod.stderr_write(fn4c);
    var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    var fn4d: []const u8 = "FN4d"; pal_mod.stderr_write(fn4d);
    if (args.len != pcount) {
        return fnp.return_type;
    }
    var ai: usize = 0;
    var fn4e: []const u8 = "FN4e"; pal_mod.stderr_write(fn4e);
    var fn4x_buf: [20]u8 = undefined; var fn4x_len = itoa_mod.itoa(@intCast(u32, self.registry.xt_len), fn4x_buf[0..]); var fn4x_s: usize = @intCast(usize, 19) - @intCast(usize, fn4x_len); var fn4x_m: []const u8 = "FN4x"; pal_mod.stderr_write(fn4x_m); pal_mod.stderr_write(fn4x_buf[fn4x_s..@intCast(usize, 19)]);
    var fn4y_buf: [20]u8 = undefined; var fn4y_len = itoa_mod.itoa(@intCast(u32, pstart), fn4y_buf[0..]); var fn4y_s: usize = @intCast(usize, 19) - @intCast(usize, fn4y_len); var fn4y_m: []const u8 = "FN4y"; pal_mod.stderr_write(fn4y_m); pal_mod.stderr_write(fn4y_buf[fn4y_s..@intCast(usize, 19)]);
    while (ai < args.len) : (ai += 1) {
        var fn4f: []const u8 = "FN4f"; pal_mod.stderr_write(fn4f);
        var param_type = self.registry.xt_items[pstart + ai];
        hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], param_type);
        var fn4g: []const u8 = "FN4g"; pal_mod.stderr_write(fn4g);
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
    var fn4: []const u8 = "FN4"; pal_mod.stderr_write(fn4);
    var fn4_rb: [20]u8 = undefined; var fn4_rl = itoa_mod.itoa(fnp.return_type, fn4_rb[0..]); var fn4_rs: usize = @intCast(usize, 19) - @intCast(usize, fn4_rl); var fn4_rm: []const u8 = "R"; pal_mod.stderr_write(fn4_rm); pal_mod.stderr_write(fn4_rb[fn4_rs..@intCast(usize, 19)]);
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
    var el: []const u8 = "eL"; pal_mod.stderr_write(el);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var n: u32 = self.store.identifiers.items[@intCast(usize, node.payload)];
    if (self.current_switch_cond_tu != @intCast(u32, 0)) {
        var tu_ty = self.registry.types_items[@intCast(usize, self.current_switch_cond_tu)];
        if (tu_ty.kind == type_mod.TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
            var fstart: usize = @intCast(usize, tp.fields_start);
            var fcount: usize = @intCast(usize, tp.fields_count);
            var f0: u32 = @intCast(u32, self.registry.fe_items[fstart].name_id);
            var nb: [20]u8 = undefined; var fb: [20]u8 = undefined;
            var nl = itoa_mod.itoa(n, nb[0..]); var fl = itoa_mod.itoa(f0, fb[0..]);
            var ns = @intCast(usize, 19) - @intCast(usize, nl); var fs2 = @intCast(usize, 19) - @intCast(usize, fl);
            var nd: []const u8 = "n"; pal_mod.stderr_write(nd); pal_mod.stderr_write(nb[ns..@intCast(usize, 19)]);
            var fd: []const u8 = "f"; pal_mod.stderr_write(fd); pal_mod.stderr_write(fb[fs2..@intCast(usize, 19)]);
            var sp: []const u8 = " "; pal_mod.stderr_write(sp);
            var fcB: [20]u8 = undefined; var fcL = itoa_mod.itoa(@intCast(u32, fcount), fcB[0..]);
            var fcS: usize = @intCast(usize, 19) - @intCast(usize, fcL);
            var fcT: []const u8 = "fc="; pal_mod.stderr_write(fcT); pal_mod.stderr_write(fcB[fcS..@intCast(usize, 19)]);
            var fcP: []const u8 = " "; pal_mod.stderr_write(fcP);
            var fi: usize = 0;
            while (fi < fcount) : (fi += 1) {
                var fe = self.registry.fe_items[fstart + fi];
                var feb: [20]u8 = undefined; var feL = itoa_mod.itoa(@intCast(u32, fe.name_id), feb[0..]);
                var fes: usize = @intCast(usize, 19) - @intCast(usize, feL);
                var feT: []const u8 = "g"; pal_mod.stderr_write(feT); pal_mod.stderr_write(feb[fes..@intCast(usize, 19)]);
                var feP: []const u8 = " "; pal_mod.stderr_write(feP);
                if (fe.name_id == n) {
                    hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, @intCast(u32, fi));
                    var ew: []const u8 = "EW"; pal_mod.stderr_write(ew);
                    var evgc = self.enum_value_table.count;
                    var eg_buf: [20]u8 = undefined;
                    var eg_len = itoa_mod.itoa(@intCast(u32, evgc), eg_buf[0..]);
                    var egs: usize = @intCast(usize, 19) - @intCast(usize, eg_len);
                    var eN: []const u8 = "eN="; pal_mod.stderr_write(eN);
                    pal_mod.stderr_write(eg_buf[egs..@intCast(usize, 19)]);
                    var eS: []const u8 = " "; pal_mod.stderr_write(eS);
                    var re: []const u8 = "E"; pal_mod.stderr_write(re);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, self.current_switch_cond_tu);
                    return self.current_switch_cond_tu;
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
    var ase: []const u8 = "ASE"; pal_mod.stderr_write(ase);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) { var as0: []const u8 = "AS0"; pal_mod.stderr_write(as0); return type_mod.TYPE_VOID; }
    if (type_mod.typeRegistryIsAssignable(self.registry, rhs, lhs)) {
        if (lhs != rhs) {
            var ck = coercion_mod.classifyCoercion(self.registry, rhs, lhs);
            if (ck != coercion_mod.CoercionKind.none) {
                coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, ck, lhs);
            }
        }
        var as1: []const u8 = "AS1"; pal_mod.stderr_write(as1);
        return lhs;
    }
    var as2: []const u8 = "AS2"; pal_mod.stderr_write(as2);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveSwitchExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var se: []const u8 = "SE"; pal_mod.stderr_write(se);
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
        var pct = self.current_switch_cond_tu; var pp = prong.payload;
        var pct_buf: [20]u8 = undefined; var pp_buf: [20]u8 = undefined;
        var pct_len = itoa_mod.itoa(pct, pct_buf[0..]);
        var pp_len = itoa_mod.itoa(pp, pp_buf[0..]);
        var ps1: usize = @intCast(usize, 19) - @intCast(usize, pct_len);
        var ps2: usize = @intCast(usize, 19) - @intCast(usize, pp_len);
        var pS: []const u8 = "pC="; pal_mod.stderr_write(pS);
        pal_mod.stderr_write(pct_buf[ps1..@intCast(usize, 19)]);
        var pP: []const u8 = " pP="; pal_mod.stderr_write(pP);
        pal_mod.stderr_write(pp_buf[ps2..@intCast(usize, 19)]);
        var pn: []const u8 = " "; pal_mod.stderr_write(pn);
        if (self.current_switch_cond_tu != @intCast(u32, 0) and prong.payload != @intCast(u32, 0)) {
            var case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong.payload);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                var case_node = self.store.nodes.items[@intCast(usize, case_ec[ci])];
                var cc_buf: [20]u8 = undefined;
                var cc_val = @intCast(u32, @enumToInt(case_node.kind));
                var cc_len = itoa_mod.itoa(cc_val, cc_buf[0..]);
                var ccs: usize = @intCast(usize, 19) - @intCast(usize, cc_len);
                var ccS: []const u8 = "cK="; pal_mod.stderr_write(ccS);
                pal_mod.stderr_write(cc_buf[ccs..@intCast(usize, 19)]);
                    var ccP: []const u8 = " "; pal_mod.stderr_write(ccP);
                    if (case_node.kind == AstKind.enum_literal) {
                        _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                    } else if (case_node.kind == AstKind.undefined_literal) {
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
        result = semanticAnalyzerResolveIdent(self, self.module_id, self.store.identifiers.items[@intCast(usize, node.payload)], node_idx);
    } else if (node.kind == AstKind.field_access) {
        result = semanticAnalyzerResolveFieldAccess(self, node_idx);
        var fad: []const u8 = "FAD:"; pal_mod.stderr_write(fad);
        var fad_b: [20]u8 = undefined; var fad_l = itoa_mod.itoa(result, fad_b[0..]); var fad_s: usize = @intCast(usize, 19) - @intCast(usize, fad_l); pal_mod.stderr_write(fad_b[fad_s..@intCast(usize, 19)]);
    } else if (node.kind == AstKind.index_access) {
        result = semanticAnalyzerResolveIndexAccess(self, node_idx);
    } else if (node.kind == AstKind.slice_expr) {
        result = semanticAnalyzerResolveSliceExpr(self, node_idx);
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
        result = semanticAnalyzerResolveTupleLiteral(self, node_idx);
    } else if (node.kind == AstKind.struct_init) {
        result = semanticAnalyzerResolveStructInit(self, node_idx);
    } else if (node.kind == AstKind.array_init) {
        var ai_dbg: []const u8 = "AW";
        pal_mod.stderr_write(ai_dbg);
        result = semanticAnalyzerResolveArrayInit(self, node_idx);
        var aw_rb: [20]u8 = undefined; var aw_rl = itoa_mod.itoa(result, aw_rb[0..]); var aw_rs: usize = @intCast(usize, 19) - @intCast(usize, aw_rl); var aw_rm: []const u8 = "r"; pal_mod.stderr_write(aw_rm); pal_mod.stderr_write(aw_rb[aw_rs..@intCast(usize, 19)]);
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
        var st_k: [20]u8 = undefined;
        var st_l = itoa_mod.itoa(@intCast(u32, @enumToInt(node.kind)), st_k[0..]);
        var st_s: usize = @intCast(usize, 19) - @intCast(usize, st_l);
        var st_m: []const u8 = "ST:";
        pal_mod.stderr_write(st_m);
        pal_mod.stderr_write(st_k[st_s..@intCast(usize, 19)]);
        var st_nid_buf: [20]u8 = undefined; var st_nid_len = itoa_mod.itoa(node_idx, st_nid_buf[0..]); var st_nid_s: usize = @intCast(usize, 19) - @intCast(usize, st_nid_len); var st_nid_m: []const u8 = "n"; pal_mod.stderr_write(st_nid_m); pal_mod.stderr_write(st_nid_buf[st_nid_s..@intCast(usize, 19)]);
        var st_v: []const u8 = "\n";
        pal_mod.stderr_write(st_v);
        result = type_mod.TYPE_VOID;
    }

    if (result != type_mod.TYPE_VOID) {
        var a4_m: []const u8 = "A4:"; pal_mod.stderr_write(a4_m);
        var a4_nb: [20]u8 = undefined; var a4_nl = itoa_mod.itoa(node_idx, a4_nb[0..]); var a4_ns: usize = @intCast(usize, 19) - @intCast(usize, a4_nl); pal_mod.stderr_write(a4_nb[a4_ns..@intCast(usize, 19)]);
        var a4_km: []const u8 = "k"; pal_mod.stderr_write(a4_km);
        var a4_kb: [20]u8 = undefined; var a4_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(node.kind)), a4_kb[0..]); var a4_ks: usize = @intCast(usize, 19) - @intCast(usize, a4_kl); pal_mod.stderr_write(a4_kb[a4_ks..@intCast(usize, 19)]);
        var a4_rm: []const u8 = "r"; pal_mod.stderr_write(a4_rm);
        var a4_rb: [20]u8 = undefined; var a4_rl = itoa_mod.itoa(result, a4_rb[0..]); var a4_rs: usize = @intCast(usize, 19) - @intCast(usize, a4_rl); pal_mod.stderr_write(a4_rb[a4_rs..@intCast(usize, 19)]);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
    }
    return result;
}

pub fn semanticAnalyzerResolveFnBody(self: *SemanticAnalyzer, fn_decl_node: u32) void {
    var fb: []const u8 = "FB"; pal_mod.stderr_write(fb);
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
                var rtm: []const u8 = "A2:"; pal_mod.stderr_write(rtm);
                var rt_nb: [20]u8 = undefined; var rt_nl = itoa_mod.itoa(pnode.payload, rt_nb[0..]); var rt_ns: usize = @intCast(usize, 19) - @intCast(usize, rt_nl); pal_mod.stderr_write(rt_nb[rt_ns..@intCast(usize, 19)]);
                var rt_am: []const u8 = "a"; pal_mod.stderr_write(rt_am);
                var rt_ab: [20]u8 = undefined; var rt_al = itoa_mod.itoa(pnode.child_0, rt_ab[0..]); var rt_as: usize = @intCast(usize, 19) - @intCast(usize, rt_al); pal_mod.stderr_write(rt_ab[rt_as..@intCast(usize, 19)]);
                var rt = rtt_mod.resolvedTypeTableGet(self.type_table, pnode.child_0);
                if (rt) |t| {
                    var rth_m: []const u8 = "H"; pal_mod.stderr_write(rth_m);
                    var rth_b: [20]u8 = undefined; var rth_l = itoa_mod.itoa(t, rth_b[0..]); var rth_s: usize = @intCast(usize, 19) - @intCast(usize, rth_l); pal_mod.stderr_write(rth_b[rth_s..@intCast(usize, 19)]);
                    self.local_decl_types[self.local_decl_count] = t;
                } else {
                    var rtm_m: []const u8 = "M"; pal_mod.stderr_write(rtm_m);
                    self.local_decl_types[self.local_decl_count] = type_mod.TYPE_UNDEFINED;
                }
                self.local_decl_count += @intCast(usize, 1);
            }
        }
    }
    semanticAnalyzerResolveStmt(self, decl.child_0);
    var evcap = self.enum_value_table.capacity; var evcnt = self.enum_value_table.count;
    var evcap_buf: [20]u8 = undefined; var evcnt_buf: [20]u8 = undefined;
    var evcap_len = itoa_mod.itoa(@intCast(u32, evcap), evcap_buf[0..]);
    var evcnt_len = itoa_mod.itoa(@intCast(u32, evcnt), evcnt_buf[0..]);
    var evcap_s: usize = @intCast(usize, 19) - @intCast(usize, evcap_len);
    var evcnt_s: usize = @intCast(usize, 19) - @intCast(usize, evcnt_len);
    var vl: []const u8 = "vN="; pal_mod.stderr_write(vl);
    pal_mod.stderr_write(evcnt_buf[evcnt_s..@intCast(usize, 19)]);
    var vc: []const u8 = " vC="; pal_mod.stderr_write(vc);
    pal_mod.stderr_write(evcap_buf[evcap_s..@intCast(usize, 19)]);
    var vnl: []const u8 = "\n"; pal_mod.stderr_write(vnl);
}

pub fn semanticAnalyzerResolveStmtDepth(self: *SemanticAnalyzer, node_idx: u32, depth: u32) void {
    if (depth > @intCast(u32, 16)) return;
    if (node_idx == @intCast(u32, 0)) return;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.block) {
         var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
         var blkm: []const u8 = "BLK:ni="; pal_mod.stderr_write(blkm);
         var blkb: [20]u8 = undefined; var blkl = itoa_mod.itoa(node_idx, blkb[0..]); var blks: usize = @intCast(usize, 19) - @intCast(usize, blkl); pal_mod.stderr_write(blkb[blks..@intCast(usize, 19)]);
         var blkc: []const u8 = "c="; pal_mod.stderr_write(blkc);
         var blkcb: [10]u8 = undefined; var blkcl = itoa_mod.itoa(@intCast(u32, children.len), blkcb[0..]); var blkcs: usize = @intCast(usize, 9) - @intCast(usize, blkcl); pal_mod.stderr_write(blkcb[blkcs..@intCast(usize, 9)]);
         var blkk: []const u8 = "k=["; pal_mod.stderr_write(blkk);
         var i: usize = 0;
         while (i < children.len) : (i += 1) {
             if (i > @intCast(usize, 0)) { var bc: []const u8 = ","; pal_mod.stderr_write(bc); }
             var cnode = self.store.nodes.items[@intCast(usize, children[i])];
             var bkb: [10]u8 = undefined; var bkl = itoa_mod.itoa(@intCast(u32, @enumToInt(cnode.kind)), bkb[0..]); var bks: usize = @intCast(usize, 9) - @intCast(usize, bkl); pal_mod.stderr_write(bkb[bks..@intCast(usize, 9)]);
             semanticAnalyzerResolveStmtDepth(self, children[i], depth + @intCast(u32, 1));
         }
         var bcej: []const u8 = "]\n"; pal_mod.stderr_write(bcej);
     } else if (node.kind == AstKind.var_decl) {
        if (node.payload == @intCast(u32, 55)) {
            var d10m: []const u8 = "D10:V55c0="; pal_mod.stderr_write(d10m);
            var d10b0: [10]u8 = undefined; var d10l0 = itoa_mod.itoa(node.child_0, d10b0[0..]); var d10s0: usize = @intCast(usize, 9) - @intCast(usize, d10l0); pal_mod.stderr_write(d10b0[d10s0..@intCast(usize, 9)]);
            var d10c1: []const u8 = "c1="; pal_mod.stderr_write(d10c1);
            var d10b1: [10]u8 = undefined; var d10l1 = itoa_mod.itoa(node.child_1, d10b1[0..]); var d10s1: usize = @intCast(usize, 9) - @intCast(usize, d10l1); pal_mod.stderr_write(d10b1[d10s1..@intCast(usize, 9)]);
            if (node.child_1 != @intCast(u32, 0)) {
                var inode = self.store.nodes.items[@intCast(usize, node.child_1)];
                var d10ik: []const u8 = "ik="; pal_mod.stderr_write(d10ik);
                var d10ikb: [10]u8 = undefined; var d10ikl = itoa_mod.itoa(@intCast(u32, @enumToInt(inode.kind)), d10ikb[0..]); var d10iks: usize = @intCast(usize, 9) - @intCast(usize, d10ikl); pal_mod.stderr_write(d10ikb[d10iks..@intCast(usize, 9)]);
            }
            var d10nl: []const u8 = "\n"; pal_mod.stderr_write(d10nl);
        }
        var vd_m: []const u8 = "FB1:VDn"; pal_mod.stderr_write(vd_m);
        var vd_nb: [10]u8 = undefined; var vd_nl = itoa_mod.itoa(node.payload, vd_nb[0..]); var vd_ns: usize = @intCast(usize, 9) - @intCast(usize, vd_nl); pal_mod.stderr_write(vd_nb[vd_ns..@intCast(usize, 9)]);
        var vd_dd: []const u8 = "c"; pal_mod.stderr_write(vd_dd);
        var vd_cb: [10]u8 = undefined; var vd_cl = itoa_mod.itoa(@intCast(u32, self.local_decl_count), vd_cb[0..]); var vd_cs: usize = @intCast(usize, 9) - @intCast(usize, vd_cl); pal_mod.stderr_write(vd_cb[vd_cs..@intCast(usize, 9)]);
        var vd_sp: []const u8 = " "; pal_mod.stderr_write(vd_sp);
        var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (node.child_0 != @intCast(u32, 0)) {
            var vdt: []const u8 = "T"; pal_mod.stderr_write(vdt);    
            var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
            if (rt) |t| { decl_type = t; }
        }
        if (node.child_1 != @intCast(u32, 0)) {
            var vdi: []const u8 = "I"; pal_mod.stderr_write(vdi);
            var init_node = self.store.nodes.items[@intCast(usize, node.child_1)];
            var ik = @intCast(u32, @enumToInt(init_node.kind));
            var ib: [20]u8 = undefined;
            var il = itoa_mod.itoa(ik, ib[0..]);
            var is: usize = @intCast(usize, 20) - @intCast(usize, 1) - @intCast(usize, il);
            pal_mod.stderr_write(ib[is..@intCast(usize, 20)]);
            pal_mod.stderr_write(vdi);
            var it = semanticAnalyzerResolveExpr(self, node.child_1);
            if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED)) { decl_type = it; }
            rtt_mod.resolvedTypeTableSet(self.type_table, node.child_1, decl_type);
        }
        if (self.local_decl_count >= self.local_decl_cap) {
            semanticAnalyzerGrowLocalDecls(self);
        }
        self.local_decl_names[self.local_decl_count] = node.payload;
        self.local_decl_types[self.local_decl_count] = decl_type;
        self.local_decl_count += @intCast(usize, 1);
        var d4v: []const u8 = "D4:vn"; pal.stderr_write(d4v);
        var d4vb: [10]u8 = undefined; var d4vl = itoa_mod.itoa(node.payload, d4vb[0..]); var d4vs: usize = @intCast(usize, 9) - @intCast(usize, d4vl); pal.stderr_write(d4vb[d4vs..@intCast(usize, 9)]);
        var d4vt: []const u8 = "t"; pal.stderr_write(d4vt);
        var d4vtb: [10]u8 = undefined; var d4vtl = itoa_mod.itoa(decl_type, d4vtb[0..]); var d4vts: usize = @intCast(usize, 9) - @intCast(usize, d4vtl); pal.stderr_write(d4vtb[d4vts..@intCast(usize, 9)]);
        var d4vnl: []const u8 = " "; pal.stderr_write(d4vnl);
    } else if (node.kind == AstKind.if_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
        if (node.child_2 != @intCast(u32, 0)) {
            semanticAnalyzerResolveStmtDepth(self, node.child_2, depth + @intCast(u32, 1));
        }
     } else if (node.kind == AstKind.while_stmt) {
        var wsm: []const u8 = "WS:b1="; pal_mod.stderr_write(wsm);
        var wsb: [20]u8 = undefined; var wsl = itoa_mod.itoa(node.child_1, wsb[0..]); var wss: usize = @intCast(usize, 19) - @intCast(usize, wsl); pal_mod.stderr_write(wsb[wss..@intCast(usize, 19)]);
        var wsnl: []const u8 = " "; pal_mod.stderr_write(wsnl);
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.for_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        var fsm: []const u8 = "FS:"; pal.stderr_write(fsm);
        var fsc_b: [20]u8 = undefined; var fsc_l = itoa_mod.itoa(node.child_0, fsc_b[0..]); var fsc_s: usize = @intCast(usize, 19) - @intCast(usize, fsc_l); pal.stderr_write(fsc_b[fsc_s..@intCast(usize, 19)]);
        var fsk_m: []const u8 = "k"; pal.stderr_write(fsk_m);
        var cnode = self.store.nodes.items[@intCast(usize, node.child_0)];
        var fsk_b: [20]u8 = undefined; var fsk_l = itoa_mod.itoa(@intCast(u32, @enumToInt(cnode.kind)), fsk_b[0..]); var fsk_s: usize = @intCast(usize, 19) - @intCast(usize, fsk_l); pal.stderr_write(fsk_b[fsk_s..@intCast(usize, 19)]);
        var it_tid = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
        if (it_tid) |tid| {
            var a5_hm: []const u8 = "H"; pal.stderr_write(a5_hm);
            var a5_hb: [20]u8 = undefined; var a5_hl = itoa_mod.itoa(tid, a5_hb[0..]); var a5_hs: usize = @intCast(usize, 19) - @intCast(usize, a5_hl); pal.stderr_write(a5_hb[a5_hs..@intCast(usize, 19)]);
            var ty = self.registry.types_items[@intCast(usize, tid)];
            var elem_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
            if (ty.kind == type_mod.TypeKind.slice_type) {
                elem_box[0] = self.registry.slice_items[@intCast(usize, ty.payload_idx)].elem;
            } else if (ty.kind == type_mod.TypeKind.array_type) {
                elem_box[0] = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem;
            }
            if (node.payload != @intCast(u32, 0) and elem_box[0] != type_mod.TYPE_UNDEFINED) {
                var fsm1: []const u8 = "FSRp"; pal.stderr_write(fsm1);
                var fsm1b: [10]u8 = undefined; var fsm1l = itoa_mod.itoa(node.payload, fsm1b[0..]); var fsm1s: usize = @intCast(usize, 9) - @intCast(usize, fsm1l); pal.stderr_write(fsm1b[fsm1s..@intCast(usize, 9)]);
                var fsm1et: []const u8 = "e"; pal.stderr_write(fsm1et);
                var fsm1eb: [10]u8 = undefined; var fsm1el = itoa_mod.itoa(elem_box[0], fsm1eb[0..]); var fsm1es: usize = @intCast(usize, 9) - @intCast(usize, fsm1el); pal.stderr_write(fsm1eb[fsm1es..@intCast(usize, 9)]);
                var fsm1sp: []const u8 = " "; pal.stderr_write(fsm1sp);
                if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
                self.local_decl_names[self.local_decl_count] = node.payload; self.local_decl_types[self.local_decl_count] = elem_box[0]; self.local_decl_count += @intCast(usize, 1);
                var d4f: []const u8 = "D4:fn"; pal.stderr_write(d4f);
                var d4fb: [10]u8 = undefined; var d4fl = itoa_mod.itoa(node.payload, d4fb[0..]); var d4fs: usize = @intCast(usize, 9) - @intCast(usize, d4fl); pal.stderr_write(d4fb[d4fs..@intCast(usize, 9)]);
                var d4ft: []const u8 = "t"; pal.stderr_write(d4ft);
                var d4ftb: [10]u8 = undefined; var d4ftl = itoa_mod.itoa(elem_box[0], d4ftb[0..]); var d4fts: usize = @intCast(usize, 9) - @intCast(usize, d4ftl); pal.stderr_write(d4ftb[d4fts..@intCast(usize, 9)]);
                var d4fnl: []const u8 = " "; pal.stderr_write(d4fnl);
            }
        } else {
            var a5_mm: []const u8 = "M"; pal_mod.stderr_write(a5_mm);
        }
        if (node.child_2 != @intCast(u32, 0)) {
            if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
            self.local_decl_names[self.local_decl_count] = node.child_2; self.local_decl_types[self.local_decl_count] = type_mod.TYPE_USIZE; self.local_decl_count += @intCast(usize, 1);
            var f2m: []const u8 = "FIX2:ln"; pal_mod.stderr_write(f2m);
            var f2mb: [10]u8 = undefined; var f2ml = itoa_mod.itoa(node.child_2, f2mb[0..]); var f2ms: usize = @intCast(usize, 9) - @intCast(usize, f2ml); pal_mod.stderr_write(f2mb[f2ms..@intCast(usize, 9)]);
            var f2sp: []const u8 = " "; pal_mod.stderr_write(f2sp);
        }
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.switch_expr) {
        var sw: []const u8 = "SW"; pal_mod.stderr_write(sw);
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

fn semanticAnalyzerResolveIndexAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    _ = semanticAnalyzerResolveExpr(self, node.child_1);
    self._stub_0 = semanticAnalyzerResolveExpr(self, node.child_0);
    var ix_m: []const u8 = "IX:"; pal_mod.stderr_write(ix_m);
    var ix_bb: [20]u8 = undefined; var ix_bl = itoa_mod.itoa(self._stub_0, ix_bb[0..]); var ix_bs: usize = @intCast(usize, 19) - @intCast(usize, ix_bl); pal_mod.stderr_write(ix_bb[ix_bs..@intCast(usize, 19)]);
    if (self._stub_0 == @intCast(u32, 0) or self._stub_0 == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var bt = self.registry.types_items[@intCast(usize, self._stub_0)];
    if (bt.kind == type_mod.TypeKind.array_type) {
        var r1 = self.registry.array_items[@intCast(usize, bt.payload_idx)].elem;
        var ix_r: []const u8 = "r"; pal_mod.stderr_write(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r1, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.stderr_write(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r1;
    } else if (bt.kind == type_mod.TypeKind.slice_type) {
        var r2 = self.registry.slice_items[@intCast(usize, bt.payload_idx)].elem;
        var ix_r: []const u8 = "r"; pal_mod.stderr_write(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r2, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.stderr_write(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r2;
    } else if (bt.kind == type_mod.TypeKind.ptr_type or bt.kind == type_mod.TypeKind.many_ptr_type) {
        var r3 = self.registry.ptr_items[@intCast(usize, bt.payload_idx)].base;
        var ix_r: []const u8 = "r"; pal_mod.stderr_write(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r3, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.stderr_write(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r3;
    } else if (bt.kind == type_mod.TypeKind.tuple_type) {
        var tp = self.registry.tup_items[@intCast(usize, bt.payload_idx)];
        var r4 = self.registry.xt_items[@intCast(usize, tp.elems_start)];
        var ix_r: []const u8 = "r"; pal_mod.stderr_write(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r4, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.stderr_write(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r4;
    }
    var ix_d: []const u8 = "d"; pal_mod.stderr_write(ix_d);
    return self._stub_0;
}

fn semanticAnalyzerResolveSliceExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    self._stub_0 = semanticAnalyzerResolveExpr(self, node.child_0);
    if (self._stub_0 == @intCast(u32, 0) or self._stub_0 == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var bt = self.registry.types_items[@intCast(usize, self._stub_0)];
    self._stub_1 = type_mod.TYPE_VOID;
    if (bt.kind == type_mod.TypeKind.array_type) {
        self._stub_1 = self.registry.array_items[@intCast(usize, bt.payload_idx)].elem;
    } else if (bt.kind == type_mod.TypeKind.slice_type) {
        self._stub_1 = self.registry.slice_items[@intCast(usize, bt.payload_idx)].elem;
    } else if (bt.kind == type_mod.TypeKind.ptr_type or bt.kind == type_mod.TypeKind.many_ptr_type) {
        self._stub_1 = self.registry.ptr_items[@intCast(usize, bt.payload_idx)].base;
    } else {
        self._stub_1 = self._stub_0;
    }
    if (self._stub_1 == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    return type_mod.typeRegistryGetOrCreateSlice(self.registry, self._stub_1, false);
}

fn semanticAnalyzerResolveTupleLiteral(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len == @intCast(usize, 0)) return type_mod.TYPE_VOID;
    var start: u16 = @intCast(u16, self.registry.xt_len);
    var i: usize = 0;
    while (i < ec.len) : (i += @intCast(usize, 1)) {
        self._stub_0 = semanticAnalyzerResolveExpr(self, ec[i]);
        if (self._stub_0 == type_mod.TYPE_VOID) { self._stub_0 = type_mod.TYPE_I32; }
        type_mod.xtAppend(self.registry, self._stub_0);
    }
    return type_mod.typeRegistryGetOrCreateTuple(self.registry, start, @intCast(u16, ec.len));
}

fn semanticAnalyzerResolveArrayInit(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.child_0 != @intCast(u32, 0)) {
        var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
        if (rt) |t| {
            var tt = self.registry.types_items[@intCast(usize, t)];
            if (tt.kind == type_mod.TypeKind.array_type) return t;
        }
    }
    var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len == @intCast(usize, 0)) return type_mod.TYPE_VOID;
    var el = self.store.nodes.items[@intCast(usize, ec[@intCast(usize, 0)])];
    self._stub_0 = type_mod.TYPE_VOID;
    if (el.kind == AstKind.char_literal) { self._stub_0 = type_mod.TYPE_U8; }
    else if (el.kind == AstKind.int_literal) { self._stub_0 = type_mod.TYPE_U32; }
    else { self._stub_0 = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]); }
    if (self._stub_0 == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var arr_tid = type_mod.typeRegistryGetOrCreateArray(self.registry, self._stub_0, @intCast(u32, ec.len));
    return arr_tid;
}

pub fn semanticAnalyzerResolveStmt(self: *SemanticAnalyzer, node_idx: u32) void {
    semanticAnalyzerResolveStmtDepth(self, node_idx, @intCast(u32, 0));
}
