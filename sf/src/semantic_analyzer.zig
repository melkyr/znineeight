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
    call_param_map: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
};

pub fn semanticAnalyzerInit(alloc: *Sand, type_table: *ResolvedTypeTable, diag: *DiagnosticCollector, registry: *TypeRegistry, symbols: *SymbolRegistry, store: *AstStore, module_id: u32, coercion_tab: *coercion_mod.CoercionTable, enum_val_tab: *hash_mod.U32ToU32Map, interner: *interner_mod.StringInterner, cal_typs: *hash_mod.U32ToU32Map, cp_map: *hash_mod.U32ToU32Map) SemanticAnalyzer {
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
        .call_param_map = cp_map,
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
    var ide: []const u8 = "IDE"; pal_mod.markerWrite(ide);
    var li = self.local_decl_count;
    while (li > @intCast(usize, 0)) {
        li -= @intCast(usize, 1);
            if (self.local_decl_names[li] == name_id) {
                var lcl_t = self.local_decl_types[li];
                var d7m: []const u8 = "D7:Yn"; pal_mod.markerWrite(d7m);
                var d7nb: [10]u8 = undefined; var d7nl = itoa_mod.itoa(name_id, d7nb[0..]); var d7ns: usize = @intCast(usize, 9) - @intCast(usize, d7nl); pal_mod.markerWrite(d7nb[d7ns..@intCast(usize, 9)]);
                var d7tm: []const u8 = "t"; pal_mod.markerWrite(d7tm);
                var d7tb: [10]u8 = undefined; var d7tl = itoa_mod.itoa(lcl_t, d7tb[0..]); var d7ts: usize = @intCast(usize, 9) - @intCast(usize, d7tl); pal_mod.markerWrite(d7tb[d7ts..@intCast(usize, 9)]);
                var d7sp: []const u8 = " "; pal_mod.markerWrite(d7sp);
                var ri: []const u8 = "R"; pal_mod.markerWrite(ri);
            var id1: []const u8 = "L"; pal_mod.markerWrite(id1);
            var lcl_b: [20]u8 = undefined; var lcl_l = itoa_mod.itoa(lcl_t, lcl_b[0..]); var lcl_s: usize = @intCast(usize, 19) - @intCast(usize, lcl_l); pal_mod.markerWrite(lcl_b[lcl_s..@intCast(usize, 19)]);
            return lcl_t;
        }
    }
    var key = @intCast(u64, name_id);
    var ncg = type_mod.nameCacheGet(self.registry, key);
    var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, name_id);
    if (sym) |s| {
        var id2: []const u8 = "S"; pal_mod.markerWrite(id2);
        if (s.kind == sym_mod.SymbolKind.type_alias) { var rdt_talias: []const u8 = "TAL"; pal_mod.markerWrite(rdt_talias); return s.type_id; }
        if (s.type_id != @intCast(u32, 0)) { var rdt_st: []const u8 = "STY:"; pal_mod.markerWrite(rdt_st); var rdt_cname = interner_mod.stringInternerGet(self.interner, name_id); pal.markerWrite(rdt_cname); var rdt_cm: []const u8 = ":"; pal.markerWrite(rdt_cm); var rdt_nb: [10]u8 = undefined; var rdt_nl = itoa_mod.itoa(name_id, rdt_nb[0..]); var rdt_ns: usize = @intCast(usize, 9) - @intCast(usize, rdt_nl); pal_mod.markerWrite(rdt_nb[rdt_ns..@intCast(usize, 9)]); var rdt_tm: []const u8 = "t"; pal_mod.markerWrite(rdt_tm); var rdt_tb: [10]u8 = undefined; var rdt_tl = itoa_mod.itoa(s.type_id, rdt_tb[0..]); var rdt_ts: usize = @intCast(usize, 9) - @intCast(usize, rdt_tl); pal.markerWrite(rdt_tb[rdt_ts..@intCast(usize, 9)]); var rdt_nm: []const u8 = "N"; pal.markerWrite(rdt_nm); if (ncg) |nt| { var rdt_ntb: [10]u8 = undefined; var rdt_ntl = itoa_mod.itoa(nt, rdt_ntb[0..]); var rdt_nts: usize = @intCast(usize, 9) - @intCast(usize, rdt_ntl); pal.markerWrite(rdt_ntb[rdt_nts..@intCast(usize, 9)]); } return s.type_id; }
        var rdt_sv: []const u8 = "SVO"; pal.markerWrite(rdt_sv); return type_mod.TYPE_VOID;
    }
    if (ncg) |t| { var id3: []const u8 = "C2:"; pal_mod.markerWrite(id3); var c2name = interner_mod.stringInternerGet(self.interner, name_id); pal_mod.markerWrite(c2name); var id3n: []const u8 = "\n"; pal_mod.markerWrite(id3n); return t; }
     var id4: []const u8 = "D8:Nn"; pal_mod.markerWrite(id4);
     var d8nb: [10]u8 = undefined; var d8nl = itoa_mod.itoa(name_id, d8nb[0..]); var d8ns: usize = @intCast(usize, 9) - @intCast(usize, d8nl); pal_mod.markerWrite(d8nb[d8ns..@intCast(usize, 9)]);
     var d8cm: []const u8 = "c"; pal_mod.markerWrite(d8cm);
     var d8cb: [10]u8 = undefined; var d8cl = itoa_mod.itoa(@intCast(u32, self.local_decl_count), d8cb[0..]); var d8cs: usize = @intCast(usize, 9) - @intCast(usize, d8cl); pal_mod.markerWrite(d8cb[d8cs..@intCast(usize, 9)]);
     if (self.local_decl_count > @intCast(usize, 0)) {
         var d8fm: []const u8 = "f"; pal_mod.markerWrite(d8fm);
         var d8fb: [10]u8 = undefined; var d8fl = itoa_mod.itoa(self.local_decl_names[@intCast(usize, 0)], d8fb[0..]); var d8fs: usize = @intCast(usize, 9) - @intCast(usize, d8fl); pal_mod.markerWrite(d8fb[d8fs..@intCast(usize, 9)]);
         var d8lm: []const u8 = "l"; pal_mod.markerWrite(d8lm);
         var d8lb: [10]u8 = undefined; var d8ll = itoa_mod.itoa(self.local_decl_names[self.local_decl_count - @intCast(usize, 1)], d8lb[0..]); var d8ls: usize = @intCast(usize, 9) - @intCast(usize, d8ll); pal_mod.markerWrite(d8lb[d8ls..@intCast(usize, 9)]);
     }
     if (self.local_decl_count > @intCast(usize, 4)) {
         var d8x: []const u8 = "x"; pal_mod.markerWrite(d8x);
         var d8x5: [10]u8 = undefined; var d8x5l = itoa_mod.itoa(self.local_decl_names[@intCast(usize, 4)], d8x5[0..]); var d8x5s: usize = @intCast(usize, 9) - @intCast(usize, d8x5l); pal_mod.markerWrite(d8x5[d8x5s..@intCast(usize, 9)]);
     }
     var d8sp: []const u8 = "i"; pal_mod.markerWrite(d8sp);
     var d8ib: [10]u8 = undefined; var d8il = itoa_mod.itoa(node_idx, d8ib[0..]); var d8is: usize = @intCast(usize, 9) - @intCast(usize, d8il); pal_mod.markerWrite(d8ib[d8is..@intCast(usize, 9)]);
      var d8nll: []const u8 = " "; pal_mod.markerWrite(d8nll);
       if (node_idx == @intCast(u32, 436) or name_id == @intCast(u32, 55)) {
           var cname = interner_mod.stringInternerGet(self.interner, name_id);
           pal_mod.markerWrite(cname);
           var d8kn: []const u8 = " k="; pal_mod.markerWrite(d8kn);
          var cnode = self.store.nodes.items[@intCast(usize, node_idx)];
          var d8kb: [10]u8 = undefined; var d8kl = itoa_mod.itoa(@intCast(u32, @enumToInt(cnode.kind)), d8kb[0..]); var d8ks: usize = @intCast(usize, 9) - @intCast(usize, d8kl); pal_mod.markerWrite(d8kb[d8ks..@intCast(usize, 9)]);
          var d8rt: []const u8 = "r"; pal_mod.markerWrite(d8rt);
          var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node_idx);
          if (rt) |t| { var d8tb: [10]u8 = undefined; var d8tl = itoa_mod.itoa(t, d8tb[0..]); var d8ts: usize = @intCast(usize, 9) - @intCast(usize, d8tl); pal_mod.markerWrite(d8tb[d8ts..@intCast(usize, 9)]); }
          else { var d8z: []const u8 = "Z"; pal_mod.markerWrite(d8z); }
          var d8nl2: []const u8 = "\n"; pal_mod.markerWrite(d8nl2);
      }
    if (name_id == self._stub_0) {
        return type_mod.TYPE_UNDEFINED;
    }
    return type_mod.TYPE_VOID;
}

pub fn semanticAnalyzerResolveFieldAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var fae: []const u8 = "FAE"; pal_mod.markerWrite(fae);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var base_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var field_name_id = node.payload;
    var pfa_bk: [20]u8 = undefined; var pfa_bkl = itoa_mod.itoa(@intCast(u32, @enumToInt(base_node.kind)), pfa_bk[0..]); var pfa_bks: usize = @intCast(usize, 19) - @intCast(usize, pfa_bkl); var pfa_bm: []const u8 = "BK"; pal_mod.markerWrite(pfa_bm); pal_mod.markerWrite(pfa_bk[pfa_bks..@intCast(usize, 19)]);
    var pfa_fn: [20]u8 = undefined; var pfa_fnl = itoa_mod.itoa(field_name_id, pfa_fn[0..]); var pfa_fns: usize = @intCast(usize, 19) - @intCast(usize, pfa_fnl); var pfa_fm: []const u8 = "FN"; pal_mod.markerWrite(pfa_fm); pal_mod.markerWrite(pfa_fn[pfa_fns..@intCast(usize, 19)]);

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
                    var q1m: []const u8 = "Q1:fl="; pal_mod.markerWrite(q1m);
                    var q1fb: [10]u8 = undefined; var q1fl = itoa_mod.itoa(@intCast(u32, fs.flags), q1fb[0..]); var q1fs: usize = @intCast(usize, 9) - @intCast(usize, q1fl); pal_mod.markerWrite(q1fb[q1fs..@intCast(usize, 9)]);
                    var q1km: []const u8 = ",ki="; pal_mod.markerWrite(q1km);
                    var q1kb: [10]u8 = undefined; var q1kl = itoa_mod.itoa(@intCast(u32, @enumToInt(fs.kind)), q1kb[0..]); var q1ks: usize = @intCast(usize, 9) - @intCast(usize, q1kl); pal_mod.markerWrite(q1kb[q1ks..@intCast(usize, 9)]);
                    var q1tm: []const u8 = ",ti="; pal_mod.markerWrite(q1tm);
                    var q1tb: [10]u8 = undefined; var q1tl = itoa_mod.itoa(fs.type_id, q1tb[0..]); var q1ts: usize = @intCast(usize, 9) - @intCast(usize, q1tl); pal_mod.markerWrite(q1tb[q1ts..@intCast(usize, 9)]);
                    var q1nm: []const u8 = ",fn="; pal_mod.markerWrite(q1nm);
                    var q1nb: [10]u8 = undefined; var q1nbl = itoa_mod.itoa(field_name_id, q1nb[0..]); var q1nbs: usize = @intCast(usize, 9) - @intCast(usize, q1nbl); pal_mod.markerWrite(q1nb[q1nbs..@intCast(usize, 9)]);
                    var q1x: []const u8 = "\n"; pal_mod.markerWrite(q1x);
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
                    if (fs.kind == sym_mod.SymbolKind.function and fs.decl_node != @intCast(u32, 0)) {
                        var q1fx: []const u8 = "Q1FX:"; pal_mod.markerWrite(q1fx);
                        var fn_dn = self.store.nodes.items[@intCast(usize, fs.decl_node)];
                        if (fn_dn.kind == AstKind.fn_decl) {
                            var proto = self.store.fn_protos.items[@intCast(usize, fn_dn.payload)];
                            if (proto.return_type_node != @intCast(u32, 0)) {
                                var rtt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                                if (rtt) |rtv| {
                                    var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, fs.module_id, @intCast(u8, 0), proto.params_start, proto.params_count, rtv);
                                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                                    return fn_ty;
                                }
                            }
                            var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, fs.module_id, @intCast(u8, 0), proto.params_start, proto.params_count, type_mod.TYPE_VOID);
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                            return fn_ty;
                        }
                    }
                }
                var q1vf: []const u8 = "Q1VF:fn"; pal_mod.markerWrite(q1vf);
                var q1vfb: [10]u8 = undefined; var q1vfl = itoa_mod.itoa(field_name_id, q1vfb[0..]); var q1vfs: usize = @intCast(usize, 9) - @intCast(usize, q1vfl); pal_mod.markerWrite(q1vfb[q1vfs..@intCast(usize, 9)]);
                var q1vfnl: []const u8 = "\n"; pal_mod.markerWrite(q1vfnl);
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
                return type_mod.TYPE_VOID;
            }
        }
    }

    var base_type_id = semanticAnalyzerResolveExpr(self, node.child_0);
    if (base_type_id == type_mod.TYPE_VOID) {
        var fa1: []const u8 = "FB"; pal_mod.markerWrite(fa1);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }
    var base_ty = self.registry.types_items[@intCast(usize, base_type_id)];

    var fields_start: usize = 0;
    var fields_count: usize = 0;
    if (base_ty.kind == type_mod.TypeKind.ptr_type or base_ty.kind == type_mod.TypeKind.many_ptr_type) {
        var pre_kind = base_ty.kind;
        base_type_id = self.registry.ptr_items[@intCast(usize, base_ty.payload_idx)].base;
        base_ty = self.registry.types_items[@intCast(usize, base_type_id)];
        var fapr_m: []const u8 = "FAPR:ok"; pal_mod.markerWrite(fapr_m);
        var fapr_ob: [10]u8 = undefined; var fapr_ol = itoa_mod.itoa(@intCast(u32, @enumToInt(pre_kind)), fapr_ob[0..]); var fapr_os: usize = @intCast(usize, 9) - @intCast(usize, fapr_ol); pal_mod.markerWrite(fapr_ob[fapr_os..@intCast(usize, 9)]);
        var fapr_dm: []const u8 = "dk"; pal_mod.markerWrite(fapr_dm);
        var fapr_db: [10]u8 = undefined; var fapr_dl = itoa_mod.itoa(@intCast(u32, @enumToInt(base_ty.kind)), fapr_db[0..]); var fapr_ds: usize = @intCast(usize, 9) - @intCast(usize, fapr_dl); pal_mod.markerWrite(fapr_db[fapr_ds..@intCast(usize, 9)]);
        var fapr_nl: []const u8 = "\n"; pal_mod.markerWrite(fapr_nl);
    }
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
        var mfa: []const u8 = "MFA"; pal_mod.markerWrite(mfa);
        var mod_field_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, base_ty.module_id, field_name_id);
        if (mod_field_sym) |mfs| {
            if (mfs.type_id != @intCast(u32, 0)) {
                var mf1: []const u8 = "MF1"; pal_mod.markerWrite(mf1);
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, mfs.type_id);
                return mfs.type_id;
            }
            if (mfs.kind == sym_mod.SymbolKind.function) {
                var fn_tid_opt = rtt_mod.resolvedTypeTableGet(self.type_table, mfs.decl_node);
                if (fn_tid_opt) |fn_tid| {
                    var mf1: []const u8 = "MF1"; pal_mod.markerWrite(mf1);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_tid);
                    return fn_tid;
                }
                var mff: []const u8 = "MFF"; pal_mod.markerWrite(mff);
                var dn = self.store.nodes.items[@intCast(usize, mfs.decl_node)];
                if (dn.kind == AstKind.fn_decl) {
                    var proto = self.store.fn_protos.items[@intCast(usize, dn.payload)];
                    var mfp_buf: [20]u8 = undefined; var mfp_len = itoa_mod.itoa(@intCast(u32, proto.params_start), mfp_buf[0..]); var mfp_s: usize = @intCast(usize, 19) - @intCast(usize, mfp_len); var mfp_m: []const u8 = "MFP"; pal_mod.markerWrite(mfp_m); pal_mod.markerWrite(mfp_buf[mfp_s..@intCast(usize, 19)]);
                    if (proto.return_type_node != @intCast(u32, 0)) {
                        var rtt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                        if (rtt) |rtv| {
                             var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, mfs.module_id, @intCast(u8, 0), proto.params_start, proto.params_count, rtv);
                             rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                              return fn_ty;
                }
            }
                     var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, mfs.module_id, @intCast(u8, 0), proto.params_start, proto.params_count, type_mod.TYPE_VOID);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                    return fn_ty;
                }
            }
            var mf2: []const u8 = "MF2"; pal_mod.markerWrite(mf2);
            var mf2_k: [20]u8 = undefined; var mf2_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(mfs.kind)), mf2_k[0..]); var mf2_ks: usize = @intCast(usize, 19) - @intCast(usize, mf2_kl); pal_mod.markerWrite(mf2_k[mf2_ks..@intCast(usize, 19)]);
        } else {
            var mf3: []const u8 = "MF3"; pal_mod.markerWrite(mf3);
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    } else if (base_ty.kind == type_mod.TypeKind.slice_type) {
        var sp = self.registry.slice_items[@intCast(usize, base_ty.payload_idx)];
        var len_s: []const u8 = "len";
        var len_id = interner_mod.stringInternerIntern(self.interner, len_s);
        if (field_name_id == len_id) {
            var fsl: []const u8 = "FSL:USIZE\n"; pal_mod.markerWrite(fsl);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_USIZE);
            return type_mod.TYPE_USIZE;
        }
        var ptr_s: []const u8 = "ptr";
        var ptr_id = interner_mod.stringInternerIntern(self.interner, ptr_s);
        if (field_name_id == ptr_id) {
            var pty = type_mod.typeRegistryGetOrCreatePtr(self.registry, sp.elem, false);
            var fsp: []const u8 = "FSP:PTR\n"; pal_mod.markerWrite(fsp);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, pty);
            return pty;
        }
    } else {
        var fnf: []const u8 = "FF"; pal_mod.markerWrite(fnf);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }

    var fi: usize = 0;
    while (fi < fields_count) {
        var fe = self.registry.fe_items[fields_start + fi];
        if (fe.name_id == field_name_id) {
            var result = fe.type_id;
            if (base_ty.kind == type_mod.TypeKind.tagged_union_type) { result = base_type_id; }
            var ff: []const u8 = "FF:"; pal_mod.markerWrite(ff);
            var ff_b: [20]u8 = undefined; var ff_l = itoa_mod.itoa(result, ff_b[0..]); var ff_s: usize = @intCast(usize, 19) - @intCast(usize, ff_l); pal_mod.markerWrite(ff_b[ff_s..@intCast(usize, 19)]);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
            return result;
        }
        fi += 1;
    }

    var fnf2: []const u8 = "NF"; pal_mod.markerWrite(fnf2);
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
    var cpe: []const u8 = "CPE"; pal_mod.markerWrite(cpe);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) { var cp0: []const u8 = "CP0"; pal_mod.markerWrite(cp0); return type_mod.TYPE_VOID; }
    if (lhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, rhs)) { var cp1: []const u8 = "CPB"; pal_mod.markerWrite(cp1); return type_mod.TYPE_BOOL; }
    if (rhs == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, lhs)) { var cp2: []const u8 = "CPB"; pal_mod.markerWrite(cp2); return type_mod.TYPE_BOOL; }
    var lhs_num = type_mod.typeRegistryIsNumeric(self.registry, lhs);
    if (lhs_num and lhs == rhs) { var cp3: []const u8 = "CPB"; pal_mod.markerWrite(cp3); return type_mod.TYPE_BOOL; }
    if (op_kind == AstKind.cmp_eq or op_kind == AstKind.cmp_ne) {
        if (type_mod.typeRegistryIsOptional(self.registry, lhs) and rhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsOptional(self.registry, rhs) and lhs == type_mod.TYPE_NULL) return type_mod.TYPE_BOOL;
        if (type_mod.typeRegistryIsErrorSet(self.registry, lhs) and type_mod.typeRegistryIsErrorSet(self.registry, rhs)) { var cp4: []const u8 = "CPB"; pal_mod.markerWrite(cp4); return type_mod.TYPE_BOOL; }
    }
    var cpv: []const u8 = "CPV"; pal_mod.markerWrite(cpv);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveLogical(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var loe: []const u8 = "LOE"; pal_mod.markerWrite(loe);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == type_mod.TYPE_BOOL and rhs == type_mod.TYPE_BOOL) { var lo1: []const u8 = "LOB"; pal_mod.markerWrite(lo1); return type_mod.TYPE_BOOL; }
    var lo2: []const u8 = "LOV"; pal_mod.markerWrite(lo2);
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

fn tryRecordCoercion(self: *SemanticAnalyzer, src_node: u32, src_type: u32, dst_type: u32) void {
    var coe_m: []const u8 = "COE:n"; pal_mod.markerWrite(coe_m);
    var coe_nb: [10]u8 = undefined; var coe_nl2 = itoa_mod.itoa(src_node, coe_nb[0..]); var coe_ns: usize = @intCast(usize, 9) - @intCast(usize, coe_nl2); pal_mod.markerWrite(coe_nb[coe_ns..@intCast(usize, 9)]);
    var coe_sm: []const u8 = "s"; pal_mod.markerWrite(coe_sm);
    var coe_sb: [10]u8 = undefined; var coe_sl = itoa_mod.itoa(src_type, coe_sb[0..]); var coe_ss: usize = @intCast(usize, 9) - @intCast(usize, coe_sl); pal_mod.markerWrite(coe_sb[coe_ss..@intCast(usize, 9)]);
    var coe_tm: []const u8 = "d"; pal_mod.markerWrite(coe_tm);
    var coe_tb: [10]u8 = undefined; var coe_tl = itoa_mod.itoa(dst_type, coe_tb[0..]); var coe_ts: usize = @intCast(usize, 9) - @intCast(usize, coe_tl); pal_mod.markerWrite(coe_tb[coe_ts..@intCast(usize, 9)]);
    var coe_nl: []const u8 = "\n"; pal_mod.markerWrite(coe_nl);
    if (src_type == type_mod.TYPE_UNDEFINED or src_type == dst_type) return;
    if (!type_mod.typeRegistryIsAssignable(self.registry, src_type, dst_type)) return;
    var ck = coercion_mod.classifyCoercion(self.registry, src_type, dst_type);
    if (ck != coercion_mod.CoercionKind.none) {
        coercion_mod.coercionTableAdd(self.coercion_table, src_node, ck, dst_type);
        var cor_m: []const u8 = "COR:n"; pal_mod.markerWrite(cor_m); var cor_nb: [10]u8 = undefined; var cor_nl = itoa_mod.itoa(src_node, cor_nb[0..]); var cor_ns: usize = @intCast(usize, 9) - @intCast(usize, cor_nl); pal_mod.markerWrite(cor_nb[cor_ns..@intCast(usize, 9)]); var cor_km: []const u8 = "k"; pal_mod.markerWrite(cor_km); var cor_kb: [10]u8 = undefined; var cor_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(ck)), cor_kb[0..]); var cor_ks: usize = @intCast(usize, 9) - @intCast(usize, cor_kl); pal_mod.markerWrite(cor_kb[cor_ks..@intCast(usize, 9)]); var cor_nl2: []const u8 = "\n"; pal_mod.markerWrite(cor_nl2);
    }
}

fn semanticAnalyzerResolveFnCall(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var fne: []const u8 = "FNE"; pal_mod.markerWrite(fne);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var callee_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var direct_ret: u32 = @intCast(u32, 0);
    var cpp_val_fnx: u32 = @intCast(u32, 0);
    var decl_cap: u32 = 0;
    if (callee_node.kind == AstKind.ident_expr) {
        var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, self.store.identifiers.items[@intCast(usize, callee_node.payload)]);
        if (sym) |s| { var xf: []const u8 = "XF"; pal_mod.markerWrite(xf);
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
        } else { var xs: []const u8 = "xS"; pal_mod.markerWrite(xs); }
    }
    if (direct_ret != @intCast(u32, 0)) {
        var fn1: []const u8 = "FN1"; pal_mod.markerWrite(fn1);
        var fn1_rb: [20]u8 = undefined; var fn1_rl = itoa_mod.itoa(direct_ret, fn1_rb[0..]); var fn1_rs: usize = @intCast(usize, 19) - @intCast(usize, fn1_rl); var fn1_rm: []const u8 = "R"; pal_mod.markerWrite(fn1_rm); pal_mod.markerWrite(fn1_rb[fn1_rs..@intCast(usize, 19)]);
        var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        if (decl_cap != 0) {
            var ft = rtt_mod.resolvedTypeTableGet(self.type_table, decl_cap);
            if (ft) |ftid| { var sfm: []const u8 = "SF:H\n"; pal.markerWrite(sfm);
            var ft_ty = self.registry.types_items[@intCast(usize, ftid)];
            if (ft_ty.kind == type_mod.TypeKind.fn_type) {
                var ftp = self.registry.fn_items[@intCast(usize, ft_ty.payload_idx)];
                var ai2: usize = 0;
                while (ai2 < args.len and ai2 < @intCast(usize, ftp.params_count)) : (ai2 += 1) {
                    var cpp_key = (@intCast(u32, decl_cap) << @intCast(u32, 16)) | @intCast(u32, ai2);
                    cpp_val_fnx = type_mod.TYPE_UNDEFINED;
                    if (hash_mod.u32ToU32MapGet(self.call_param_map, cpp_key)) |cpp_v| { cpp_val_fnx = cpp_v; } else { cpp_val_fnx = self.registry.xt_items[@intCast(usize, ftp.params_start) + ai2]; }
                    hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai2], cpp_val_fnx);
                    var dxc_at = semanticAnalyzerResolveExpr(self, args[ai2]);
                    tryRecordCoercion(self, args[ai2], dxc_at, cpp_val_fnx);
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
    if (callee_type == @intCast(u32, 0)) { var fn2: []const u8 = "FN2"; pal_mod.markerWrite(fn2); return type_mod.TYPE_VOID; }
    var callee_ty = self.registry.types_items[@intCast(usize, callee_type)];
    if (callee_ty.kind != type_mod.TypeKind.fn_type) {
        var fn3: []const u8 = "FN3:"; pal_mod.markerWrite(fn3);
        var fn3_nid_buf: [20]u8 = undefined; var fn3_nid_len = itoa_mod.itoa(node_idx, fn3_nid_buf[0..]); var fn3_nid_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_nid_len); pal_mod.markerWrite(fn3_nid_buf[fn3_nid_s..@intCast(usize, 19)]);
        var fn3_ct_buf: [20]u8 = undefined; var fn3_ct_len = itoa_mod.itoa(callee_type, fn3_ct_buf[0..]); var fn3_ct_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_ct_len); var fn3_ct_m: []const u8 = "c"; pal_mod.markerWrite(fn3_ct_m); pal_mod.markerWrite(fn3_ct_buf[fn3_ct_s..@intCast(usize, 19)]);
        var fn3_ck_buf: [20]u8 = undefined; var fn3_ck_len = itoa_mod.itoa(@intCast(u32, @enumToInt(callee_ty.kind)), fn3_ck_buf[0..]); var fn3_ck_s: usize = @intCast(usize, 19) - @intCast(usize, fn3_ck_len); var fn3_ck_m: []const u8 = "k"; pal_mod.markerWrite(fn3_ck_m); pal_mod.markerWrite(fn3_ck_buf[fn3_ck_s..@intCast(usize, 19)]);
        return type_mod.TYPE_VOID;
    }
    var fn4a: []const u8 = "FN4a"; pal_mod.markerWrite(fn4a);
    var fnp = self.registry.fn_items[@intCast(usize, callee_ty.payload_idx)];
    var fn4b: []const u8 = "FN4b"; pal_mod.markerWrite(fn4b);
    var pcount: usize = @intCast(usize, fnp.params_count);
    var pstart: usize = @intCast(usize, fnp.params_start);
    var fn4c: []const u8 = "FN4c"; pal_mod.markerWrite(fn4c);
    var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    var fn4d: []const u8 = "FN4d"; pal_mod.markerWrite(fn4d);
    if (args.len != pcount) {
        return fnp.return_type;
    }
    var ai: usize = 0;
    var fn4e: []const u8 = "FN4e"; pal_mod.markerWrite(fn4e);
    var fn4x_buf: [20]u8 = undefined; var fn4x_len = itoa_mod.itoa(@intCast(u32, self.registry.xt_len), fn4x_buf[0..]); var fn4x_s: usize = @intCast(usize, 19) - @intCast(usize, fn4x_len); var fn4x_m: []const u8 = "FN4x"; pal_mod.markerWrite(fn4x_m); pal_mod.markerWrite(fn4x_buf[fn4x_s..@intCast(usize, 19)]);
    var fn4y_buf: [20]u8 = undefined; var fn4y_len = itoa_mod.itoa(@intCast(u32, pstart), fn4y_buf[0..]); var fn4y_s: usize = @intCast(usize, 19) - @intCast(usize, fn4y_len); var fn4y_m: []const u8 = "FN4y"; pal_mod.markerWrite(fn4y_m); pal_mod.markerWrite(fn4y_buf[fn4y_s..@intCast(usize, 19)]);
    while (ai < args.len) : (ai += 1) {
        var fn4f: []const u8 = "FN4f"; pal_mod.markerWrite(fn4f);
        var param_type = self.registry.xt_items[pstart + ai];
        hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], param_type);
        var ptm_m: []const u8 = "PTM:a"; pal_mod.markerWrite(ptm_m);
        var ptm_ab2: [10]u8 = undefined; var ptm_al = itoa_mod.itoa(@intCast(u32, ai), ptm_ab2[0..]); var ptm_as2: usize = @intCast(usize, 9) - @intCast(usize, ptm_al); pal_mod.markerWrite(ptm_ab2[ptm_as2..@intCast(usize, 9)]);
        var ptm_tm: []const u8 = "t"; pal_mod.markerWrite(ptm_tm);
        var ptm_tb: [10]u8 = undefined; var ptm_tl2 = itoa_mod.itoa(param_type, ptm_tb[0..]); var ptm_ts: usize = @intCast(usize, 9) - @intCast(usize, ptm_tl2); pal_mod.markerWrite(ptm_tb[ptm_ts..@intCast(usize, 9)]);
        var ptm_nm: []const u8 = "n"; pal_mod.markerWrite(ptm_nm);
        var ptm_nb: [10]u8 = undefined; var ptm_nl3 = itoa_mod.itoa(args[ai], ptm_nb[0..]); var ptm_ns: usize = @intCast(usize, 9) - @intCast(usize, ptm_nl3); pal_mod.markerWrite(ptm_nb[ptm_ns..@intCast(usize, 9)]);
        var ptm_nl4: []const u8 = "\n"; pal_mod.markerWrite(ptm_nl4);
        var fn4g: []const u8 = "FN4g"; pal_mod.markerWrite(fn4g);
        var arg_type = semanticAnalyzerResolveExpr(self, args[ai]);
        if (param_type == type_mod.TYPE_UNDEFINED) { if (arg_type != type_mod.TYPE_UNDEFINED) { hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], arg_type); } }
        if (param_type == type_mod.TYPE_VOID) { if (arg_type != type_mod.TYPE_UNDEFINED) { hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], arg_type); } }
        tryRecordCoercion(self, args[ai], arg_type, param_type);
    }
    var fn4: []const u8 = "FN4"; pal_mod.markerWrite(fn4);
    var fn4_rb: [20]u8 = undefined; var fn4_rl = itoa_mod.itoa(fnp.return_type, fn4_rb[0..]); var fn4_rs: usize = @intCast(usize, 19) - @intCast(usize, fn4_rl); var fn4_rm: []const u8 = "R"; pal_mod.markerWrite(fn4_rm); pal_mod.markerWrite(fn4_rb[fn4_rs..@intCast(usize, 19)]);
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
    var el: []const u8 = "eL"; pal_mod.markerWrite(el);
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
            var nd: []const u8 = "n"; pal_mod.markerWrite(nd); pal_mod.markerWrite(nb[ns..@intCast(usize, 19)]);
            var fd: []const u8 = "f"; pal_mod.markerWrite(fd); pal_mod.markerWrite(fb[fs2..@intCast(usize, 19)]);
            var sp: []const u8 = " "; pal_mod.markerWrite(sp);
            var fcB: [20]u8 = undefined; var fcL = itoa_mod.itoa(@intCast(u32, fcount), fcB[0..]);
            var fcS: usize = @intCast(usize, 19) - @intCast(usize, fcL);
            var fcT: []const u8 = "fc="; pal_mod.markerWrite(fcT); pal_mod.markerWrite(fcB[fcS..@intCast(usize, 19)]);
            var fcP: []const u8 = " "; pal_mod.markerWrite(fcP);
            var fi: usize = 0;
            while (fi < fcount) : (fi += 1) {
                var fe = self.registry.fe_items[fstart + fi];
                var feb: [20]u8 = undefined; var feL = itoa_mod.itoa(@intCast(u32, fe.name_id), feb[0..]);
                var fes: usize = @intCast(usize, 19) - @intCast(usize, feL);
                var feT: []const u8 = "g"; pal_mod.markerWrite(feT); pal_mod.markerWrite(feb[fes..@intCast(usize, 19)]);
                var feP: []const u8 = " "; pal_mod.markerWrite(feP);
                if (fe.name_id == n) {
                    hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, @intCast(u32, fi));
                    var ew: []const u8 = "EW"; pal_mod.markerWrite(ew);
                    var evgc = self.enum_value_table.count;
                    var eg_buf: [20]u8 = undefined;
                    var eg_len = itoa_mod.itoa(@intCast(u32, evgc), eg_buf[0..]);
                    var egs: usize = @intCast(usize, 19) - @intCast(usize, eg_len);
                    var eN: []const u8 = "eN="; pal_mod.markerWrite(eN);
                    pal_mod.markerWrite(eg_buf[egs..@intCast(usize, 19)]);
                    var eS: []const u8 = " "; pal_mod.markerWrite(eS);
                    var re: []const u8 = "E"; pal_mod.markerWrite(re);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, self.current_switch_cond_tu);
                    return self.current_switch_cond_tu;
                }
            }
        }
    }
    var elv_m: []const u8 = "ELV:n"; pal_mod.markerWrite(elv_m);
    var elv_nb: [10]u8 = undefined; var elv_nl: u32 = itoa_mod.itoa(n, elv_nb[0..]); var elv_ns: usize = @intCast(usize, 9) - @intCast(usize, elv_nl); pal_mod.markerWrite(elv_nb[elv_ns..@intCast(usize, 9)]);
    var elv_x: []const u8 = "\n"; pal_mod.markerWrite(elv_x);
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
            var fname_id = fi_node.payload;
            if (fname_id != @intCast(u32, 0)) {
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.registry.fe_items[fstart + fi].name_id == fname_id) {
                        if (fi_node.child_0 != @intCast(u32, 0)) {
                            var init_type = semanticAnalyzerResolveExpr(self, fi_node.child_0);
                            var field_type = self.registry.fe_items[fstart + fi].type_id;
                            tryRecordCoercion(self, fi_node.child_0, init_type, field_type);
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
            var fname_id = fi_node.payload;
            if (fname_id != @intCast(u32, 0)) {
                var fi: usize = 0;
                while (fi < fcount) : (fi += 1) {
                    if (self.registry.fe_items[fstart + fi].name_id == fname_id) {
                        if (fi_node.child_0 != @intCast(u32, 0)) {
                            var init_type = semanticAnalyzerResolveExpr(self, fi_node.child_0);
                            var field_type = self.registry.fe_items[fstart + fi].type_id;
                            tryRecordCoercion(self, fi_node.child_0, init_type, field_type);
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
    var ase: []const u8 = "ASE"; pal_mod.markerWrite(ase);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var lhs = semanticAnalyzerResolveExpr(self, node.child_0);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) { var as0: []const u8 = "AS0"; pal_mod.markerWrite(as0); return type_mod.TYPE_VOID; }
    if (type_mod.typeRegistryIsAssignable(self.registry, rhs, lhs)) {
        tryRecordCoercion(self, node.child_1, rhs, lhs);
        var as1: []const u8 = "AS1"; pal_mod.markerWrite(as1);
        return lhs;
    }
    var as2: []const u8 = "AS2"; pal_mod.markerWrite(as2);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveSwitchExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var se: []const u8 = "SE"; pal_mod.markerWrite(se);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var ent_m: []const u8 = "SWI:n"; pal_mod.markerWrite(ent_m); var ent_nb: [10]u8 = undefined; var ent_nl = itoa_mod.itoa(node_idx, ent_nb[0..]); var ent_ns: usize = @intCast(usize, 9) - @intCast(usize, ent_nl); pal_mod.markerWrite(ent_nb[ent_ns..@intCast(usize, 9)]); var ent_pm: []const u8 = "p"; pal_mod.markerWrite(ent_pm); var ent_pb: [10]u8 = undefined; var ent_pl = itoa_mod.itoa(node.payload, ent_pb[0..]); var ent_ps: usize = @intCast(usize, 9) - @intCast(usize, ent_pl); pal_mod.markerWrite(ent_pb[ent_ps..@intCast(usize, 9)]); var ent_nl2: []const u8 = "\n"; pal_mod.markerWrite(ent_nl2);
    if (node.payload == @intCast(u32, 0)) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
    var cond_type = semanticAnalyzerResolveExpr(self, node.child_0);
    self.current_switch_cond_tu = @intCast(u32, 0);
    if (cond_type != @intCast(u32, 0) and cond_type != type_mod.TYPE_VOID) {
        var cond_ty = self.registry.types_items[@intCast(usize, cond_type)];
        if (cond_ty.kind == type_mod.TypeKind.tagged_union_type) {
            self.current_switch_cond_tu = cond_type;
            var rs: []const u8 = "Z"; pal_mod.markerWrite(rs);
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
        var pS: []const u8 = "pC="; pal_mod.markerWrite(pS);
        pal_mod.markerWrite(pct_buf[ps1..@intCast(usize, 19)]);
        var pP: []const u8 = " pP="; pal_mod.markerWrite(pP);
        pal_mod.markerWrite(pp_buf[ps2..@intCast(usize, 19)]);
        var pn: []const u8 = " "; pal_mod.markerWrite(pn);
        if (self.current_switch_cond_tu != @intCast(u32, 0) and prong.payload != @intCast(u32, 0)) {
            var case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong.payload);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                var case_node = self.store.nodes.items[@intCast(usize, case_ec[ci])];
                var cc_buf: [20]u8 = undefined;
                var cc_val = @intCast(u32, @enumToInt(case_node.kind));
                var cc_len = itoa_mod.itoa(cc_val, cc_buf[0..]);
                var ccs: usize = @intCast(usize, 19) - @intCast(usize, cc_len);
                var ccS: []const u8 = "cK="; pal_mod.markerWrite(ccS);
                pal_mod.markerWrite(cc_buf[ccs..@intCast(usize, 19)]);
                    var ccP: []const u8 = " "; pal_mod.markerWrite(ccP);
                    if (case_node.kind == AstKind.enum_literal) {
                        _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                    } else if (case_node.kind == AstKind.undefined_literal) {
                        _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                    }
            }
            if ((prong.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
                var cap_name = prong.child_1;
                if (case_ec.len > @intCast(usize, 0)) {
                    var ev = hash_mod.u32ToU32MapGet(self.enum_value_table, case_ec[0]);
                    if (ev) |idx| {
                        var tu_ty = self.registry.types_items[@intCast(usize, self.current_switch_cond_tu)];
                        var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
                        var fe: type_mod.FieldEntry = self.registry.fe_items[@intCast(usize, tp.fields_start) + @intCast(usize, idx)];
                        if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
                        self.local_decl_names[self.local_decl_count] = cap_name;
                        self.local_decl_types[self.local_decl_count] = fe.type_id;
                        self.local_decl_count += @intCast(usize, 1);
                        var scax_m: []const u8 = "SCAX:n"; pal_mod.markerWrite(scax_m);
                        var scax_nb: [10]u8 = undefined; var scax_nl = itoa_mod.itoa(cap_name, scax_nb[0..]); var scax_ns: usize = @intCast(usize, 9) - @intCast(usize, scax_nl); pal_mod.markerWrite(scax_nb[scax_ns..@intCast(usize, 9)]);
                        var scax_n: []const u8 = "\n"; pal_mod.markerWrite(scax_n);
                    }
                }
            }
        }
        var bt = semanticAnalyzerResolveExpr(self, prong.child_0);
        if (self.current_fn_return != @intCast(u32, 0) and self.current_fn_return != type_mod.TYPE_VOID) {
            tryRecordCoercion(self, prong.child_0, bt, self.current_fn_return);
            if (coercion_mod.classifyCoercion(self.registry, bt, self.current_fn_return) != coercion_mod.CoercionKind.none) {
                bt = self.current_fn_return;
            }
        }
        var pct_m: []const u8 = "PCT:n"; pal_mod.markerWrite(pct_m); var pct_nb: [10]u8 = undefined; var pct_nl = itoa_mod.itoa(prong.child_0, pct_nb[0..]); var pct_ns: usize = @intCast(usize, 9) - @intCast(usize, pct_nl); pal_mod.markerWrite(pct_nb[pct_ns..@intCast(usize, 9)]); var pct_bm: []const u8 = "b"; pal_mod.markerWrite(pct_bm); var pct_bb: [10]u8 = undefined; var pct_bl = itoa_mod.itoa(bt, pct_bb[0..]); var pct_bs: usize = @intCast(usize, 9) - @intCast(usize, pct_bl); pal_mod.markerWrite(pct_bb[pct_bs..@intCast(usize, 9)]); var pct_fm: []const u8 = "f"; pal_mod.markerWrite(pct_fm); var pct_fb: [10]u8 = undefined; var pct_fl = itoa_mod.itoa(self.current_fn_return, pct_fb[0..]); var pct_fs: usize = @intCast(usize, 9) - @intCast(usize, pct_fl); pal_mod.markerWrite(pct_fb[pct_fs..@intCast(usize, 9)]); var pct_nl2: []const u8 = "\n"; pal_mod.markerWrite(pct_nl2);
        var swpb_m: []const u8 = "SWPB:pi"; pal_mod.markerWrite(swpb_m);
        var swpb_ib: [10]u8 = undefined; var swpb_il = itoa_mod.itoa(@intCast(u32, i), swpb_ib[0..]); var swpb_is: usize = @intCast(usize, 9) - @intCast(usize, swpb_il); pal_mod.markerWrite(swpb_ib[swpb_is..@intCast(usize, 9)]);
        var swpb_tm: []const u8 = ",bt"; pal_mod.markerWrite(swpb_tm);
        var swpb_tb: [10]u8 = undefined; var swpb_tl = itoa_mod.itoa(bt, swpb_tb[0..]); var swpb_ts: usize = @intCast(usize, 9) - @intCast(usize, swpb_tl); pal_mod.markerWrite(swpb_tb[swpb_ts..@intCast(usize, 9)]);
        var swpb_nl: []const u8 = "\n"; pal_mod.markerWrite(swpb_nl);
        if (i == @intCast(usize, 0)) { unified = bt; }
        else if (bt == type_mod.TYPE_NORETURN) {}
        else if (bt == unified) {}
        else {
            var unum: u32 = @intCast(u32, 0);
            if (type_mod.typeRegistryIsNumeric(self.registry, bt)) { unum = @intCast(u32, 1); }
            if (unified == type_mod.TYPE_INT_LIT and unum != @intCast(u32, 0)) { unified = bt; }
            else { var mix_m: []const u8 = "MIX:p"; pal_mod.markerWrite(mix_m); var mix_pb: [10]u8 = undefined; var mix_pl = itoa_mod.itoa(@intCast(u32, i), mix_pb[0..]); var mix_ps: usize = @intCast(usize, 9) - @intCast(usize, mix_pl); pal_mod.markerWrite(mix_pb[mix_ps..@intCast(usize, 9)]); var mix_um: []const u8 = "u"; pal_mod.markerWrite(mix_um); var mix_ub: [10]u8 = undefined; var mix_ul = itoa_mod.itoa(unified, mix_ub[0..]); var mix_us: usize = @intCast(usize, 9) - @intCast(usize, mix_ul); pal_mod.markerWrite(mix_ub[mix_us..@intCast(usize, 9)]); var mix_bm: []const u8 = "b"; pal_mod.markerWrite(mix_bm); var mix_bb: [10]u8 = undefined; var mix_bl = itoa_mod.itoa(bt, mix_bb[0..]); var mix_bs: usize = @intCast(usize, 9) - @intCast(usize, mix_bl); pal_mod.markerWrite(mix_bb[mix_bs..@intCast(usize, 9)]); var mix_nl2: []const u8 = "\n"; pal_mod.markerWrite(mix_nl2); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
        }
    }

    self.current_switch_cond_tu = @intCast(u32, 0);
    if (has_else == @intCast(u8, 0)) {
    }
    if (unified == @intCast(u32, 0)) unified = type_mod.TYPE_VOID;
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, unified);
    var swu_m: []const u8 = "SWU:n"; pal_mod.markerWrite(swu_m); var swu_nb: [10]u8 = undefined; var swu_nl = itoa_mod.itoa(node_idx, swu_nb[0..]); var swu_ns: usize = @intCast(usize, 9) - @intCast(usize, swu_nl); pal_mod.markerWrite(swu_nb[swu_ns..@intCast(usize, 9)]); var swu_tm: []const u8 = "t"; pal_mod.markerWrite(swu_tm); var swu_tb: [10]u8 = undefined; var swu_tl = itoa_mod.itoa(unified, swu_tb[0..]); var swu_ts: usize = @intCast(usize, 9) - @intCast(usize, swu_tl); pal_mod.markerWrite(swu_tb[swu_ts..@intCast(usize, 9)]); var swu_nl2: []const u8 = "\n"; pal_mod.markerWrite(swu_nl2);
    return unified;
}

pub fn semanticAnalyzerResolveExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var result: u32;
    result = @intCast(u32, 0);
    if (node_idx == @intCast(u32, 0)) return result;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    result = type_mod.TYPE_VOID;
    if (node.kind == AstKind.swt_ex) {
        var rx_sw_m: []const u8 = "RXS"; pal_mod.markerWrite(rx_sw_m);
    }

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
        result = type_mod.typeRegistryGetOrCreatePtr(self.registry, type_mod.TYPE_C_CHAR, true);
    } else if (node.kind == AstKind.enum_literal) {
        result = semanticAnalyzerResolveEnumLiteral(self, node_idx);
    } else if (node.kind == AstKind.error_literal) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.ident_expr) {
        result = semanticAnalyzerResolveIdent(self, self.module_id, self.store.identifiers.items[@intCast(usize, node.payload)], node_idx);
    } else if (node.kind == AstKind.field_access) {
        result = semanticAnalyzerResolveFieldAccess(self, node_idx);
        var fad: []const u8 = "FAD:"; pal_mod.markerWrite(fad);
        var fad_b: [20]u8 = undefined; var fad_l = itoa_mod.itoa(result, fad_b[0..]); var fad_s: usize = @intCast(usize, 19) - @intCast(usize, fad_l); pal_mod.markerWrite(fad_b[fad_s..@intCast(usize, 19)]);
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
    } else if (node.kind == AstKind.swt_ex) {
        result = semanticAnalyzerResolveSwitchExpr(self, node_idx);
    } else if (node.kind == AstKind.tuple_literal) {
        result = semanticAnalyzerResolveTupleLiteral(self, node_idx);
    } else if (node.kind == AstKind.struct_init) {
        result = semanticAnalyzerResolveStructInit(self, node_idx);
    } else if (node.kind == AstKind.array_init) {
        var ai_dbg: []const u8 = "AW";
        pal_mod.markerWrite(ai_dbg);
        result = semanticAnalyzerResolveArrayInit(self, node_idx);
        var aw_rb: [20]u8 = undefined; var aw_rl = itoa_mod.itoa(result, aw_rb[0..]); var aw_rs: usize = @intCast(usize, 19) - @intCast(usize, aw_rl); var aw_rm: []const u8 = "r"; pal_mod.markerWrite(aw_rm); pal_mod.markerWrite(aw_rb[aw_rs..@intCast(usize, 19)]);
    } else if (node.kind == AstKind.ptr_type or node.kind == AstKind.many_ptr_type or
               node.kind == AstKind.array_type or node.kind == AstKind.slice_type or
               node.kind == AstKind.optional_type or node.kind == AstKind.error_union_type or
               node.kind == AstKind.fn_type or node.kind == AstKind.struct_decl or
               node.kind == AstKind.enum_decl or node.kind == AstKind.union_decl or
               node.kind == AstKind.error_set_decl) {
        result = type_mod.TYPE_TYPE;
    } else if (node.kind == AstKind.paren_expr) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.return_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            result = semanticAnalyzerResolveExpr(self, node.child_0);
            if (self.current_fn_return != @intCast(u32, 0) and self.current_fn_return != type_mod.TYPE_VOID) {
                if (result != self.current_fn_return) {
                    var fn_ret_ty = self.registry.types_items[@intCast(usize, self.current_fn_return)];
                    if (fn_ret_ty.kind == type_mod.TypeKind.tagged_union_type) {
                        var ret_node = self.store.nodes.items[@intCast(usize, node.child_0)];
                        if (ret_node.kind == AstKind.enum_literal) {
                            var old_tu = self.current_switch_cond_tu;
                            self.current_switch_cond_tu = self.current_fn_return;
                            var elv_res = semanticAnalyzerResolveExpr(self, node.child_0);
                            self.current_switch_cond_tu = old_tu;
                            result = elv_res;
                        }
                    }
                }
            }
        } else {
            result = type_mod.TYPE_VOID;
        }
    } else if (node.kind == AstKind.expr_stmt) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        result = type_mod.TYPE_VOID;
    } else if (node.kind == AstKind.block) {
        var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
        if (children.len > @intCast(usize, 0)) {
            var si: usize = 0;
            while (si < children.len - @intCast(usize, 1)) : (si += 1) {
                semanticAnalyzerResolveStmtDepth(self, children[si], @intCast(u32, 0));
            }
            var last_child = children[children.len - @intCast(usize, 1)];
            result = semanticAnalyzerResolveExpr(self, last_child);
        } else {
            result = type_mod.TYPE_VOID;
        }
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
    } else if (node.kind == AstKind.plain_assign or
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
        pal_mod.markerWrite(st_m);
        pal_mod.markerWrite(st_k[st_s..@intCast(usize, 19)]);
        var st_nid_buf: [20]u8 = undefined; var st_nid_len = itoa_mod.itoa(node_idx, st_nid_buf[0..]); var st_nid_s: usize = @intCast(usize, 19) - @intCast(usize, st_nid_len); var st_nid_m: []const u8 = "n"; pal_mod.markerWrite(st_nid_m); pal_mod.markerWrite(st_nid_buf[st_nid_s..@intCast(usize, 19)]);
        var st_v: []const u8 = "\n";
        pal_mod.markerWrite(st_v);
        result = type_mod.TYPE_VOID;
    }

    if (result != type_mod.TYPE_VOID) {
        var a4_m: []const u8 = "A4:"; pal_mod.markerWrite(a4_m);
        var a4_nb: [20]u8 = undefined; var a4_nl = itoa_mod.itoa(node_idx, a4_nb[0..]); var a4_ns: usize = @intCast(usize, 19) - @intCast(usize, a4_nl); pal_mod.markerWrite(a4_nb[a4_ns..@intCast(usize, 19)]);
        var a4_km: []const u8 = "k"; pal_mod.markerWrite(a4_km);
        var a4_kb: [20]u8 = undefined; var a4_kl = itoa_mod.itoa(@intCast(u32, @enumToInt(node.kind)), a4_kb[0..]); var a4_ks: usize = @intCast(usize, 19) - @intCast(usize, a4_kl); pal_mod.markerWrite(a4_kb[a4_ks..@intCast(usize, 19)]);
        var a4_rm: []const u8 = "r"; pal_mod.markerWrite(a4_rm);
        var a4_rb: [20]u8 = undefined; var a4_rl = itoa_mod.itoa(result, a4_rb[0..]); var a4_rs: usize = @intCast(usize, 19) - @intCast(usize, a4_rl); pal_mod.markerWrite(a4_rb[a4_rs..@intCast(usize, 19)]);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
        var stb_m: []const u8 = "STB:n"; pal_mod.markerWrite(stb_m);
        var stb_nb: [10]u8 = undefined; var stb_nl = itoa_mod.itoa(node_idx, stb_nb[0..]); var stb_ns: usize = @intCast(usize, 9) - @intCast(usize, stb_nl); pal_mod.markerWrite(stb_nb[stb_ns..@intCast(usize, 9)]);
        var stb_rm: []const u8 = "R"; pal_mod.markerWrite(stb_rm);
        var stb_rb: [10]u8 = undefined; var stb_rl = itoa_mod.itoa(result, stb_rb[0..]); var stb_rs: usize = @intCast(usize, 9) - @intCast(usize, stb_rl); pal_mod.markerWrite(stb_rb[stb_rs..@intCast(usize, 9)]);
        var stb_nl2: []const u8 = "\n"; pal_mod.markerWrite(stb_nl2);
    }
    return result;
}

pub fn semanticAnalyzerResolveFnBody(self: *SemanticAnalyzer, fn_decl_node: u32) void {
    var fb: []const u8 = "FB"; pal_mod.markerWrite(fb);
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
                var rtm: []const u8 = "A2:"; pal_mod.markerWrite(rtm);
                var rt_nb: [20]u8 = undefined; var rt_nl = itoa_mod.itoa(pnode.payload, rt_nb[0..]); var rt_ns: usize = @intCast(usize, 19) - @intCast(usize, rt_nl); pal_mod.markerWrite(rt_nb[rt_ns..@intCast(usize, 19)]);
                var rt_am: []const u8 = "a"; pal_mod.markerWrite(rt_am);
                var rt_ab: [20]u8 = undefined; var rt_al = itoa_mod.itoa(pnode.child_0, rt_ab[0..]); var rt_as: usize = @intCast(usize, 19) - @intCast(usize, rt_al); pal_mod.markerWrite(rt_ab[rt_as..@intCast(usize, 19)]);
                var rt = rtt_mod.resolvedTypeTableGet(self.type_table, pnode.child_0);
                if (rt) |t| {
                    var rth_m: []const u8 = "H"; pal_mod.markerWrite(rth_m);
                    var rth_b: [20]u8 = undefined; var rth_l = itoa_mod.itoa(t, rth_b[0..]); var rth_s: usize = @intCast(usize, 19) - @intCast(usize, rth_l); pal_mod.markerWrite(rth_b[rth_s..@intCast(usize, 19)]);
                    self.local_decl_types[self.local_decl_count] = t;
                } else {
                    var rtm_m: []const u8 = "M"; pal_mod.markerWrite(rtm_m);
                    self.local_decl_types[self.local_decl_count] = type_mod.TYPE_UNDEFINED;
                }
                self.local_decl_count += @intCast(usize, 1);
            }
        }
    }
    var fn_rt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
    if (fn_rt) |frt| {
        self.current_fn_return = frt;
    }
    semanticAnalyzerResolveStmt(self, decl.child_0);
    var evcap = self.enum_value_table.capacity; var evcnt = self.enum_value_table.count;
    var evcap_buf: [20]u8 = undefined; var evcnt_buf: [20]u8 = undefined;
    var evcap_len = itoa_mod.itoa(@intCast(u32, evcap), evcap_buf[0..]);
    var evcnt_len = itoa_mod.itoa(@intCast(u32, evcnt), evcnt_buf[0..]);
    var evcap_s: usize = @intCast(usize, 19) - @intCast(usize, evcap_len);
    var evcnt_s: usize = @intCast(usize, 19) - @intCast(usize, evcnt_len);
    var vl: []const u8 = "vN="; pal_mod.markerWrite(vl);
    pal_mod.markerWrite(evcnt_buf[evcnt_s..@intCast(usize, 19)]);
    var vc: []const u8 = " vC="; pal_mod.markerWrite(vc);
    pal_mod.markerWrite(evcap_buf[evcap_s..@intCast(usize, 19)]);
    var vnl: []const u8 = "\n"; pal_mod.markerWrite(vnl);
}

pub fn semanticAnalyzerResolveStmtDepth(self: *SemanticAnalyzer, node_idx: u32, depth: u32) void {
    if (depth > @intCast(u32, 16)) return;
    if (node_idx == @intCast(u32, 0)) return;
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.block) {
         var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
         var blkm: []const u8 = "BLK:ni="; pal_mod.markerWrite(blkm);
         var blkb: [20]u8 = undefined; var blkl = itoa_mod.itoa(node_idx, blkb[0..]); var blks: usize = @intCast(usize, 19) - @intCast(usize, blkl); pal_mod.markerWrite(blkb[blks..@intCast(usize, 19)]);
         var blkc: []const u8 = "c="; pal_mod.markerWrite(blkc);
         var blkcb: [10]u8 = undefined; var blkcl = itoa_mod.itoa(@intCast(u32, children.len), blkcb[0..]); var blkcs: usize = @intCast(usize, 9) - @intCast(usize, blkcl); pal_mod.markerWrite(blkcb[blkcs..@intCast(usize, 9)]);
         var blkk: []const u8 = "k=["; pal_mod.markerWrite(blkk);
         var i: usize = 0;
         while (i < children.len) : (i += 1) {
             if (i > @intCast(usize, 0)) { var bc: []const u8 = ","; pal_mod.markerWrite(bc); }
             var cnode = self.store.nodes.items[@intCast(usize, children[i])];
             var bkb: [10]u8 = undefined; var bkl = itoa_mod.itoa(@intCast(u32, @enumToInt(cnode.kind)), bkb[0..]); var bks: usize = @intCast(usize, 9) - @intCast(usize, bkl); pal_mod.markerWrite(bkb[bks..@intCast(usize, 9)]);
             semanticAnalyzerResolveStmtDepth(self, children[i], depth + @intCast(u32, 1));
         }
         var bcej: []const u8 = "]\n"; pal_mod.markerWrite(bcej);
     } else if (node.kind == AstKind.var_decl) {
        if (node.payload == @intCast(u32, 55)) {
            var d10m: []const u8 = "D10:V55c0="; pal_mod.markerWrite(d10m);
            var d10b0: [10]u8 = undefined; var d10l0 = itoa_mod.itoa(node.child_0, d10b0[0..]); var d10s0: usize = @intCast(usize, 9) - @intCast(usize, d10l0); pal_mod.markerWrite(d10b0[d10s0..@intCast(usize, 9)]);
            var d10c1: []const u8 = "c1="; pal_mod.markerWrite(d10c1);
            var d10b1: [10]u8 = undefined; var d10l1 = itoa_mod.itoa(node.child_1, d10b1[0..]); var d10s1: usize = @intCast(usize, 9) - @intCast(usize, d10l1); pal_mod.markerWrite(d10b1[d10s1..@intCast(usize, 9)]);
            if (node.child_1 != @intCast(u32, 0)) {
                var inode = self.store.nodes.items[@intCast(usize, node.child_1)];
                var d10ik: []const u8 = "ik="; pal_mod.markerWrite(d10ik);
                var d10ikb: [10]u8 = undefined; var d10ikl = itoa_mod.itoa(@intCast(u32, @enumToInt(inode.kind)), d10ikb[0..]); var d10iks: usize = @intCast(usize, 9) - @intCast(usize, d10ikl); pal_mod.markerWrite(d10ikb[d10iks..@intCast(usize, 9)]);
            }
            var d10nl: []const u8 = "\n"; pal_mod.markerWrite(d10nl);
        }
        var vd_m: []const u8 = "FB1:VDn"; pal_mod.markerWrite(vd_m);
        var vd_nb: [10]u8 = undefined; var vd_nl = itoa_mod.itoa(node.payload, vd_nb[0..]); var vd_ns: usize = @intCast(usize, 9) - @intCast(usize, vd_nl); pal_mod.markerWrite(vd_nb[vd_ns..@intCast(usize, 9)]);
        var vd_dd: []const u8 = "c"; pal_mod.markerWrite(vd_dd);
        var vd_cb: [10]u8 = undefined; var vd_cl = itoa_mod.itoa(@intCast(u32, self.local_decl_count), vd_cb[0..]); var vd_cs: usize = @intCast(usize, 9) - @intCast(usize, vd_cl); pal_mod.markerWrite(vd_cb[vd_cs..@intCast(usize, 9)]);
        var vd_sp: []const u8 = " "; pal_mod.markerWrite(vd_sp);
        var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
        if (node.child_0 != @intCast(u32, 0)) {
            var ann = self.store.nodes.items[@intCast(usize, node.child_0)];
            if (ann.kind == AstKind.ident_expr) { decl_type = semanticAnalyzerResolveExpr(self, node.child_0); }
            else {
                var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
                if (rt) |t| { decl_type = t; }
            }
        }
        if (node.child_1 != @intCast(u32, 0)) {
            var vdi: []const u8 = "I"; pal_mod.markerWrite(vdi);
            var init_node = self.store.nodes.items[@intCast(usize, node.child_1)];
            var ik = @intCast(u32, @enumToInt(init_node.kind));
            var ib: [20]u8 = undefined;
            var il = itoa_mod.itoa(ik, ib[0..]);
            var is: usize = @intCast(usize, 20) - @intCast(usize, 1) - @intCast(usize, il);
            pal_mod.markerWrite(ib[is..@intCast(usize, 20)]);
            pal_mod.markerWrite(vdi);
            var it = semanticAnalyzerResolveExpr(self, node.child_1);
            if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED) and it != decl_type) {
                var ck = coercion_mod.classifyCoercion(self.registry, it, decl_type);
                if (ck != coercion_mod.CoercionKind.none) {
                    coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, ck, decl_type);
                }
            }
            if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED)) { decl_type = it; }
            rtt_mod.resolvedTypeTableSet(self.type_table, node.child_1, decl_type);
        }
        if (self.local_decl_count >= self.local_decl_cap) {
            semanticAnalyzerGrowLocalDecls(self);
        }
        self.local_decl_names[self.local_decl_count] = node.payload;
        self.local_decl_types[self.local_decl_count] = decl_type;
        self.local_decl_count += @intCast(usize, 1);
        var d4v: []const u8 = "D4:vn"; pal.markerWrite(d4v);
        var d4vb: [10]u8 = undefined; var d4vl = itoa_mod.itoa(node.payload, d4vb[0..]); var d4vs: usize = @intCast(usize, 9) - @intCast(usize, d4vl); pal.markerWrite(d4vb[d4vs..@intCast(usize, 9)]);
        var d4vt: []const u8 = "t"; pal.markerWrite(d4vt);
        var d4vtb: [10]u8 = undefined; var d4vtl = itoa_mod.itoa(decl_type, d4vtb[0..]); var d4vts: usize = @intCast(usize, 9) - @intCast(usize, d4vtl); pal.markerWrite(d4vtb[d4vts..@intCast(usize, 9)]);
        var d4vnl: []const u8 = " "; pal.markerWrite(d4vnl);
    } else if (node.kind == AstKind.if_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
        if (node.child_2 != @intCast(u32, 0)) {
            semanticAnalyzerResolveStmtDepth(self, node.child_2, depth + @intCast(u32, 1));
        }
     } else if (node.kind == AstKind.while_stmt) {
        var wsm: []const u8 = "WS:b1="; pal_mod.markerWrite(wsm);
        var wsb: [20]u8 = undefined; var wsl = itoa_mod.itoa(node.child_1, wsb[0..]); var wss: usize = @intCast(usize, 19) - @intCast(usize, wsl); pal_mod.markerWrite(wsb[wss..@intCast(usize, 19)]);
        var wsnl: []const u8 = " "; pal_mod.markerWrite(wsnl);
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.for_stmt) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        var fsm: []const u8 = "FS:"; pal.markerWrite(fsm);
        var fsc_b: [20]u8 = undefined; var fsc_l = itoa_mod.itoa(node.child_0, fsc_b[0..]); var fsc_s: usize = @intCast(usize, 19) - @intCast(usize, fsc_l); pal.markerWrite(fsc_b[fsc_s..@intCast(usize, 19)]);
        var fsk_m: []const u8 = "k"; pal.markerWrite(fsk_m);
        var cnode = self.store.nodes.items[@intCast(usize, node.child_0)];
        var fsk_b: [20]u8 = undefined; var fsk_l = itoa_mod.itoa(@intCast(u32, @enumToInt(cnode.kind)), fsk_b[0..]); var fsk_s: usize = @intCast(usize, 19) - @intCast(usize, fsk_l); pal.markerWrite(fsk_b[fsk_s..@intCast(usize, 19)]);
        var it_tid = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
        if (it_tid) |tid| {
            var a5_hm: []const u8 = "H"; pal.markerWrite(a5_hm);
            var a5_hb: [20]u8 = undefined; var a5_hl = itoa_mod.itoa(tid, a5_hb[0..]); var a5_hs: usize = @intCast(usize, 19) - @intCast(usize, a5_hl); pal.markerWrite(a5_hb[a5_hs..@intCast(usize, 19)]);
            var ty = self.registry.types_items[@intCast(usize, tid)];
            var elem_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
            if (ty.kind == type_mod.TypeKind.slice_type) {
                elem_box[0] = self.registry.slice_items[@intCast(usize, ty.payload_idx)].elem;
            } else if (ty.kind == type_mod.TypeKind.array_type) {
                elem_box[0] = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem;
            }
            if (node.payload != @intCast(u32, 0) and elem_box[0] != type_mod.TYPE_UNDEFINED) {
                var fsm1: []const u8 = "FSRp"; pal.markerWrite(fsm1);
                var fsm1b: [10]u8 = undefined; var fsm1l = itoa_mod.itoa(node.payload, fsm1b[0..]); var fsm1s: usize = @intCast(usize, 9) - @intCast(usize, fsm1l); pal.markerWrite(fsm1b[fsm1s..@intCast(usize, 9)]);
                var fsm1et: []const u8 = "e"; pal.markerWrite(fsm1et);
                var fsm1eb: [10]u8 = undefined; var fsm1el = itoa_mod.itoa(elem_box[0], fsm1eb[0..]); var fsm1es: usize = @intCast(usize, 9) - @intCast(usize, fsm1el); pal.markerWrite(fsm1eb[fsm1es..@intCast(usize, 9)]);
                var fsm1sp: []const u8 = " "; pal.markerWrite(fsm1sp);
                if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
                self.local_decl_names[self.local_decl_count] = node.payload; self.local_decl_types[self.local_decl_count] = elem_box[0]; self.local_decl_count += @intCast(usize, 1);
                var d4f: []const u8 = "D4:fn"; pal.markerWrite(d4f);
                var d4fb: [10]u8 = undefined; var d4fl = itoa_mod.itoa(node.payload, d4fb[0..]); var d4fs: usize = @intCast(usize, 9) - @intCast(usize, d4fl); pal.markerWrite(d4fb[d4fs..@intCast(usize, 9)]);
                var d4ft: []const u8 = "t"; pal.markerWrite(d4ft);
                var d4ftb: [10]u8 = undefined; var d4ftl = itoa_mod.itoa(elem_box[0], d4ftb[0..]); var d4fts: usize = @intCast(usize, 9) - @intCast(usize, d4ftl); pal.markerWrite(d4ftb[d4fts..@intCast(usize, 9)]);
                var d4fnl: []const u8 = " "; pal.markerWrite(d4fnl);
            }
        } else {
            var a5_mm: []const u8 = "M"; pal_mod.markerWrite(a5_mm);
        }
        if (node.child_2 != @intCast(u32, 0)) {
            if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
            self.local_decl_names[self.local_decl_count] = node.child_2; self.local_decl_types[self.local_decl_count] = type_mod.TYPE_USIZE; self.local_decl_count += @intCast(usize, 1);
            var f2m: []const u8 = "FIX2:ln"; pal_mod.markerWrite(f2m);
            var f2mb: [10]u8 = undefined; var f2ml = itoa_mod.itoa(node.child_2, f2mb[0..]); var f2ms: usize = @intCast(usize, 9) - @intCast(usize, f2ml); pal_mod.markerWrite(f2mb[f2ms..@intCast(usize, 9)]);
            var f2sp: []const u8 = " "; pal_mod.markerWrite(f2sp);
        }
        semanticAnalyzerResolveStmtDepth(self, node.child_1, depth + @intCast(u32, 1));
    } else if (node.kind == AstKind.swt_ex) {
        var sw: []const u8 = "SW"; pal_mod.markerWrite(sw);
        _ = semanticAnalyzerResolveExpr(self, node_idx);
        if (node.payload != @intCast(u32, 0)) {
            var prongs = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
            var pi: usize = 0;
            while (pi < prongs.len) : (pi += 1) {
                var prong_node = self.store.nodes.items[@intCast(usize, prongs[pi])];
                var flgm: []const u8 = "FLG:n"; pal_mod.markerWrite(flgm);
                var flgnb: [10]u8 = undefined; var flgnl = itoa_mod.itoa(@intCast(u32, prong_node.flags), flgnb[0..]); var flgns: usize = @intCast(usize, 9) - @intCast(usize, flgnl); pal_mod.markerWrite(flgnb[flgns..@intCast(usize, 9)]);
                var flgpm: []const u8 = "c1="; pal_mod.markerWrite(flgpm);
                var flgpb: [10]u8 = undefined; var flgpl = itoa_mod.itoa(prong_node.child_1, flgpb[0..]); var flgps: usize = @intCast(usize, 9) - @intCast(usize, flgpl); pal_mod.markerWrite(flgpb[flgps..@intCast(usize, 9)]);
                var flgn: []const u8 = "\n"; pal_mod.markerWrite(flgn);
                if ((prong_node.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
                    var capture_name = prong_node.child_1;
                    var cond_rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
                    if (cond_rt) |cond_type| {
                        var crtm: []const u8 = "CRT:n"; pal_mod.markerWrite(crtm);
                        var crtnb: [10]u8 = undefined; var crtnl = itoa_mod.itoa(cond_type, crtnb[0..]); var crtns: usize = @intCast(usize, 9) - @intCast(usize, crtnl); pal_mod.markerWrite(crtnb[crtns..@intCast(usize, 9)]);
                        var crtn: []const u8 = "\n"; pal_mod.markerWrite(crtn);
                        if (cond_type != @intCast(u32, 0) and cond_type != type_mod.TYPE_VOID) {
                            var tu_ty = self.registry.types_items[@intCast(usize, cond_type)];
                            if (tu_ty.kind == type_mod.TypeKind.tagged_union_type) {
                                var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
                                var case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong_node.payload);
                                var cecm: []const u8 = "CEC:n"; pal_mod.markerWrite(cecm);
                                var cecnb: [10]u8 = undefined; var cecnl = itoa_mod.itoa(@intCast(u32, case_ec.len), cecnb[0..]); var cecns: usize = @intCast(usize, 9) - @intCast(usize, cecnl); pal_mod.markerWrite(cecnb[cecns..@intCast(usize, 9)]);
                                var cecn: []const u8 = "\n"; pal_mod.markerWrite(cecn);
                                if (case_ec.len > @intCast(usize, 0)) {
                                    var ev = hash_mod.u32ToU32MapGet(self.enum_value_table, case_ec[0]);
                                    if (ev) |idx| {
                                        var evtm: []const u8 = "EVT:n"; pal_mod.markerWrite(evtm);
                                        var evtnb: [10]u8 = undefined; var evtnl = itoa_mod.itoa(idx, evtnb[0..]); var evtns: usize = @intCast(usize, 9) - @intCast(usize, evtnl); pal_mod.markerWrite(evtnb[evtns..@intCast(usize, 9)]);
                                        var evtn: []const u8 = "\n"; pal_mod.markerWrite(evtn);
                                        var fe: type_mod.FieldEntry = self.registry.fe_items[@intCast(usize, tp.fields_start) + @intCast(usize, idx)];
                                        if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
                                        self.local_decl_names[self.local_decl_count] = capture_name;
                                        self.local_decl_types[self.local_decl_count] = fe.type_id;
                                        self.local_decl_count += @intCast(usize, 1);
                                        var sca_m: []const u8 = "SCA:n"; pal_mod.markerWrite(sca_m);
                                        var sca_nb: [10]u8 = undefined; var sca_nl = itoa_mod.itoa(capture_name, sca_nb[0..]); var sca_ns: usize = @intCast(usize, 9) - @intCast(usize, sca_nl); pal_mod.markerWrite(sca_nb[sca_ns..@intCast(usize, 9)]);
                                        var sca_tm: []const u8 = "t"; pal_mod.markerWrite(sca_tm);
                                        var sca_tb: [10]u8 = undefined; var sca_tl = itoa_mod.itoa(fe.type_id, sca_tb[0..]); var sca_ts: usize = @intCast(usize, 9) - @intCast(usize, sca_tl); pal_mod.markerWrite(sca_tb[sca_ts..@intCast(usize, 9)]);
                                        var sca_em: []const u8 = "\n"; pal_mod.markerWrite(sca_em);
                                    } else {
                                        var evt_nul: []const u8 = "EVT:NULL\n"; pal_mod.markerWrite(evt_nul);
                                    }
                                }
                            }
                        }
                    } else {
                        var crt_nul: []const u8 = "CRT:NULL\n"; pal_mod.markerWrite(crt_nul);
                    }
                }
                if (prong_node.child_0 != @intCast(u32, 0)) {
                    semanticAnalyzerResolveStmtDepth(self, prong_node.child_0, depth + @intCast(u32, 1));
                }
            }
        }
    } else if (node.kind == AstKind.return_stmt) {
        if (node.child_0 != @intCast(u32, 0)) {
            var ret_val = semanticAnalyzerResolveExpr(self, node.child_0);
            if (self.current_fn_return != @intCast(u32, 0) and self.current_fn_return != type_mod.TYPE_VOID) {
                if (ret_val != self.current_fn_return) {
                    var fn_ret_ty = self.registry.types_items[@intCast(usize, self.current_fn_return)];
                    if (fn_ret_ty.kind == type_mod.TypeKind.tagged_union_type) {
                        var ret_node = self.store.nodes.items[@intCast(usize, node.child_0)];
                        if (ret_node.kind == AstKind.enum_literal) {
                            var old_tu = self.current_switch_cond_tu;
                            self.current_switch_cond_tu = self.current_fn_return;
                            _ = semanticAnalyzerResolveExpr(self, node.child_0);
                            self.current_switch_cond_tu = old_tu;
                        }
                    }
                }
                var t2f_m: []const u8 = "T2F:n"; pal_mod.markerWrite(t2f_m); var t2f_nb: [10]u8 = undefined; var t2f_nl = itoa_mod.itoa(node.child_0, t2f_nb[0..]); var t2f_ns: usize = @intCast(usize, 9) - @intCast(usize, t2f_nl); pal_mod.markerWrite(t2f_nb[t2f_ns..@intCast(usize, 9)]); var t2f_rm: []const u8 = "r"; pal_mod.markerWrite(t2f_rm); var t2f_rb: [10]u8 = undefined; var t2f_rl = itoa_mod.itoa(ret_val, t2f_rb[0..]); var t2f_rs: usize = @intCast(usize, 9) - @intCast(usize, t2f_rl); pal_mod.markerWrite(t2f_rb[t2f_rs..@intCast(usize, 9)]); var t2f_fm: []const u8 = "f"; pal_mod.markerWrite(t2f_fm); var t2f_fb: [10]u8 = undefined; var t2f_fl = itoa_mod.itoa(self.current_fn_return, t2f_fb[0..]); var t2f_fs: usize = @intCast(usize, 9) - @intCast(usize, t2f_fl); pal_mod.markerWrite(t2f_fb[t2f_fs..@intCast(usize, 9)]); var t2f_nl2: []const u8 = "\n"; pal_mod.markerWrite(t2f_nl2);
                tryRecordCoercion(self, node.child_0, ret_val, self.current_fn_return);
            }
        }
    } else if (node.kind == AstKind.plain_assign or
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

fn semaTraceStep(self: *SemanticAnalyzer, cur_name: *u32, done: *u8) u32 {
    var ss = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, cur_name.*);
    if (ss) |s| {
        if (s.decl_node == @intCast(u32, 0)) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        var dn = self.store.nodes.items[@intCast(usize, s.decl_node)];
        if (dn.kind != AstKind.var_decl) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        if (dn.child_1 == @intCast(u32, 0)) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        var init = self.store.nodes.items[@intCast(usize, dn.child_1)];
        if (init.kind != AstKind.slice_expr) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        if (init.child_0 == @intCast(u32, 0)) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        var c0 = self.store.nodes.items[@intCast(usize, init.child_0)];
        if (c0.kind != AstKind.ident_expr) { done.* = @intCast(u8, 1); return @intCast(u32, 0); }
        var nn = self.store.identifiers.items[@intCast(usize, c0.payload)];
        cur_name.* = nn;
        return nn;
    }
    done.* = @intCast(u8, 1);
    return @intCast(u32, 0);
}

fn semanticAnalyzerResolveIndexAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var ii_m: []const u8 = "IXA:i"; pal_mod.markerWrite(ii_m);
    var ii_b: [10]u8 = undefined; var ii_l = itoa_mod.itoa(node_idx, ii_b[0..]); var ii_s: usize = @intCast(usize, 9) - @intCast(usize, ii_l); pal_mod.markerWrite(ii_b[ii_s..@intCast(usize, 9)]);
    var ii_nl: []const u8 = "\n"; pal_mod.markerWrite(ii_nl);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    _ = semanticAnalyzerResolveExpr(self, node.child_1);
    self._stub_0 = semanticAnalyzerResolveExpr(self, node.child_0);
    var c0_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var c0k_m: []const u8 = "C0K:k"; pal_mod.markerWrite(c0k_m);
    var c0k_b: [10]u8 = undefined; var c0k_l = itoa_mod.itoa(@intCast(u32, @enumToInt(c0_node.kind)), c0k_b[0..]); var c0k_s: usize = @intCast(usize, 9) - @intCast(usize, c0k_l); pal_mod.markerWrite(c0k_b[c0k_s..@intCast(usize, 9)]);
    var c0k_nl: []const u8 = "\n"; pal_mod.markerWrite(c0k_nl);
    if (c0_node.kind == AstKind.ident_expr) {
        var c0_name_id = self.store.identifiers.items[@intCast(usize, c0_node.payload)];
        var ste_m: []const u8 = "STE:n"; pal_mod.markerWrite(ste_m);
        var ste_b: [10]u8 = undefined; var ste_l = itoa_mod.itoa(node_idx, ste_b[0..]); var ste_s: usize = @intCast(usize, 9) - @intCast(usize, ste_l); pal_mod.markerWrite(ste_b[ste_s..@intCast(usize, 9)]);
        var ste_nl: []const u8 = "\n"; pal_mod.markerWrite(ste_nl);
        var src_cur_name = c0_name_id;
        var src_depth: u32 = @intCast(u32, 0);
        var src_name: u32 = @intCast(u32, 0);
        var src_done: u8 = @intCast(u8, 0);
        while (src_done == @intCast(u8, 0) and src_depth < @intCast(u32, 3)) : (src_depth += @intCast(u32, 1)) { src_name = semaTraceStep(self, &src_cur_name, &src_done); }
        if (src_name != @intCast(u32, 0)) {
            var srs_n: []const u8 = "SRC:n"; pal_mod.markerWrite(srs_n);
            var srs_b: [10]u8 = undefined; var srs_l = itoa_mod.itoa(node_idx, srs_b[0..]); var srs_s: usize = @intCast(usize, 9) - @intCast(usize, srs_l); pal_mod.markerWrite(srs_b[srs_s..@intCast(usize, 9)]);
            var srs_m: []const u8 = "s"; pal_mod.markerWrite(srs_m);
            var srs_b2: [10]u8 = undefined; var srs_l2 = itoa_mod.itoa(src_name, srs_b2[0..]); var srs_s2: usize = @intCast(usize, 9) - @intCast(usize, srs_l2); pal_mod.markerWrite(srs_b2[srs_s2..@intCast(usize, 9)]);
            var srs_nl: []const u8 = "\n"; pal_mod.markerWrite(srs_nl);
            _ = rtt_mod.resolvedSourceTableSet(self.type_table, node.child_0, src_name);
        }
    }
    var ix_m: []const u8 = "IX:"; pal_mod.markerWrite(ix_m);
    var ix_bb: [20]u8 = undefined; var ix_bl = itoa_mod.itoa(self._stub_0, ix_bb[0..]); var ix_bs: usize = @intCast(usize, 19) - @intCast(usize, ix_bl); pal_mod.markerWrite(ix_bb[ix_bs..@intCast(usize, 19)]);
    if (self._stub_0 == @intCast(u32, 0) or self._stub_0 == type_mod.TYPE_VOID) { rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
    var bt = self.registry.types_items[@intCast(usize, self._stub_0)];
    if (bt.kind == type_mod.TypeKind.array_type) {
        var r1 = self.registry.array_items[@intCast(usize, bt.payload_idx)].elem;
        var ix_r: []const u8 = "r"; pal_mod.markerWrite(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r1, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.markerWrite(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r1;
    } else if (bt.kind == type_mod.TypeKind.slice_type) {
        var r2 = self.registry.slice_items[@intCast(usize, bt.payload_idx)].elem;
        var ix_r: []const u8 = "r"; pal_mod.markerWrite(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r2, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.markerWrite(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r2;
    } else if (bt.kind == type_mod.TypeKind.ptr_type or bt.kind == type_mod.TypeKind.many_ptr_type) {
        var r3 = self.registry.ptr_items[@intCast(usize, bt.payload_idx)].base;
        var ix_r: []const u8 = "r"; pal_mod.markerWrite(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r3, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.markerWrite(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r3;
    } else if (bt.kind == type_mod.TypeKind.tuple_type) {
        var tp = self.registry.tup_items[@intCast(usize, bt.payload_idx)];
        var r4 = self.registry.xt_items[@intCast(usize, tp.elems_start)];
        var ix_r: []const u8 = "r"; pal_mod.markerWrite(ix_r);
        var ix_rb: [20]u8 = undefined; var ix_rl = itoa_mod.itoa(r4, ix_rb[0..]); var ix_rs: usize = @intCast(usize, 19) - @intCast(usize, ix_rl); pal_mod.markerWrite(ix_rb[ix_rs..@intCast(usize, 19)]);
        return r4;
    }
    var ix_d: []const u8 = "d"; pal_mod.markerWrite(ix_d);
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
