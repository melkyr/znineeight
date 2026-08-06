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
const type_resolver = @import("type_resolver.zig");

pub const SemanticAnalyzer = struct {
    type_table: *ResolvedTypeTable,
    diag: *DiagnosticCollector,
    registry: *TypeRegistry,
    symbols: *SymbolRegistry,
    store: *AstStore,
    module_id: u32,
    source_file_id: u32,
    expected_type_stack_items: [*]TypeId,
    expected_type_stack_len: usize,
    expected_type_stack_cap: usize,
    expected_type_stack_alloc: *Sand,
    stmt_work_items: [*]u32,
    stmt_work_len: usize,
    stmt_work_cap: usize,
    current_fn_return: TypeId,
    current_fn_name: u32,
    coercion_table: *coercion_mod.CoercionTable,
    enum_value_table: *hash_mod.U32ToU32Map,
    error_code_registry: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
    call_param_map: *hash_mod.U32ToU32Map,
    current_switch_cond_tu: u32,
    switch_depth: u32,
    local_decl_names: [*]u32,
    local_decl_types: [*]u32,
    local_decl_count: usize,
    local_decl_cap: usize,
    _stub_0: u32,
    _stub_1: u32,
    interner: *interner_mod.StringInterner,
    ptrcast_name_id: u32,
    ptrtoint_name_id: u32,
    inttoptr_name_id: u32,
    intcast_name_id: u32,
    floatcast_name_id: u32,
    inttofloat_name_id: u32,
    inttoenum_name_id: u32,
    size_of_name_id: u32,
    align_of_name_id: u32,
};

pub fn semanticAnalyzerInit(alloc: *Sand, type_table: *ResolvedTypeTable, diag: *DiagnosticCollector, registry: *TypeRegistry, symbols: *SymbolRegistry, store: *AstStore, module_id: u32, source_file_id: u32, coercion_tab: *coercion_mod.CoercionTable, enum_val_tab: *hash_mod.U32ToU32Map, error_code_reg: *hash_mod.U32ToU32Map, interner: *interner_mod.StringInterner, cal_typs: *hash_mod.U32ToU32Map, cp_map: *hash_mod.U32ToU32Map) SemanticAnalyzer {
    var und_text: []const u8 = "_";
    var und_name_id = interner_mod.stringInternerIntern(interner, und_text);
    var pc_text: []const u8 = "@ptrCast";
    var pc_name_id = interner_mod.stringInternerIntern(interner, pc_text);
    var pti_s: []const u8 = "@ptrToInt";
    var ptin_id = interner_mod.stringInternerIntern(interner, pti_s);
    var itp_s: []const u8 = "@intToPtr";
    var itp_id = interner_mod.stringInternerIntern(interner, itp_s);
    var ic_s: []const u8 = "@intCast";
    var ic_id = interner_mod.stringInternerIntern(interner, ic_s);
    var fc_s: []const u8 = "@floatCast";
    var fc_id = interner_mod.stringInternerIntern(interner, fc_s);
    var if_s: []const u8 = "@intToFloat";
    var if_id = interner_mod.stringInternerIntern(interner, if_s);
    var ie_s: []const u8 = "@intToEnum";
    var ie_id = interner_mod.stringInternerIntern(interner, ie_s);
    var so_s: []const u8 = "@sizeOf";
    var so_id = interner_mod.stringInternerIntern(interner, so_s);
    var ao_s: []const u8 = "@alignOf";
    var ao_id = interner_mod.stringInternerIntern(interner, ao_s);
    return SemanticAnalyzer{
        .type_table = type_table,
        .diag = diag,
        .registry = registry,
        .symbols = symbols,
        .store = store,
        .module_id = module_id,
        .source_file_id = source_file_id,
        .expected_type_stack_items = undefined,
        .expected_type_stack_len = @intCast(usize, 0),
        .expected_type_stack_cap = @intCast(usize, 0),
        .expected_type_stack_alloc = alloc,
        .stmt_work_items = undefined,
        .stmt_work_len = @intCast(usize, 0),
        .stmt_work_cap = @intCast(usize, 0),
        .current_fn_return = @intCast(u32, 0),
        .current_fn_name = @intCast(u32, 0),
        .coercion_table = coercion_tab,
        .enum_value_table = enum_val_tab,
        .error_code_registry = error_code_reg,
        .current_switch_cond_tu = @intCast(u32, 0),
        .switch_depth = @intCast(u32, 0),
        .local_decl_names = undefined,
        .local_decl_types = undefined,
        .local_decl_count = @intCast(usize, 0),
        .local_decl_cap = @intCast(usize, 0),
        ._stub_0 = und_name_id,
        ._stub_1 = @intCast(u32, 0),
        .call_arg_types = cal_typs,
        .call_param_map = cp_map,
        .interner = interner,
        .ptrcast_name_id = pc_name_id,
        .ptrtoint_name_id = ptin_id,
        .inttoptr_name_id = itp_id,
        .intcast_name_id = ic_id,
        .floatcast_name_id = fc_id,
        .inttofloat_name_id = if_id,
        .inttoenum_name_id = ie_id,
        .size_of_name_id = so_id,
        .align_of_name_id = ao_id,
    };
}

fn semanticAnalyzerIsTypeValueCast(self: *SemanticAnalyzer, name_id: u32) bool {
    if (name_id == self.ptrcast_name_id) return true;
    if (name_id == self.inttoptr_name_id) return true;
    if (name_id == self.intcast_name_id) return true;
    if (name_id == self.floatcast_name_id) return true;
    if (name_id == self.inttofloat_name_id) return true;
    if (name_id == self.inttoenum_name_id) return true;
    return false;
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

fn registerLocalDecl(self: *SemanticAnalyzer, name_id: u32, type_id: u32) void {
    if (self.local_decl_count >= self.local_decl_cap) {
        semanticAnalyzerGrowLocalDecls(self);
    }
    var sct_nm: []const u8 = "SCT:n"; pal_mod.markerWriteInt(sct_nm, name_id);
    var sct_tm: []const u8 = "SCT:t"; pal_mod.markerWriteInt(sct_tm, type_id);
    self.local_decl_names[self.local_decl_count] = name_id;
    self.local_decl_types[self.local_decl_count] = type_id;
    self.local_decl_count += @intCast(usize, 1);
}

fn semanticAnalyzerCaptureType(self: *SemanticAnalyzer, cond_type: u32) u32 {
    if (cond_type == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var capt_ty = self.registry.types_items[@intCast(usize, cond_type)];
    if (capt_ty.kind == type_mod.TypeKind.optional_type) {
        return self.registry.opt_items[@intCast(usize, capt_ty.payload_idx)].payload;
    }
    return cond_type;
}

pub fn semanticAnalyzerResolveIdent(self: *SemanticAnalyzer, module_id: u32, name_id: u32, node_idx: u32) u32 {
    var ide: []const u8 = "IDE\n"; pal_mod.markerWrite(ide);
    if (name_id == @intCast(u32, 1)) { var sem_m: []const u8 = "SEM:vi"; pal_mod.markerWriteInt(sem_m, module_id); }
    var li = self.local_decl_count;
    while (li > @intCast(usize, 0)) {
        li -= @intCast(usize, 1);
            if (self.local_decl_names[li] == name_id) {
                var lcl_t = self.local_decl_types[li];
                var d7m: []const u8 = "D7:Yn"; pal_mod.markerWrite(d7m);
                var d7n_m: []const u8 = "D7:n"; pal_mod.markerWriteInt(d7n_m, name_id);
                var d7tm: []const u8 = "D7:t"; pal_mod.markerWrite(d7tm);
                var d7t_m: []const u8 = "D7"; pal_mod.markerWriteInt(d7t_m, lcl_t);
                var id1: []const u8 = "L\n"; pal_mod.markerWrite(id1);
            var lt_m: []const u8 = "L:t"; pal_mod.markerWriteInt(lt_m, lcl_t);
            return lcl_t;
        }
    }
    var key = @intCast(u64, name_id);
    var ncg = type_mod.nameCacheGet(self.registry, key);
    var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, name_id);
    if (sym) |s| {
        var id2: []const u8 = "S\n"; pal_mod.markerWrite(id2);
        if (s.kind == sym_mod.SymbolKind.type_alias) { var rdt_talias: []const u8 = "TAL\n"; pal_mod.markerWrite(rdt_talias); return s.type_id; }
        if (s.type_id != @intCast(u32, 0)) { var rdt_nm: []const u8 = "STY:N"; pal_mod.markerWriteInt(rdt_nm, name_id); var rdt_tm: []const u8 = "STY:T"; pal_mod.markerWriteInt(rdt_tm, s.type_id); if (ncg) |nt| { var rdt_ntm: []const u8 = "STY:C"; pal_mod.markerWriteInt(rdt_ntm, nt); } return s.type_id; }
        var rdt_sv: []const u8 = "SVO\n"; pal.markerWrite(rdt_sv); return type_mod.TYPE_VOID;
    }
    if (ncg) |t| { var id3: []const u8 = "C2:T"; pal_mod.markerWriteInt(id3, t); return t; }
     var d8n_m: []const u8 = "D8:Nn"; pal_mod.markerWriteInt(d8n_m, name_id);
     var d8c_m: []const u8 = "D8:C"; pal_mod.markerWriteInt(d8c_m, @intCast(u32, self.local_decl_count));
      if (self.local_decl_count > @intCast(usize, 0)) {
          var d8f_m: []const u8 = "D8:F"; pal_mod.markerWriteInt(d8f_m, self.local_decl_names[@intCast(usize, 0)]);
          var d8l_m: []const u8 = "D8:L"; pal_mod.markerWriteInt(d8l_m, self.local_decl_names[self.local_decl_count - @intCast(usize, 1)]);
     }
      if (self.local_decl_count > @intCast(usize, 4)) {
          var d8x_m: []const u8 = "D8:X"; pal_mod.markerWriteInt(d8x_m, self.local_decl_names[@intCast(usize, 4)]);
     }
      var d8i_m: []const u8 = "D8:I"; pal_mod.markerWriteInt(d8i_m, node_idx);
        if (node_idx >= @intCast(u32, 450) and node_idx <= @intCast(u32, 660)) {
            var cname = interner_mod.stringInternerGet(self.interner, name_id);
            pal_mod.markerWrite(cname);
           var cnode = self.store.nodes.items[@intCast(usize, node_idx)];
           var d8k_m: []const u8 = "D8"; pal_mod.markerWriteInt(d8k_m, @intCast(u32, @enumToInt(cnode.kind)));
           var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node_idx);
           if (rt) |t| { var d8t_m: []const u8 = "D8:T"; pal_mod.markerWriteInt(d8t_m, t); }
           else { var d8z_m: []const u8 = "D8:Z\n"; pal_mod.markerWrite(d8z_m); }
          var d8nl2: []const u8 = "\n"; pal_mod.markerWrite(d8nl2);
      }
    if (name_id == self._stub_0) {
        return type_mod.TYPE_UNDEFINED;
    }
    var idm: []const u8 = "IDT:"; pal_mod.markerWrite(idm);
    var idnb: [10]u8 = undefined; var idnl = itoa_mod.itoa(name_id, idnb[0..]); var idns: usize = @intCast(usize, 9) - @intCast(usize, idnl); pal_mod.markerWrite(idnb[idns..@intCast(usize, 9)]);
    var idc: []const u8 = ":VOID\n"; pal_mod.markerWrite(idc);
    return type_mod.TYPE_VOID;
}

pub fn semanticAnalyzerResolveFieldAccess(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var fae: []const u8 = "FAE\n"; pal_mod.markerWrite(fae);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var base_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var field_name_id = node.payload;
    var pfa_bkm: []const u8 = "PFA:BK"; pal_mod.markerWriteInt(pfa_bkm, @intCast(u32, @enumToInt(base_node.kind)));
    var pfa_fnm: []const u8 = "PFA:FN"; pal_mod.markerWriteInt(pfa_fnm, field_name_id);

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
                    if (aty.kind == type_mod.TypeKind.enum_type) {
                        var ep = self.registry.en_items[@intCast(usize, aty.payload_idx)];
                        var estart: usize = @intCast(usize, ep.members_start);
                        var ecount: usize = @intCast(usize, ep.members_count);
                        var ei: usize = 0;
                        while (ei < ecount) : (ei += 1) {
                            if (self.registry.em_items[estart + ei].name_id == field_name_id) {
                                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, alias_type_id);
                                return alias_type_id;
                            }
                        }
                    }
                    if (aty.kind == type_mod.TypeKind.error_set_type) {
                        var es_mi = type_mod.typeRegistryErrorSetMemberIndex(self.registry, alias_type_id, field_name_id);
                        if (es_mi != @intCast(u32, 0xFFFFFFFF)) {
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, alias_type_id);
                            return alias_type_id;
                        }
                    }
                }
            }
            if (s.kind == sym_mod.SymbolKind.module) {
                var target_mod = s.module_id;
                var field_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, target_mod, field_name_id);
                if (field_sym) |fs| {
                    var q1fl_m: []const u8 = "Q1:FL"; pal_mod.markerWriteInt(q1fl_m, @intCast(u32, fs.flags));
                    var q1kl_m: []const u8 = "Q1:KL"; pal_mod.markerWriteInt(q1kl_m, @intCast(u32, @enumToInt(fs.kind)));
                    var q1tl_m: []const u8 = "Q1:TL"; pal_mod.markerWriteInt(q1tl_m, fs.type_id);
                    var q1fn_m: []const u8 = "Q1:FN"; pal_mod.markerWriteInt(q1fn_m, field_name_id);
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
                        var q1fx: []const u8 = "Q1FX\n"; pal_mod.markerWrite(q1fx);
                        var fn_dn = self.store.nodes.items[@intCast(usize, fs.decl_node)];
                        if (fn_dn.kind == AstKind.fn_decl) {
                            var proto = self.store.fn_protos.items[@intCast(usize, fn_dn.payload)];
                            var bre1_m: []const u8 = "BR:x"; pal_mod.markerWriteInt(bre1_m, proto.name_id);
                            if (proto.return_type_node != @intCast(u32, 0)) {
                                var rtt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                                var rtt_val: u32 = if (rtt) |rv| rv else @intCast(u32, 0);
                                var bre2_m: []const u8 = "BR:rt"; pal_mod.markerWriteInt(bre2_m, rtt_val);
                                if (rtt) |rtv| {
                                    var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, fs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, rtv);
                                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                                    return fn_ty;
                                }
                                var tre_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                                var resolved_rt = type_resolver.resolveTypeExprFull(&tre_env, proto.return_type_node, @intCast(u32, 0));
                                var brr1_m: []const u8 = "BR:treN"; pal_mod.markerWriteInt(brr1_m, proto.return_type_node);
                                var brr2_m: []const u8 = "BR:treT"; pal_mod.markerWriteInt(brr2_m, resolved_rt);
                                if (resolved_rt != type_mod.TYPE_UNDEFINED) {
                                    rtt_mod.resolvedTypeTableSet(self.type_table, proto.return_type_node, resolved_rt);
                                    var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, fs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, resolved_rt);
                                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                                    return fn_ty;
                                }
                            }
                            var bre3_m: []const u8 = "BR:dv\n"; pal_mod.markerWrite(bre3_m);
                            var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, fs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, type_mod.TYPE_VOID);
                            var bre4_m: []const u8 = "BR:ft"; pal_mod.markerWriteInt(bre4_m, fn_ty);
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                            return fn_ty;
                        }
                    }
                }
                var q1v_m: []const u8 = "Q1VF:FN"; pal_mod.markerWriteInt(q1v_m, field_name_id);
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
                return type_mod.TYPE_VOID;
            }
        }
    }

    var base_type_id = semanticAnalyzerResolveExpr(self, node.child_0);
    if (base_type_id == type_mod.TYPE_VOID) {
        var fa1: []const u8 = "FB\n"; pal_mod.markerWrite(fa1);
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
        var fapr_ok_m: []const u8 = "FAPR:OK"; pal_mod.markerWriteInt(fapr_ok_m, @intCast(u32, @enumToInt(pre_kind)));
        var fapr_dk_m: []const u8 = "FAPR:DK"; pal_mod.markerWriteInt(fapr_dk_m, @intCast(u32, @enumToInt(base_ty.kind)));
        var fapr_nl: []const u8 = "\n"; pal_mod.markerWrite(fapr_nl);
    }
    if (base_ty.kind == type_mod.TypeKind.optional_type) {
        var sp = node.span_start;
        var ep = sp + @intCast(u32, node.span_len);
        var opt_msg: []const u8 = "cannot access field on optional type; use .? to unwrap first";
        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000),
            self.source_file_id, sp, ep, opt_msg);
        return type_mod.TYPE_VOID;
    }
    if (base_ty.kind == type_mod.TypeKind.error_union_type) {
        var sp = node.span_start;
        var ep = sp + @intCast(u32, node.span_len);
        var eu_msg: []const u8 = "cannot access field on error-union type; handle the error first";
        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000),
            self.source_file_id, sp, ep, eu_msg);
        return type_mod.TYPE_VOID;
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
        var mfa: []const u8 = "MFA\n"; pal_mod.markerWrite(mfa);
        var mod_field_sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, base_ty.module_id, field_name_id);
        if (mod_field_sym) |mfs| {
            if (mfs.type_id != @intCast(u32, 0)) {
                var mf1: []const u8 = "MF1\n"; pal_mod.markerWrite(mf1);
                rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, mfs.type_id);
                return mfs.type_id;
            }
            if (mfs.kind == sym_mod.SymbolKind.function) {
                var fn_tid_opt = rtt_mod.resolvedTypeTableGet(self.type_table, mfs.decl_node);
                if (fn_tid_opt) |fn_tid| {
                    var mf1: []const u8 = "MF1\n"; pal_mod.markerWrite(mf1);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_tid);
                    return fn_tid;
                }
                var mff: []const u8 = "MFF\n"; pal_mod.markerWrite(mff);
                var dn = self.store.nodes.items[@intCast(usize, mfs.decl_node)];
                if (dn.kind == AstKind.fn_decl) {
                    var proto = self.store.fn_protos.items[@intCast(usize, dn.payload)];
                    var mfp_m: []const u8 = "MFP"; pal_mod.markerWriteInt(mfp_m, @intCast(u32, proto.params_start));
                    if (proto.return_type_node != @intCast(u32, 0)) {
                        var rtt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                        if (rtt) |rtv| {
                             var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, mfs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, rtv);
                             rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                              return fn_ty;
                }
                var tre_env_b = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                var resolved_rt_b = type_resolver.resolveTypeExprFull(&tre_env_b, proto.return_type_node, @intCast(u32, 0));
                if (resolved_rt_b != type_mod.TYPE_UNDEFINED) {
                    rtt_mod.resolvedTypeTableSet(self.type_table, proto.return_type_node, resolved_rt_b);
                    var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, mfs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, resolved_rt_b);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                    return fn_ty;
                }
            }
                     var fn_ty = type_mod.typeRegistryGetOrCreateFn(self.registry, proto.name_id, mfs.module_id, @intCast(u8, 0), @intCast(u8, 0), proto.params_start, proto.params_count, type_mod.TYPE_VOID);
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, fn_ty);
                    return fn_ty;
                }
            }
            var mf2_m: []const u8 = "MF2"; pal_mod.markerWriteInt(mf2_m, @intCast(u32, @enumToInt(mfs.kind)));
        } else {
            var mf3: []const u8 = "MF3\n"; pal_mod.markerWrite(mf3);
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
    } else if (base_ty.kind == type_mod.TypeKind.error_set_type) {
        var es_mi2 = type_mod.typeRegistryErrorSetMemberIndex(self.registry, base_type_id, field_name_id);
        if (es_mi2 != @intCast(u32, 0xFFFFFFFF)) {
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, base_type_id);
            return base_type_id;
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    } else {
        var fnf: []const u8 = "FF\n"; pal_mod.markerWrite(fnf);
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
        return type_mod.TYPE_VOID;
    }

    var fi: usize = 0;
    while (fi < fields_count) {
        var fe = self.registry.fe_items[fields_start + fi];
        if (fe.name_id == field_name_id) {
            var result = fe.type_id;
            var rt = self.registry.types_items[@intCast(usize, result)];
            if (rt.kind == type_mod.TypeKind.array_type) {
                var elem = self.registry.array_items[@intCast(usize, rt.payload_idx)].elem;
                result = type_mod.typeRegistryGetOrCreatePtr(self.registry, elem, false);
            }
            if (base_ty.kind == type_mod.TypeKind.tagged_union_type) { result = base_type_id; }
            var ff_m: []const u8 = "FF:R"; pal_mod.markerWriteInt(ff_m, result);
            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
            return result;
        }
        fi += 1;
    }

    var fnf2: []const u8 = "NF\n"; pal_mod.markerWrite(fnf2);
    var ff2n_m: []const u8 = "FF2:N"; pal_mod.markerWriteInt(ff2n_m, node_idx); var ff2f_m: []const u8 = "FF2:F"; pal_mod.markerWriteInt(ff2f_m, field_name_id); var ff2b_m: []const u8 = "FF2:B"; pal_mod.markerWriteInt(ff2b_m, base_type_id);
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
        var rhs_uint = type_mod.typeRegistryIsUnsigned(self.registry, rhs) or rhs == type_mod.TYPE_INT_LIT;
        var rhs_ptr = type_mod.typeRegistryIsPointer(self.registry, rhs) or type_mod.typeRegistryIsSlice(self.registry, rhs);
        if (lhs_ptr and rhs_uint) return lhs;
        if (op_kind == AstKind.add and (type_mod.typeRegistryIsUnsigned(self.registry, lhs) or lhs == type_mod.TYPE_INT_LIT) and rhs_ptr) return rhs;
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
    var lhs: u32 = 0;
    var rhs: u32 = 0;
    var c0n = self.store.nodes.items[@intCast(usize, node.child_0)];
    var c1n = self.store.nodes.items[@intCast(usize, node.child_1)];
    var c0_lit: u8 = if (c0n.kind == AstKind.error_literal or c0n.kind == AstKind.enum_literal) @intCast(u8, 1) else @intCast(u8, 0);
    var c1_lit: u8 = if (c1n.kind == AstKind.error_literal or c1n.kind == AstKind.enum_literal) @intCast(u8, 1) else @intCast(u8, 0);
    if (c0_lit == @intCast(u8, 0) and c1_lit != @intCast(u8, 0)) {
        lhs = semanticAnalyzerResolveExpr(self, node.child_0);
        var peerk: u32 = 0;
        if (lhs != 0 and lhs != type_mod.TYPE_VOID and lhs != type_mod.TYPE_UNDEFINED) { peerk = self.registry.types_items[@intCast(usize, lhs)].kind; }
        if ((c1n.kind == AstKind.error_literal and peerk == type_mod.TypeKind.error_set_type) or (c1n.kind == AstKind.enum_literal and peerk == type_mod.TypeKind.tagged_union_type)) {
            pushExpectedType(self, lhs); rhs = semanticAnalyzerResolveExpr(self, node.child_1); popExpectedType(self);
        } else { rhs = semanticAnalyzerResolveExpr(self, node.child_1); }
    } else if (c0_lit != @intCast(u8, 0) and c1_lit == @intCast(u8, 0)) {
        rhs = semanticAnalyzerResolveExpr(self, node.child_1);
        var peerk: u32 = 0;
        if (rhs != 0 and rhs != type_mod.TYPE_VOID and rhs != type_mod.TYPE_UNDEFINED) { peerk = self.registry.types_items[@intCast(usize, rhs)].kind; }
        if ((c0n.kind == AstKind.error_literal and peerk == type_mod.TypeKind.error_set_type) or (c0n.kind == AstKind.enum_literal and peerk == type_mod.TypeKind.tagged_union_type)) {
            pushExpectedType(self, rhs); lhs = semanticAnalyzerResolveExpr(self, node.child_0); popExpectedType(self);
        } else { lhs = semanticAnalyzerResolveExpr(self, node.child_0); }
    } else {
        lhs = semanticAnalyzerResolveExpr(self, node.child_0);
        rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    }
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
    if (lhs == rhs) {
        if (lhs == type_mod.TYPE_BOOL) { var cp5: []const u8 = "CPB"; pal_mod.markerWrite(cp5); return type_mod.TYPE_BOOL; }
        if (type_mod.typeRegistryIsPointer(self.registry, lhs)) { var cp6: []const u8 = "CPB"; pal_mod.markerWrite(cp6); return type_mod.TYPE_BOOL; }
    }
    var cpv: []const u8 = "CPVl"; pal_mod.markerWrite(cpv); var cpv_lb: [10]u8 = undefined; var cpv_ll = itoa_mod.itoa(lhs, cpv_lb[0..]); var cpv_ls: usize = @intCast(usize, 9) - @intCast(usize, cpv_ll); pal_mod.markerWrite(cpv_lb[cpv_ls..@intCast(usize, 9)]); var cpv_rh: []const u8 = "r"; pal_mod.markerWrite(cpv_rh); var cpv_rb: [10]u8 = undefined; var cpv_rl = itoa_mod.itoa(rhs, cpv_rb[0..]); var cpv_rs: usize = @intCast(usize, 9) - @intCast(usize, cpv_rl); pal_mod.markerWrite(cpv_rb[cpv_rs..@intCast(usize, 9)]); var cpv_ih: []const u8 = "n"; pal_mod.markerWrite(cpv_ih); var cpv_ib: [10]u8 = undefined; var cpv_il = itoa_mod.itoa(node.child_0, cpv_ib[0..]); var cpv_is: usize = @intCast(usize, 9) - @intCast(usize, cpv_il); pal_mod.markerWrite(cpv_ib[cpv_is..@intCast(usize, 9)]); var cpv_nl: []const u8 = "\n"; pal_mod.markerWrite(cpv_nl);
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
    var coe_nm: []const u8 = "COE:N"; pal_mod.markerWriteInt(coe_nm, src_node);
    var coe_sm: []const u8 = "COE:S"; pal_mod.markerWriteInt(coe_sm, src_type);
    var coe_dm: []const u8 = "COE:D"; pal_mod.markerWriteInt(coe_dm, dst_type);
    {
        var src_t = self.registry.types_items[@intCast(usize, src_type)];
        var dst_t = self.registry.types_items[@intCast(usize, dst_type)];
        var coe_skm: []const u8 = "COE:SK"; pal_mod.markerWriteInt(coe_skm, @intCast(u32, @enumToInt(src_t.kind)));
        var coe_dkm: []const u8 = "COE:DK"; pal_mod.markerWriteInt(coe_dkm, @intCast(u32, @enumToInt(dst_t.kind)));
    }
    {
        var snode = self.store.nodes.items[@intCast(usize, src_node)];
        var coe_nkm: []const u8 = "COE:NK"; pal_mod.markerWriteInt(coe_nkm, @intCast(u32, @enumToInt(snode.kind)));
    }
    if (src_type == type_mod.TYPE_UNDEFINED or src_type == dst_type) return;
    if (!type_mod.typeRegistryIsAssignable(self.registry, src_type, dst_type)) return;
    if (src_type == type_mod.TYPE_NULL) { var cs1_m: []const u8 = "CS1\n"; pal_mod.markerWrite(cs1_m); }
    var ck = coercion_mod.classifyCoercion(self.registry, src_type, dst_type);
    var cka_m: []const u8 = "CCK:ca"; pal_mod.markerWriteInt(cka_m, @intCast(u32, @enumToInt(ck)));
    if (ck != coercion_mod.CoercionKind.none or (src_type == type_mod.TYPE_NULL and type_mod.typeRegistryIsPointer(self.registry, dst_type))) {
        coercion_mod.coercionTableAdd(self.coercion_table, src_node, ck, dst_type);
        var cor_nm: []const u8 = "COR:N"; pal_mod.markerWriteInt(cor_nm, src_node); var cor_km: []const u8 = "COR:K"; pal_mod.markerWriteInt(cor_km, @intCast(u32, @enumToInt(ck)));
    }
}

fn errLitSrcType(self: *SemanticAnalyzer, child_0: u32, target_ty: u32, ret_val: u32) u32 {
    var rn = self.store.nodes.items[@intCast(usize, child_0)];
    if (rn.kind == AstKind.error_literal) {
        var frt = self.registry.types_items[@intCast(usize, target_ty)];
        if (frt.kind == type_mod.TypeKind.error_union_type) {
            return self.registry.eu_items[@intCast(usize, frt.payload_idx)].error_set;
        }
    }
    return ret_val;
}

fn resolveReturnStmt(self: *SemanticAnalyzer, node_idx: u32) void {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.child_0 != @intCast(u32, 0)) {
        pushExpectedType(self, self.current_fn_return);
        var ret_val = semanticAnalyzerResolveExpr(self, node.child_0);
        popExpectedType(self);
        if (self.current_fn_return != @intCast(u32, 0) and self.current_fn_return != type_mod.TYPE_VOID) {

            var t2f_nm: []const u8 = "T2F:C"; pal_mod.markerWriteInt(t2f_nm, node.child_0);
            var t2f_rm: []const u8 = "T2F:R"; pal_mod.markerWriteInt(t2f_rm, ret_val);
            var t2f_fm: []const u8 = "T2F:F"; pal_mod.markerWriteInt(t2f_fm, self.current_fn_return);
            tryRecordCoercion(self, node.child_0, errLitSrcType(self, node.child_0, self.current_fn_return, ret_val), self.current_fn_return);
        }
    }
}

fn semanticAnalyzerResolveFnCall(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var fne: []const u8 = "FNE\n"; pal_mod.markerWrite(fne);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var callee_node = self.store.nodes.items[@intCast(usize, node.child_0)];
    var direct_ret: u32 = @intCast(u32, 0);
    var cpp_val_fnx: u32 = @intCast(u32, 0);
    var decl_cap: u32 = 0;
    if (callee_node.kind == AstKind.ident_expr) {
        var sym = sym_mod.symbolRegistryQualifiedLookup(self.symbols, self.module_id, self.store.identifiers.items[@intCast(usize, callee_node.payload)]);
        if (sym) |s| { var xf: []const u8 = "XF\n"; pal_mod.markerWrite(xf);
            decl_cap = s.decl_node;
            if (s.type_id != @intCast(u32, 0)) { rtt_mod.resolvedTypeTableSet(self.type_table, node.child_0, s.type_id); }
            if (s.kind == sym_mod.SymbolKind.function and s.decl_node != @intCast(u32, 0)) {
                var dn = self.store.nodes.items[@intCast(usize, s.decl_node)];
                if (dn.kind == AstKind.fn_decl) {
                    var proto = self.store.fn_protos.items[@intCast(usize, dn.payload)];
                    if (proto.return_type_node != @intCast(u32, 0)) {
                        var rt = rtt_mod.resolvedTypeTableGet(self.type_table, proto.return_type_node);
                        var rnt_val: u32 = if (rt) |t| t else @intCast(u32, 0);
                        var brnt_m: []const u8 = "BR:rnt"; pal_mod.markerWriteInt(brnt_m, rnt_val);
                        if (rt) |t| { direct_ret = t; }
                        else {
                            var drfb_m: []const u8 = "DRETFB:n"; pal_mod.markerWriteInt(drfb_m, node_idx);
                            var rn = self.store.nodes.items[@intCast(usize, proto.return_type_node)];
                            var brnk_m: []const u8 = "BR:rnk"; pal_mod.markerWriteInt(brnk_m, @intCast(u32, @enumToInt(rn.kind)));
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
                            } else {
                                var tre_env_fc = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                                var fc_rt = type_resolver.resolveTypeExprFull(&tre_env_fc, proto.return_type_node, @intCast(u32, 0));
                                var brfc_m: []const u8 = "BR:fc"; pal_mod.markerWriteInt(brfc_m, fc_rt);
                                if (fc_rt != type_mod.TYPE_UNDEFINED) { direct_ret = fc_rt; }
                            }
                        }
                    var brfnr_m: []const u8 = "BR:fnr"; pal_mod.markerWriteInt(brfnr_m, direct_ret);
                }
                }
            }
        } else { var xs: []const u8 = "xS\n"; pal_mod.markerWrite(xs); }
    }
    if (direct_ret != @intCast(u32, 0)) {
        var fn1: []const u8 = "FN1\n"; pal_mod.markerWrite(fn1);
        var fn1r_m: []const u8 = "FN1:R"; pal_mod.markerWriteInt(fn1r_m, direct_ret);
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
                    pushExpectedType(self, cpp_val_fnx);
                    var dxc_at = semanticAnalyzerResolveExpr(self, args[ai2]);
                    popExpectedType(self);
                    tryRecordCoercion(self, args[ai2], errLitSrcType(self, args[ai2], cpp_val_fnx, dxc_at), cpp_val_fnx);
                }
            }
            }
            }
        var ai: usize = 0;
        while (ai < args.len) : (ai += 1) {
            pushExpectedType(self, @intCast(u32, 0));
            _ = semanticAnalyzerResolveExpr(self, args[ai]);
            popExpectedType(self);
        }
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, direct_ret);
        return direct_ret;
    }
    var callee_type = semanticAnalyzerResolveExpr(self, node.child_0);
    if (callee_type == @intCast(u32, 0)) { var fn2: []const u8 = "FN2\n"; pal_mod.markerWrite(fn2); return type_mod.TYPE_VOID; }
    var callee_ty = self.registry.types_items[@intCast(usize, callee_type)];
    if (callee_ty.kind == type_mod.TypeKind.ptr_type) {
        var cptr_pp = self.registry.ptr_items[@intCast(usize, callee_ty.payload_idx)];
        var cptr_pointee = self.registry.types_items[@intCast(usize, cptr_pp.base)];
        if (cptr_pointee.kind == type_mod.TypeKind.fn_type) {
            callee_type = cptr_pp.base;
            callee_ty = self.registry.types_items[@intCast(usize, callee_type)];
        }
    }
    if (callee_ty.kind != type_mod.TypeKind.fn_type) {
        var fn3: []const u8 = "FN3:N"; pal_mod.markerWriteInt(fn3, node_idx);
        var fn3_ct_m: []const u8 = "FN3:T"; pal_mod.markerWriteInt(fn3_ct_m, callee_type);
        var fn3_ck_m: []const u8 = "FN3:K"; pal_mod.markerWriteInt(fn3_ck_m, @intCast(u32, @enumToInt(callee_ty.kind)));
        return type_mod.TYPE_VOID;
    }
    var fn4a: []const u8 = "FN4a\n"; pal_mod.markerWrite(fn4a);
    var fnp = self.registry.fn_items[@intCast(usize, callee_ty.payload_idx)];
    var fn4b: []const u8 = "FN4b\n"; pal_mod.markerWrite(fn4b);
    var pcount: usize = @intCast(usize, fnp.params_count);
    var pstart: usize = @intCast(usize, fnp.params_start);
    var fn4c: []const u8 = "FN4c\n"; pal_mod.markerWrite(fn4c);
    var args = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    var fn4d: []const u8 = "FN4d\n"; pal_mod.markerWrite(fn4d);
    var is_var: u8 = @intCast(u8, 0);
    if ((fnp.flags_packed & @intCast(u8, 1)) != @intCast(u8, 0)) { is_var = @intCast(u8, 1); }
    var fixed: usize = pcount;
    if (is_var != @intCast(u8, 0)) {
        if (args.len < fixed) {
            return fnp.return_type;
        }
    } else if (args.len != pcount) {
        return fnp.return_type;
    }
    var ai: usize = 0;
    var fn4e: []const u8 = "FN4e\n"; pal_mod.markerWrite(fn4e);
    var fn4x_m: []const u8 = "FN4x:X"; pal_mod.markerWriteInt(fn4x_m, @intCast(u32, self.registry.xt_len));
    var fn4y_m: []const u8 = "FN4y:P"; pal_mod.markerWriteInt(fn4y_m, @intCast(u32, pstart));    while (ai < fixed) : (ai += 1) {
        var fn4f: []const u8 = "FN4f\n"; pal_mod.markerWrite(fn4f);
        var param_type = self.registry.xt_items[pstart + ai];
        hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], param_type);
        var ptm_am: []const u8 = "PTM:A"; pal_mod.markerWriteInt(ptm_am, @intCast(u32, ai));
        var ptm_tm: []const u8 = "PTM:T"; pal_mod.markerWriteInt(ptm_tm, param_type);
        var ptm_nm: []const u8 = "PTM:N"; pal_mod.markerWriteInt(ptm_nm, args[ai]);
        var fn4g: []const u8 = "FN4g\n"; pal_mod.markerWrite(fn4g);
        pushExpectedType(self, param_type);
        var arg_type = semanticAnalyzerResolveExpr(self, args[ai]);
        popExpectedType(self);
        if (param_type == type_mod.TYPE_UNDEFINED) { if (arg_type != type_mod.TYPE_UNDEFINED) { hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], arg_type); } }
        if (param_type == type_mod.TYPE_VOID) { if (arg_type != type_mod.TYPE_UNDEFINED) { hash_mod.u32ToU32MapPut(self.call_arg_types, args[ai], arg_type); } }
        tryRecordCoercion(self, args[ai], errLitSrcType(self, args[ai], param_type, arg_type), param_type);
    }
    if (is_var != @intCast(u8, 0)) {
        var vi: usize = fixed;
        while (vi < args.len) : (vi += 1) {
            pushExpectedType(self, @intCast(u32, 0));
            var varg_type = semanticAnalyzerResolveExpr(self, args[vi]);
            popExpectedType(self);
            if (varg_type != type_mod.TYPE_UNDEFINED) {
                hash_mod.u32ToU32MapPut(self.call_arg_types, args[vi], varg_type);
            }
        }
    }
    var fn4_rm: []const u8 = "FN4:R"; pal_mod.markerWriteInt(fn4_rm, fnp.return_type);
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

fn semanticAnalyzerResolveOrelseExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var inner = semanticAnalyzerResolveExpr(self, node.child_0);
    if (inner == @intCast(u32, 0) or inner == type_mod.TYPE_VOID) return type_mod.TYPE_VOID;
    var ty = self.registry.types_items[@intCast(usize, inner)];
    if (ty.kind == type_mod.TypeKind.null_type and self.expected_type_stack_len > @intCast(u32, 0)) {
        var expected = self.expected_type_stack_items[@intCast(usize, self.expected_type_stack_len - @intCast(u32, 1))];
        if (expected != @intCast(u32, 0)) {
            var oe_et = self.registry.types_items[@intCast(usize, expected)];
            var payload_type: u32 = expected;
            if (oe_et.kind == type_mod.TypeKind.optional_type) {
                var oe_opt = self.registry.opt_items[@intCast(usize, oe_et.payload_idx)];
                payload_type = oe_opt.payload;
            }
            var opt_target = type_mod.typeRegistryGetOrCreateOptional(self.registry, payload_type);
            coercion_mod.coercionTableAdd(self.coercion_table, node.child_0, coercion_mod.CoercionKind.wrap_optional_null, opt_target);
            return payload_type;
        }
        return type_mod.TYPE_VOID;
    }
    if (ty.kind != type_mod.TypeKind.optional_type) {
        return type_mod.TYPE_VOID;
    }
    var opt = self.registry.opt_items[@intCast(usize, ty.payload_idx)];
    coercion_mod.coercionTableAdd(self.coercion_table, node.child_0, coercion_mod.CoercionKind.unwrap_optional, opt.payload);
    if (node.child_1 != @intCast(u32, 0)) {
        pushExpectedType(self, opt.payload);
        var rhs_result = semanticAnalyzerResolveExpr(self, node.child_1);
        popExpectedType(self);
        if (rhs_result != @intCast(u32, 0) and rhs_result != type_mod.TYPE_VOID) {
            tryRecordCoercion(self, node.child_1, rhs_result, opt.payload);
        }
    }
    return opt.payload;
}

fn semanticAnalyzerResolveIfExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    semanticAnalyzerResolveIfHeader(self, node_idx);
    var then_type = semanticAnalyzerResolveExpr(self, node.child_1);
    if (node.child_2 == @intCast(u32, 0)) { var sif_m: []const u8 = "SIF:0N"; pal_mod.markerWriteInt(sif_m, node_idx); var sif_tm: []const u8 = "T"; pal_mod.markerWriteInt(sif_tm, then_type); var sif_nl: []const u8 = " "; pal_mod.markerWrite(sif_nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    var else_type = semanticAnalyzerResolveExpr(self, node.child_2);
    if (then_type == else_type) { var sif_m: []const u8 = "SIF:1N"; pal_mod.markerWriteInt(sif_m, node_idx); var sif_tm: []const u8 = "T"; pal_mod.markerWriteInt(sif_tm, then_type); var sif_nl: []const u8 = " "; pal_mod.markerWrite(sif_nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_NORETURN) { var sif2m: []const u8 = "SIF:2N"; pal_mod.markerWriteInt(sif2m, node_idx); var sif2tm: []const u8 = "T"; pal_mod.markerWriteInt(sif2tm, else_type); var sif2nl: []const u8 = " "; pal_mod.markerWrite(sif2nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_NORETURN) { var sif3m: []const u8 = "SIF:3N"; pal_mod.markerWriteInt(sif3m, node_idx); var sif3tm: []const u8 = "T"; pal_mod.markerWriteInt(sif3tm, then_type); var sif3nl: []const u8 = " "; pal_mod.markerWrite(sif3nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, else_type)) { var sif4m: []const u8 = "SIF:4N"; pal_mod.markerWriteInt(sif4m, node_idx); var sif4tm: []const u8 = "T"; pal_mod.markerWriteInt(sif4tm, else_type); var sif4nl: []const u8 = " "; pal_mod.markerWrite(sif4nl); coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, coercion_mod.CoercionKind.int_literal_coerce, else_type); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_INT_LIT and type_mod.typeRegistryIsNumeric(self.registry, then_type)) { var sif5m: []const u8 = "SIF:5N"; pal_mod.markerWriteInt(sif5m, node_idx); var sif5tm: []const u8 = "T"; pal_mod.markerWriteInt(sif5tm, then_type); var sif5nl: []const u8 = " "; pal_mod.markerWrite(sif5nl); coercion_mod.coercionTableAdd(self.coercion_table, node.child_2, coercion_mod.CoercionKind.int_literal_coerce, then_type); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    if (then_type == type_mod.TYPE_VOID) { var sif6m: []const u8 = "SIF:6N"; pal_mod.markerWriteInt(sif6m, node_idx); var sif6tm: []const u8 = "T"; pal_mod.markerWriteInt(sif6tm, else_type); var sif6nl: []const u8 = " "; pal_mod.markerWrite(sif6nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, else_type); return else_type; }
    if (else_type == type_mod.TYPE_VOID) { var sif7m: []const u8 = "SIF:7N"; pal_mod.markerWriteInt(sif7m, node_idx); var sif7tm: []const u8 = "T"; pal_mod.markerWriteInt(sif7tm, then_type); var sif7nl: []const u8 = " "; pal_mod.markerWrite(sif7nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, then_type); return then_type; }
    var siffm: []const u8 = "SIF:FN"; pal_mod.markerWriteInt(siffm, node_idx); var sifftm: []const u8 = "\n"; pal_mod.markerWrite(sifftm); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveEnumLiteral(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var el: []const u8 = "eL\n"; pal_mod.markerWrite(el);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var n: u32 = self.store.identifiers.items[@intCast(usize, node.payload)];
    if (self.current_switch_cond_tu != @intCast(u32, 0)) {
        var tu_ty = self.registry.types_items[@intCast(usize, self.current_switch_cond_tu)];
        if (tu_ty.kind == type_mod.TypeKind.tagged_union_type) {
            var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
            var fstart: usize = @intCast(usize, tp.fields_start);
            var fcount: usize = @intCast(usize, tp.fields_count);
            var f0: u32 = @intCast(u32, self.registry.fe_items[fstart].name_id);
            var eln_m: []const u8 = "EL:N"; pal_mod.markerWriteInt(eln_m, n);
            var elf_m: []const u8 = "EL:F"; pal_mod.markerWriteInt(elf_m, f0);
            var elc_m: []const u8 = "EL:C"; pal_mod.markerWriteInt(elc_m, @intCast(u32, fcount));
            var fi: usize = 0;
            while (fi < fcount) : (fi += 1) {
                var fe = self.registry.fe_items[fstart + fi];
                var elv_m: []const u8 = "EL:V"; pal_mod.markerWriteInt(elv_m, @intCast(u32, fe.name_id));
                if (fe.name_id == n) {
                    var elm_m: []const u8 = "EL:M"; pal_mod.markerWriteInt(elm_m, @intCast(u32, self.enum_value_table.count));
                    hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, @intCast(u32, fi));
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, self.current_switch_cond_tu);
                    return self.current_switch_cond_tu;
                }
            }
        }
    }
    if (self.expected_type_stack_len > 0) {
        var top: u32 = self.expected_type_stack_items[@intCast(usize, self.expected_type_stack_len - 1)];
        if (top != @intCast(u32, 0)) {
            var top_ty = self.registry.types_items[@intCast(usize, top)];
            if (top_ty.kind == type_mod.TypeKind.tagged_union_type) {
                var tp = self.registry.tu_items[@intCast(usize, top_ty.payload_idx)];
                var fstart2: usize = @intCast(usize, tp.fields_start);
                var fcount2: usize = @intCast(usize, tp.fields_count);
                var fi2: usize = 0;
                while (fi2 < fcount2) : (fi2 += 1) {
                    var fe = self.registry.fe_items[fstart2 + fi2];
                    if (fe.name_id == n) {
                        if (fe.type_id == type_mod.TYPE_VOID) {
                            hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, @intCast(u32, fi2));
                            rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, top);
                            return top;
                        } else {
                            var sp = node.span_start;
                            var ep = sp + @intCast(u32, node.span_len);
                            var elr_msg: []const u8 = "enum literal member requires payload";
                            _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3008_ENUM_LITERAL_REQUIRES_PAYLOAD)), self.source_file_id, sp, ep, elr_msg);
                            return type_mod.TYPE_VOID;
                        }
                    }
                }
                var sp = node.span_start;
                var ep = sp + @intCast(u32, node.span_len);
                var elu_msg: []const u8 = "unknown enum literal member";
                _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3009_UNKNOWN_ENUM_LITERAL_MEMBER)), self.source_file_id, sp, ep, elu_msg);
                return type_mod.TYPE_VOID;
            }
        }
    }
    var elv_m: []const u8 = "ELV:N"; pal_mod.markerWriteInt(elv_m, n);
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID);
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveStructInit(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var target_type: u32 = @intCast(u32, 0);
    if (node.child_0 != @intCast(u32, 0)) {
        target_type = semanticAnalyzerResolveExpr(self, node.child_0);
    }
    if (target_type == @intCast(u32, 0)) { target_type = topExpectedType(self); }
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
                            var field_type = self.registry.fe_items[fstart + fi].type_id;
                            pushExpectedType(self, field_type);
                            var init_type = semanticAnalyzerResolveExpr(self, fi_node.child_0);
                            popExpectedType(self);
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
                            var field_type = self.registry.fe_items[fstart + fi].type_id;
                            pushExpectedType(self, field_type);
                            var init_type = semanticAnalyzerResolveExpr(self, fi_node.child_0);
                            popExpectedType(self);
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
    if (node.child_0 != @intCast(u32, 0)) {
        var lhs_node = self.store.nodes.items[@intCast(usize, node.child_0)];
        if (lhs_node.kind == AstKind.ident_expr) {
            var us_str: []const u8 = "_";
            if (self.store.identifiers.items[@intCast(usize, lhs_node.payload)] == interner_mod.stringInternerIntern(self.interner, us_str)) {
                _ = semanticAnalyzerResolveExpr(self, node.child_1);
                return type_mod.TYPE_VOID;
            }
        }
    }
    pushExpectedType(self, lhs);
    var rhs = semanticAnalyzerResolveExpr(self, node.child_1);
    popExpectedType(self);
    if (lhs == @intCast(u32, 0) or rhs == @intCast(u32, 0)) { var as0: []const u8 = "AS0"; pal_mod.markerWrite(as0); return type_mod.TYPE_VOID; }
    var eff_src = errLitSrcType(self, node.child_1, lhs, rhs);
    if (type_mod.typeRegistryIsAssignable(self.registry, eff_src, lhs)) {
        tryRecordCoercion(self, node.child_1, eff_src, lhs);
        var as1: []const u8 = "AS1"; pal_mod.markerWrite(as1);
        return lhs;
    }
    var as2: []const u8 = "AS2"; pal_mod.markerWrite(as2);
    if (lhs != type_mod.TYPE_VOID) {
            var sp = node.span_start;
            var ep = sp + @intCast(u32, node.span_len);
            var tma_msg: []const u8 = "type mismatch in assignment — internal type representations differ; generated code may be incorrect";
            var sk = self.registry.types_items[@intCast(usize, eff_src)].kind;
            var tk = self.registry.types_items[@intCast(usize, lhs)].kind;
            var level: u8 = 1;
            if (sk == type_mod.TypeKind.error_union_type and tk == type_mod.TypeKind.error_union_type) {
                var eu_src = self.registry.eu_items[@intCast(usize, self.registry.types_items[@intCast(usize, eff_src)].payload_idx)];
                var eu_tgt = self.registry.eu_items[@intCast(usize, self.registry.types_items[@intCast(usize, lhs)].payload_idx)];
                if (eu_src.error_set == eu_tgt.error_set) {
                    level = 0;
                }
            }
            var di = diag_mod.diagnosticCollectorAdd(self.diag, level, @intCast(u16, 3000),
                self.source_file_id, sp, ep, tma_msg);
            _ = diag_mod.diagnosticCollectorAddNote(self.diag, di, diag_mod.typeKindSrcStr(sk));
            _ = diag_mod.diagnosticCollectorAddNote(self.diag, di, diag_mod.typeKindTgtStr(tk));
    }
    return type_mod.TYPE_VOID;
}

fn semanticAnalyzerResolveSwitchExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    self.switch_depth += @intCast(u32, 1);
    var se: []const u8 = "SE"; pal_mod.markerWrite(se);
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var swu_im: []const u8 = "SWI:n"; pal_mod.markerWriteInt(swu_im, node_idx); var swu_pm: []const u8 = "SWI:p"; pal_mod.markerWriteInt(swu_pm, node.payload);
    var swi_dm: []const u8 = "SWI:d"; pal_mod.markerWriteInt(swi_dm, self.switch_depth);
    if (node.payload == @intCast(u32, 0)) { var sep_m: []const u8 = "P0: n"; pal_mod.markerWrite(sep_m); var sep_b: [10]u8 = undefined; var sep_l = itoa_mod.itoa(node_idx, sep_b[0..]); var sep_s: usize = @intCast(usize, 9) - @intCast(usize, sep_l); pal_mod.markerWrite(sep_b[sep_s..@intCast(usize, 9)]); var sep_nl: []const u8 = "\n"; pal_mod.markerWrite(sep_nl); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); self.switch_depth -= @intCast(u32, 1); return type_mod.TYPE_VOID; }
    var cond_type = semanticAnalyzerResolveExpr(self, node.child_0);
    self.current_switch_cond_tu = @intCast(u32, 0);
    var cond_es: u32 = @intCast(u32, 0);
    if (cond_type != @intCast(u32, 0) and cond_type != type_mod.TYPE_VOID) {
        var cond_ty = self.registry.types_items[@intCast(usize, cond_type)];
        if (cond_ty.kind == type_mod.TypeKind.tagged_union_type) {
            self.current_switch_cond_tu = cond_type;
            var rs: []const u8 = "Z"; pal_mod.markerWrite(rs);
        } else if (cond_ty.kind == type_mod.TypeKind.error_set_type) {
            cond_es = cond_type;
            var swes_m: []const u8 = "SWES:e"; pal_mod.markerWriteInt(swes_m, cond_es);
            var swes_nl: []const u8 = "\n"; pal_mod.markerWrite(swes_nl);
        } else if (cond_ty.kind == type_mod.TypeKind.error_union_type) {
            var cond_eu = self.registry.eu_items[@intCast(usize, cond_ty.payload_idx)];
            cond_es = cond_eu.error_set;
            var sweu_m: []const u8 = "SWEU:e"; pal_mod.markerWriteInt(sweu_m, cond_es);
            var sweu_nl: []const u8 = "\n"; pal_mod.markerWrite(sweu_nl);
        }
    }
    var prongs = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (prongs.len == @intCast(usize, 0)) { var pr0_m: []const u8 = "PL0:n"; pal_mod.markerWrite(pr0_m); var pr0_b: [10]u8 = undefined; var pr0_l = itoa_mod.itoa(node_idx, pr0_b[0..]); var pr0_s: usize = @intCast(usize, 9) - @intCast(usize, pr0_l); pal_mod.markerWrite(pr0_b[pr0_s..@intCast(usize, 9)]); var pr0_nl: []const u8 = "\n"; pal_mod.markerWrite(pr0_nl); self.current_switch_cond_tu = @intCast(u32, 0); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); self.switch_depth -= @intCast(u32, 1); return type_mod.TYPE_VOID; }
    var unified: u32 = @intCast(u32, 0);
    var unified_node: u32 = @intCast(u32, 0);
    var has_else: u8 = 0;
    var i: usize = 0;

    while (i < prongs.len) : (i += 1) {
        var prong = self.store.nodes.items[@intCast(usize, prongs[i])];
        if ((prong.flags & @intCast(u8, 1)) != @intCast(u8, 0)) has_else = 1;
        if ((prong.flags & @intCast(u8, 1)) != @intCast(u8, 0) and (prong.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
            var swec_msg: []const u8 = "switch else-prong capture (else => |capture|) is not supported";
            _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3001), self.source_file_id, node_idx, node_idx, swec_msg);
            return type_mod.TYPE_VOID;
        }
        var pct = self.current_switch_cond_tu; var pp = prong.payload;
        var pct_m2: []const u8 = "PCT:C"; pal_mod.markerWriteInt(pct_m2, pct);
        var ppt_m: []const u8 = "PCT:P"; pal_mod.markerWriteInt(ppt_m, pp);
        if (self.current_switch_cond_tu != @intCast(u32, 0) and prong.payload != @intCast(u32, 0)) {
            var case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong.payload);
            var ci: usize = 0;
            while (ci < case_ec.len) : (ci += 1) {
                var case_node = self.store.nodes.items[@intCast(usize, case_ec[ci])];
                var cc_val = @intCast(u32, @enumToInt(case_node.kind));
                var cc_m: []const u8 = "CC:K"; pal_mod.markerWriteInt(cc_m, cc_val);
                    if (case_node.kind == AstKind.enum_literal) {
                        _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                    } else if (case_node.kind == AstKind.undefined_literal) {
                        _ = semanticAnalyzerResolveEnumLiteral(self, @intCast(u32, case_ec[ci]));
                    }
            }
            if ((prong.flags & @intCast(u8, 16)) != @intCast(u8, 0)) {
                var cap_name = prong.child_1;
                var sce_pm: []const u8 = "SCE:p"; pal_mod.markerWriteInt(sce_pm, cap_name);
                var sce_lm: []const u8 = "SCE:l"; pal_mod.markerWriteInt(sce_lm, @intCast(u32, case_ec.len));
                if (case_ec.len > @intCast(usize, 0)) {
                    var ev = hash_mod.u32ToU32MapGet(self.enum_value_table, case_ec[0]);
                    if (ev) |idx| {
                        var tu_ty = self.registry.types_items[@intCast(usize, self.current_switch_cond_tu)];
                        var tp = self.registry.tu_items[@intCast(usize, tu_ty.payload_idx)];
                        var fe: type_mod.FieldEntry = self.registry.fe_items[@intCast(usize, tp.fields_start) + @intCast(usize, idx)];
                        var scfe_nm: []const u8 = "SCFE:n"; pal_mod.markerWriteInt(scfe_nm, cap_name);
                        var scfe_tm: []const u8 = "SCFE:t"; pal_mod.markerWriteInt(scfe_tm, fe.type_id);
                        var scfe_km: []const u8 = "SCFE:k"; pal_mod.markerWriteInt(scfe_km, @intCast(u32, @enumToInt(tu_ty.kind)));
                        if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
                        self.local_decl_names[self.local_decl_count] = cap_name;
                        self.local_decl_types[self.local_decl_count] = fe.type_id;
                        self.local_decl_count += @intCast(usize, 1);
                        var scax_m: []const u8 = "SCAX:N"; pal_mod.markerWriteInt(scax_m, cap_name);
                        var scax_tm: []const u8 = "SCAX:T"; pal_mod.markerWriteInt(scax_tm, fe.type_id);
                    }
                } else {
                    var sce_rm: []const u8 = "SCE:R"; pal_mod.markerWriteInt(sce_rm, cap_name);
                    registerLocalDecl(self, cap_name, self.current_switch_cond_tu);
                }
            }
        }
        if (cond_es != @intCast(u32, 0) and prong.payload != @intCast(u32, 0)) {
            var es_case_ec = ast_mod.astStoreGetExtraChildren(self.store, prong.payload);
            var es_ci: usize = 0;
            while (es_ci < es_case_ec.len) : (es_ci += 1) {
                var es_case_node = self.store.nodes.items[@intCast(usize, es_case_ec[es_ci])];
                if (es_case_node.kind == AstKind.error_literal) {
                    pushExpectedType(self, cond_es);
                    _ = semanticAnalyzerResolveExpr(self, @intCast(u32, es_case_ec[es_ci]));
                    popExpectedType(self);
                }
            }
        }
         var pbd_b0 = prong.child_0;
         var pbd_k0: u32 = @intCast(u32, 0);
         if (pbd_b0 != @intCast(u32, 0)) { var pbd_n = self.store.nodes.items[@intCast(usize, pbd_b0)]; pbd_k0 = @intCast(u32, @enumToInt(pbd_n.kind)); }
         var pbd_nm: []const u8 = "PBD:N"; pal_mod.markerWriteInt(pbd_nm, pbd_b0);
         var pbd_km: []const u8 = "PBD:K"; pal_mod.markerWriteInt(pbd_km, pbd_k0);
          var saved_tu = self.current_switch_cond_tu;
          var bt = semanticAnalyzerResolveExpr(self, prong.child_0);
         self.current_switch_cond_tu = saved_tu;
        var pct_m: []const u8 = "PCT:n"; pal_mod.markerWriteInt(pct_m, prong.child_0); var pct_bm: []const u8 = "PCT:b"; pal_mod.markerWriteInt(pct_bm, bt); var pct_fm: []const u8 = "PCT:f"; pal_mod.markerWriteInt(pct_fm, self.current_fn_return);
        var swpb_im: []const u8 = "SWPB:i"; pal_mod.markerWriteInt(swpb_im, @intCast(u32, i)); var swpb_tm: []const u8 = "SWPB:t"; pal_mod.markerWriteInt(swpb_tm, bt);
        if (bt == type_mod.TYPE_NORETURN) {}
        else if (unified == @intCast(u32, 0)) { unified = bt; unified_node = prong.child_0; }
        else if (bt == unified) {}
        else if (coercion_mod.classifyCoercion(self.registry, bt, unified) != coercion_mod.CoercionKind.none) {
            tryRecordCoercion(self, prong.child_0, bt, unified);
        }
        else if (coercion_mod.classifyCoercion(self.registry, unified, bt) != coercion_mod.CoercionKind.none) {
            tryRecordCoercion(self, unified_node, unified, bt);
            unified = bt;
            unified_node = prong.child_0;
        }

        else {
            var unum: u32 = @intCast(u32, 0);
            if (type_mod.typeRegistryIsNumeric(self.registry, bt)) { unum = @intCast(u32, 1); }
            if (unified == type_mod.TYPE_INT_LIT and unum != @intCast(u32, 0)) { unified = bt; }
            else { var mix_pm: []const u8 = "MIX:P"; pal_mod.markerWriteInt(mix_pm, @intCast(u32, i)); var mix_um: []const u8 = "MIX:U"; pal_mod.markerWriteInt(mix_um, unified); var mix_bm: []const u8 = "MIX:B"; pal_mod.markerWriteInt(mix_bm, bt); var mix_tk_m: []const u8 = "MIX:tk"; var mix_tk_v: u32 = @intCast(u32, @enumToInt(self.registry.types_items[@intCast(usize, bt)].kind)); pal_mod.markerWriteInt(mix_tk_m, mix_tk_v); var mix_uk_m: []const u8 = "MIX:uk"; var mix_uk_v: u32 = @intCast(u32, @enumToInt(self.registry.types_items[@intCast(usize, unified)].kind)); pal_mod.markerWriteInt(mix_uk_m, mix_uk_v); var mix_cd_m: []const u8 = "MIX:cd"; pal_mod.markerWriteInt(mix_cd_m, node.child_0); var mix_b_m: []const u8 = "MIX:b"; pal_mod.markerWriteInt(mix_b_m, prong.child_0); var mix_pf_m: []const u8 = "MIX:pf"; pal_mod.markerWriteInt(mix_pf_m, @intCast(u32, prong.flags)); var mix_pn_m: []const u8 = "MIX:pn"; pal_mod.markerWriteInt(mix_pn_m, @intCast(u32, prongs.len)); var mix_ni_m: []const u8 = "MIX:ni"; pal_mod.markerWriteInt(mix_ni_m, node_idx); rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
        }
    }

    self.current_switch_cond_tu = @intCast(u32, 0);
    if (has_else == @intCast(u8, 0)) {
    }
    if (unified == @intCast(u32, 0)) unified = type_mod.TYPE_VOID;
    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, unified);
    var swu_m: []const u8 = "SWU:n"; pal_mod.markerWriteInt(swu_m, node_idx); var swu_tm: []const u8 = "SWU:t"; pal_mod.markerWriteInt(swu_tm, unified);
    self.switch_depth -= @intCast(u32, 1);
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
        var rxs_nm: []const u8 = "RXS:n"; pal_mod.markerWriteInt(rxs_nm, node_idx);
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
        if (self.expected_type_stack_len > 0) {
            var top = self.expected_type_stack_items[self.expected_type_stack_len - 1];
            if (top != 0) {
                var es: u32 = 0;
                var tty = self.registry.types_items[@intCast(usize, top)];
                var eff_top: u32 = top;
                if (tty.kind == type_mod.TypeKind.optional_type) {
                    var opt_pay = self.registry.opt_items[@intCast(usize, tty.payload_idx)].payload;
                    tty = self.registry.types_items[@intCast(usize, opt_pay)];
                    eff_top = opt_pay;
                }
                if (tty.kind == type_mod.TypeKind.error_set_type) { es = eff_top; }
                else if (tty.kind == type_mod.TypeKind.error_union_type) { es = self.registry.eu_items[@intCast(usize, tty.payload_idx)].error_set; }
                if (es != 0) {
                    var name_id: u32 = node.payload;
                    var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, es, name_id);
                    if (ord != @intCast(u32, 0xFFFFFFFF)) {
                        var reg_code = hash_mod.u32ToU32MapGetOrAddDense(self.error_code_registry, name_id);
                        hash_mod.u32ToU32MapPut(self.enum_value_table, node_idx, reg_code);
                        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, es);
                        result = es;
                    } else {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var eln_msg: []const u8 = "error literal not found in error set";
                        _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3011_ERROR_LITERAL_NOT_IN_SET)), self.source_file_id, sp, ep, eln_msg);
                        result = type_mod.TYPE_VOID;
                    }
                } else if (tty.kind == type_mod.TypeKind.error_union_type) {
                    rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, eff_top);
                    result = eff_top;
                } else { result = type_mod.TYPE_VOID; }
            } else { result = type_mod.TYPE_VOID; }
        } else { result = type_mod.TYPE_VOID; }
    } else if (node.kind == AstKind.ident_expr) {
        result = semanticAnalyzerResolveIdent(self, self.module_id, self.store.identifiers.items[@intCast(usize, node.payload)], node_idx);
    } else if (node.kind == AstKind.field_access) {
        result = semanticAnalyzerResolveFieldAccess(self, node_idx);
        var fad: []const u8 = "FAD:R"; pal_mod.markerWriteInt(fad, result);
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
        if (node.child_0 == self.size_of_name_id or node.child_0 == self.align_of_name_id) {
            if (ec.len >= @intCast(usize, 1)) {
                var so_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                _ = type_resolver.resolveTypeExprFull(&so_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
            }
            result = type_mod.TYPE_INT_LIT;
        } else if (ec.len >= @intCast(usize, 2)) {
            if (semanticAnalyzerIsTypeValueCast(self, node.child_0)) {
                _ = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 1)]);
                var tre_env = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                result = type_resolver.resolveTypeExprFull(&tre_env, ec[@intCast(usize, 0)], @intCast(u32, 0));
            } else if (node.child_0 == self.ptrtoint_name_id) {
                var ec2 = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
                if (ec2.len >= 1) { _ = semanticAnalyzerResolveExpr(self, ec2[0]); }
                result = type_mod.TYPE_USIZE;
            } else {
                result = semanticAnalyzerResolveExpr(self, ec[0]);
            }
        } else if (ec.len >= @intCast(usize, 1)) {
            result = semanticAnalyzerResolveExpr(self, ec[0]);
        } else {
            result = type_mod.TYPE_VOID;
        }
    } else if (node.kind == AstKind.bool_not) {
        _ = semanticAnalyzerResolveExpr(self, node.child_0);
        result = type_mod.TYPE_BOOL;
    } else if (node.kind == AstKind.negate) {
        result = semanticAnalyzerResolveNegate(self, node_idx);
    } else if (node.kind == AstKind.bit_not) {
        result = semanticAnalyzerResolveBitNot(self, node_idx);
    } else if (node.kind == AstKind.try_expr) {
        result = semanticAnalyzerResolveTryExpr(self, node_idx);
    } else if (node.kind == AstKind.catch_expr) {
        var catch_es: u32 = 0; result = semanticAnalyzerResolveExpr(self, node.child_0);
        if (result != type_mod.TYPE_UNDEFINED) {
            var clt = self.registry.types_items[@intCast(usize, result)];
            if (clt.kind == type_mod.TypeKind.error_union_type) {
                catch_es = self.registry.eu_items[@intCast(usize, clt.payload_idx)].error_set; result = self.registry.eu_items[@intCast(usize, clt.payload_idx)].payload;
                coercion_mod.coercionTableAdd(self.coercion_table, node.child_0, coercion_mod.CoercionKind.unwrap_optional, result);
            }
        }
        if (node.child_2 != 0) {
            var capture_node = self.store.nodes.items[@intCast(usize, node.child_2)];
            if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
            self.local_decl_names[self.local_decl_count] = capture_node.payload;
            self.local_decl_types[self.local_decl_count] = if (catch_es != 0) catch_es else type_mod.TYPE_I32;
            self.local_decl_count += @intCast(usize, 1);
        }
        if (node.child_1 != @intCast(u32, 0)) {
            if (catch_es != 0) {
                var child1 = self.store.nodes.items[@intCast(usize, node.child_1)];
                if (child1.kind == AstKind.error_literal) {
                    pushExpectedType(self, catch_es);
                    _ = semanticAnalyzerResolveExpr(self, node.child_1);
                    popExpectedType(self);
                }
            }
            semanticAnalyzerStmtWorkPush(self, node.child_1);
        }
    } else if (node.kind == AstKind.orelse_expr) {
        result = semanticAnalyzerResolveOrelseExpr(self, node_idx);
     } else if (node.kind == AstKind.break_stmt or node.kind == AstKind.continue_stmt) {
         result = type_mod.TYPE_VOID;
     } else if (node.kind == AstKind.var_decl or node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt) {
         semanticAnalyzerResolveStmtIter(self, node_idx);
         result = type_mod.TYPE_VOID;
      } else if (node.kind == AstKind.if_expr) {
          result = semanticAnalyzerResolveIfExpr(self, node_idx);
      } else if (node.kind == AstKind.if_stmt) {
          semanticAnalyzerResolveIfHeader(self, node_idx);
          if (node.child_2 != @intCast(u32, 0)) { semanticAnalyzerStmtWorkPush(self, node.child_2); }
          if (node.child_1 != @intCast(u32, 0)) { semanticAnalyzerStmtWorkPush(self, node.child_1); }
          result = type_mod.TYPE_VOID;
       } else if (node.kind == AstKind.for_stmt) {
           semanticAnalyzerResolveForHeader(self, node_idx);
           if (node.child_1 != 0) { semanticAnalyzerStmtWorkPush(self, node.child_1); }
           result = type_mod.TYPE_VOID;
      } else if (node.kind == AstKind.while_stmt) {
          semanticAnalyzerResolveWhileHeader(self, node_idx);
          if (node.child_1 != 0) { semanticAnalyzerStmtWorkPush(self, node.child_1); }
          result = type_mod.TYPE_VOID;
      } else if (node.kind == AstKind.swt_ex) {
        result = semanticAnalyzerResolveSwitchExpr(self, node_idx);
    } else if (node.kind == AstKind.tuple_literal) {
        result = semanticAnalyzerResolveTupleLiteral(self, node_idx);
    } else if (node.kind == AstKind.struct_init) {
        result = semanticAnalyzerResolveStructInit(self, node_idx);
    } else if (node.kind == AstKind.array_init) {
        var ai_dbg: []const u8 = "AW:R"; pal_mod.markerWriteInt(ai_dbg, result);
        result = semanticAnalyzerResolveArrayInit(self, node_idx);
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
        resolveReturnStmt(self, node_idx);
        result = type_mod.TYPE_NORETURN;
    } else if (node.kind == AstKind.expr_stmt) {
        result = semanticAnalyzerResolveExpr(self, node.child_0);
    } else if (node.kind == AstKind.import_expr) {
        result = type_mod.TYPE_VOID;
     } else if (node.kind == AstKind.block) {
          var eblk_m: []const u8 = "EBLK:N"; pal_mod.markerWriteInt(eblk_m, node_idx);
          var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
          var eblk_cm: []const u8 = "EBLK:C"; pal_mod.markerWriteInt(eblk_cm, @intCast(u32, children.len));
         if (children.len > @intCast(usize, 0)) {
             var si: usize = 0;
             while (si < children.len - @intCast(usize, 1)) : (si += 1) {
                 var eblk_sm: []const u8 = "EBLK:S"; pal_mod.markerWriteInt(eblk_sm, @intCast(u32, si));
                 var eblk_cm2: []const u8 = "EBLK:D"; pal_mod.markerWriteInt(eblk_cm2, children[si]);
                 semanticAnalyzerResolveStmtIter(self, children[si]);
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
    } else if (node.kind == AstKind.range_exclusive or node.kind == AstKind.range_inclusive) {
        rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_U32);
        return type_mod.TYPE_U32;
     } else {
          var st_m: []const u8 = "ST:N"; pal_mod.markerWriteInt(st_m, node_idx);
          var st_kv: u32 = @intCast(u32, @enumToInt(node.kind)); var st_km: []const u8 = "ST:K"; pal_mod.markerWriteInt(st_km, st_kv);
           var unr_msg: []const u8 = "internal error: unhandled node kind in type resolution";
           _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3020), self.source_file_id, node_idx, node_idx, unr_msg);
           return type_mod.TYPE_VOID;
     }

    var stx_m: []const u8 = "STX:n"; pal_mod.markerWriteInt(stx_m, node_idx);
    var stx_kv: u32 = @intCast(u32, @enumToInt(node.kind)); var stx_km: []const u8 = "STX:k"; pal_mod.markerWriteInt(stx_km, stx_kv);
    var stx_rm: []const u8 = "STX:r"; pal_mod.markerWriteInt(stx_rm, result);
     var a4_nm: []const u8 = "A4:N"; pal_mod.markerWriteInt(a4_nm, node_idx);
     var a4_kv: u32 = @intCast(u32, @enumToInt(node.kind)); var a4_km: []const u8 = "A4:K"; pal_mod.markerWriteInt(a4_km, a4_kv);
     var a4_rm: []const u8 = "A4:R"; pal_mod.markerWriteInt(a4_rm, result);
     rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, result);
     var stb_nm: []const u8 = "STB:N"; pal_mod.markerWriteInt(stb_nm, node_idx);
     var stb_rm: []const u8 = "STB:R"; pal_mod.markerWriteInt(stb_rm, result);
    return result;
}

pub fn semanticAnalyzerResolveFnBody(self: *SemanticAnalyzer, fn_decl_node: u32) void {
     var fb: []const u8 = "FB"; pal_mod.markerWrite(fb);
     self.local_decl_count = @intCast(usize, 0);
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
                var rtp_m: []const u8 = "RT:P"; pal_mod.markerWriteInt(rtp_m, pnode.payload);
                var rta_m: []const u8 = "RT:A"; pal_mod.markerWriteInt(rta_m, pnode.child_0);
                var rt = rtt_mod.resolvedTypeTableGet(self.type_table, pnode.child_0);
                if (rt) |t| {
                    var rth_m: []const u8 = "RT:T"; pal_mod.markerWriteInt(rth_m, t);
                    self.local_decl_types[self.local_decl_count] = t;
                } else {
                    var rtm2: []const u8 = "RT:M\n"; pal_mod.markerWrite(rtm2);
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
    var vm: []const u8 = "EVC:N"; pal_mod.markerWriteInt(vm, @intCast(u32, evcnt));
    var vcm: []const u8 = "EVC:C"; pal_mod.markerWriteInt(vcm, @intCast(u32, evcap));
}

fn semanticAnalyzerStmtWorkPush(self: *SemanticAnalyzer, node_idx: u32) void {
    if (self.stmt_work_len >= self.stmt_work_cap) {
        var new_cap: usize = if (self.stmt_work_cap < @intCast(usize, 64)) @intCast(usize, 64) else self.stmt_work_cap * @intCast(usize, 2);
        var raw = alloc_mod.sandAlloc(self.expected_type_stack_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
        var ndst = @ptrCast([*]u32, raw);
        var ci: usize = 0;
        while (ci < self.stmt_work_len) : (ci += @intCast(usize, 1)) {
            ndst[ci] = self.stmt_work_items[ci];
        }
        self.stmt_work_items = ndst;
        self.stmt_work_cap = new_cap;
    }
    self.stmt_work_items[self.stmt_work_len] = node_idx;
    self.stmt_work_len += @intCast(usize, 1);
}

pub fn pushExpectedType(self: *SemanticAnalyzer, ty: u32) void {
    if (self.expected_type_stack_len >= self.expected_type_stack_cap) {
        var new_cap: usize = if (self.expected_type_stack_cap < @intCast(usize, 64)) @intCast(usize, 64) else self.expected_type_stack_cap * @intCast(usize, 2);
        var raw = alloc_mod.sandAlloc(self.expected_type_stack_alloc, @intCast(usize, 4) * new_cap, @intCast(usize, 4)) catch unreachable;
        var ndst = @ptrCast([*]u32, raw);
        var ci: usize = 0;
        while (ci < self.expected_type_stack_len) : (ci += @intCast(usize, 1)) {
            ndst[ci] = self.expected_type_stack_items[ci];
        }
        self.expected_type_stack_items = ndst;
        self.expected_type_stack_cap = new_cap;
    }
    self.expected_type_stack_items[self.expected_type_stack_len] = ty;
    self.expected_type_stack_len += @intCast(usize, 1);
}

pub fn popExpectedType(self: *SemanticAnalyzer) void {
    if (self.expected_type_stack_len > @intCast(usize, 0)) {
        self.expected_type_stack_len -= @intCast(usize, 1);
    }
}

pub fn topExpectedType(self: *SemanticAnalyzer) u32 {
    if (self.expected_type_stack_len == @intCast(usize, 0)) return @intCast(u32, 0);
    return self.expected_type_stack_items[self.expected_type_stack_len - @intCast(usize, 1)];
}

fn semanticAnalyzerResolveIfHeader(self: *SemanticAnalyzer, node_idx: u32) void {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var icond_t = semanticAnalyzerResolveExpr(self, node.child_0);
    if (node.payload != @intCast(u32, 0)) {
        var icap_node = self.store.nodes.items[@intCast(usize, node.payload)];
        if (icap_node.kind == AstKind.if_capture) {
            registerLocalDecl(self, icap_node.payload, semanticAnalyzerCaptureType(self, icond_t));
        }
    }
    var ifs_b: [1]u32 = [1]u32{node.child_1};
    var ifs_k: [1]u32 = [1]u32{@intCast(u32, 0)};
    if (ifs_b[0] != @intCast(u32, 0)) { var ifs_cn = self.store.nodes.items[@intCast(usize, ifs_b[0])]; ifs_k[0] = @intCast(u32, @enumToInt(ifs_cn.kind)); }
    var ifst_nm: []const u8 = "IFST:N"; pal_mod.markerWriteInt(ifst_nm, node_idx);
    var ifst_cm: []const u8 = "IFST:C"; pal_mod.markerWriteInt(ifst_cm, ifs_b[0]);
    var ifst_km: []const u8 = "IFST:K"; pal_mod.markerWriteInt(ifst_km, ifs_k[0]);
    var ifst_c2m: []const u8 = "IFST:2"; pal_mod.markerWriteInt(ifst_c2m, node.child_2);
    var ifs_k2: [1]u32 = [1]u32{@intCast(u32, 0)};
    if (node.child_2 != @intCast(u32, 0)) { var ifs_cn2 = self.store.nodes.items[@intCast(usize, node.child_2)]; ifs_k2[0] = @intCast(u32, @enumToInt(ifs_cn2.kind)); }
    var ifst_k2m: []const u8 = "IFST:K2"; pal_mod.markerWriteInt(ifst_k2m, ifs_k2[0]);
}

fn semanticAnalyzerResolveForHeader(self: *SemanticAnalyzer, node_idx: u32) void {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    _ = semanticAnalyzerResolveExpr(self, node.child_0);
    var fs_c_m: []const u8 = "FS:C"; pal_mod.markerWriteInt(fs_c_m, node.child_0);
    var cnode = self.store.nodes.items[@intCast(usize, node.child_0)];
    var fs_ck_m: []const u8 = "FS:CK"; pal_mod.markerWriteInt(fs_ck_m, @intCast(u32, @enumToInt(cnode.kind)));
    var it_tid = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
    if (it_tid) |tid| {
        var fs_tid_m: []const u8 = "FS:T"; pal_mod.markerWriteInt(fs_tid_m, tid);
        var ty = self.registry.types_items[@intCast(usize, tid)];
        var elem_box: [1]u32 = [1]u32{type_mod.TYPE_UNDEFINED};
        if (ty.kind == type_mod.TypeKind.slice_type) { elem_box[0] = self.registry.slice_items[@intCast(usize, ty.payload_idx)].elem; }
        else if (ty.kind == type_mod.TypeKind.array_type) { elem_box[0] = self.registry.array_items[@intCast(usize, ty.payload_idx)].elem; }
        else if (cnode.kind == AstKind.range_exclusive or cnode.kind == AstKind.range_inclusive) { elem_box[0] = tid; }
        if (node.payload != @intCast(u32, 0) and elem_box[0] != type_mod.TYPE_UNDEFINED) {
            var fs_p_m: []const u8 = "FS:P"; pal_mod.markerWriteInt(fs_p_m, node.payload);
            var fs_e_m: []const u8 = "FS:E"; pal_mod.markerWriteInt(fs_e_m, elem_box[0]);
            if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
            self.local_decl_names[self.local_decl_count] = node.payload; self.local_decl_types[self.local_decl_count] = elem_box[0]; self.local_decl_count += @intCast(usize, 1);
            var d4f_n: []const u8 = "D4F:N"; pal_mod.markerWriteInt(d4f_n, node.payload);
            var d4f_t: []const u8 = "D4F:T"; pal_mod.markerWriteInt(d4f_t, elem_box[0]);
        }
    } else {
        var a5_m: []const u8 = "FS:M\n"; pal_mod.markerWrite(a5_m);
    }
    if (node.child_2 != @intCast(u32, 0)) {
        if (self.local_decl_count >= self.local_decl_cap) { semanticAnalyzerGrowLocalDecls(self); }
        self.local_decl_names[self.local_decl_count] = node.child_2; self.local_decl_types[self.local_decl_count] = type_mod.TYPE_USIZE; self.local_decl_count += @intCast(usize, 1);
        var f2_m: []const u8 = "FIX2:LN"; pal_mod.markerWriteInt(f2_m, node.child_2);
    }
}

fn semanticAnalyzerResolveWhileHeader(self: *SemanticAnalyzer, node_idx: u32) void {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    if (node.child_1 != @intCast(u32, 0)) {
        var ws_node = self.store.nodes.items[@intCast(usize, node.child_1)];
        var wst_nm: []const u8 = "WST:N"; pal_mod.markerWriteInt(wst_nm, node_idx);
        var wst_km: []const u8 = "WST:K"; pal_mod.markerWriteInt(wst_km, @intCast(u32, @enumToInt(ws_node.kind)));
    }
    var wcond_t = semanticAnalyzerResolveExpr(self, node.child_0);
    if (node.payload != @intCast(u32, 0)) {
        var wcap_node = self.store.nodes.items[@intCast(usize, node.payload)];
        if (wcap_node.kind == AstKind.while_capture) {
            registerLocalDecl(self, wcap_node.payload, semanticAnalyzerCaptureType(self, wcond_t));
        }
    }
}

pub fn semanticAnalyzerResolveStmtIter(self: *SemanticAnalyzer, root_node: u32) void {
    var sp_base: usize = self.stmt_work_len;
    semanticAnalyzerStmtWorkPush(self, root_node);
    while (self.stmt_work_len > sp_base) {
        self.stmt_work_len -= @intCast(usize, 1);
        var node_idx = self.stmt_work_items[self.stmt_work_len];
        if (node_idx == @intCast(u32, 0)) { continue; }
        var node = self.store.nodes.items[@intCast(usize, node_idx)];
        var sp_m: []const u8 = "SP:n"; pal_mod.markerWriteInt(sp_m, @intCast(u32, self.stmt_work_len));
        var spk_m: []const u8 = "SP:K"; pal_mod.markerWriteInt(spk_m, @intCast(u32, @enumToInt(node.kind)));
        if (node.kind == AstKind.block) {
            var children = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
            var blk_nm: []const u8 = "BLK:N"; pal_mod.markerWriteInt(blk_nm, node_idx);
            var blk_cm: []const u8 = "BLK:C"; pal_mod.markerWriteInt(blk_cm, @intCast(u32, children.len));
            var i: usize = children.len;
            while (i > @intCast(usize, 0)) : (i -= @intCast(usize, 1)) {
                var ci = children[i - @intCast(usize, 1)];
                var bc_m: []const u8 = "BCK:B"; pal_mod.markerWriteInt(bc_m, node_idx);
                var bc_im: []const u8 = "BCK:I"; pal_mod.markerWriteInt(bc_im, @intCast(u32, i - @intCast(usize, 1)));
                var bc_nm: []const u8 = "BCK:N"; pal_mod.markerWriteInt(bc_nm, ci);
                var cnode_k = self.store.nodes.items[@intCast(usize, ci)].kind;
                var bc_km: []const u8 = "BCK:K"; pal_mod.markerWriteInt(bc_km, @intCast(u32, @enumToInt(cnode_k)));
                semanticAnalyzerStmtWorkPush(self, ci);
            }
            var bcej: []const u8 = "]\n"; pal_mod.markerWrite(bcej);
        } else if (node.kind == AstKind.var_decl) {
            if (node.payload == @intCast(u32, 55)) {
                var d10n_m: []const u8 = "D10:C0"; pal_mod.markerWriteInt(d10n_m, node.child_0);
                var d10c_m: []const u8 = "D10:C1"; pal_mod.markerWriteInt(d10c_m, node.child_1);
                if (node.child_1 != @intCast(u32, 0)) {
                    var inode = self.store.nodes.items[@intCast(usize, node.child_1)];
                    var d10k_m: []const u8 = "D10:IK"; pal_mod.markerWriteInt(d10k_m, @intCast(u32, @enumToInt(inode.kind)));
                }
            }
            var vd_m: []const u8 = "VD:N"; pal_mod.markerWriteInt(vd_m, node.payload);
            var vd2_m: []const u8 = "VD:C"; pal_mod.markerWriteInt(vd2_m, @intCast(u32, self.local_decl_count));
            var decl_type: u32 = @intCast(u32, type_mod.TYPE_UNDEFINED);
            if (node.child_0 != @intCast(u32, 0)) {
                var ann = self.store.nodes.items[@intCast(usize, node.child_0)];
                if (ann.kind == AstKind.ident_expr) { decl_type = semanticAnalyzerResolveExpr(self, node.child_0); }
                else {
                    var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
                    if (rt) |t| { decl_type = t; }
                    else {
                        var tre_env_vd = type_resolver.TypeResolveEnv{ .store = self.store, .typereg = self.registry, .symbol_reg = self.symbols, .interner = self.interner };
                        decl_type = type_resolver.resolveTypeExprFull(&tre_env_vd, node.child_0, @intCast(u32, 0));
                        if (decl_type != type_mod.TYPE_UNDEFINED) {
                            rtt_mod.resolvedTypeTableSet(self.type_table, node.child_0, decl_type);
                        }
                    }
                }
            }
            if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED)) {
                var b1m: []const u8 = "VRT:"; pal_mod.markerWrite(b1m);
                var b1nb: [10]u8 = undefined; var b1nl = itoa_mod.itoa(node.child_0, b1nb[0..]); var b1ns: usize = @intCast(usize, 9) - @intCast(usize, b1nl); pal_mod.markerWrite(b1nb[b1ns..@intCast(usize, 9)]);
                var b1c: []const u8 = ":"; pal_mod.markerWrite(b1c);
                var b1tb: [10]u8 = undefined; var b1tl = itoa_mod.itoa(decl_type, b1tb[0..]); var b1ts: usize = @intCast(usize, 9) - @intCast(usize, b1tl); pal_mod.markerWrite(b1tb[b1ts..@intCast(usize, 9)]);
                var b1nl2: []const u8 = "\n"; pal_mod.markerWrite(b1nl2);
            }
            if (node.child_1 != @intCast(u32, 0)) {
                var init_node = self.store.nodes.items[@intCast(usize, node.child_1)];
                var ik_m: []const u8 = "I:K"; pal_mod.markerWriteInt(ik_m, @intCast(u32, @enumToInt(init_node.kind)));
                var vd_exp = if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED)) decl_type else @intCast(u32, 0);
                pushExpectedType(self, vd_exp);
                var it = semanticAnalyzerResolveExpr(self, node.child_1);
                popExpectedType(self);
                if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED) and init_node.kind == AstKind.error_literal) {
                    var name_id: u32 = init_node.payload;
                    var ei: usize = 0;
                    while (ei < self.registry.types_len) : (ei += 1) {
                        if (self.registry.types_items[ei].kind == type_mod.TypeKind.error_set_type) {
                            var ord = type_mod.typeRegistryErrorSetMemberIndex(self.registry, @intCast(u32, ei), name_id);
                            if (ord != @intCast(u32, 0xFFFFFFFF)) {
                                var es_type_id: u32 = @intCast(u32, ei);
                                var reg_code = hash_mod.u32ToU32MapGetOrAddDense(self.error_code_registry, name_id);
                                hash_mod.u32ToU32MapPut(self.enum_value_table, node.child_1, reg_code);
                                rtt_mod.resolvedTypeTableSet(self.type_table, node.child_1, es_type_id);
                                it = es_type_id;
                                break;
                            }
                        }
                    }
                }
                if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED) and init_node.kind == AstKind.enum_literal) {
                    var sp = init_node.span_start;
                    var ep = sp + @intCast(u32, init_node.span_len);
                    var elu_msg: []const u8 = "unable to infer type of enum literal without context";
                    _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3010_CANNOT_INFER_ENUM_LITERAL_TYPE)), self.source_file_id, sp, ep, elu_msg);
                }
                if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED) and it != decl_type) {
                    if (it == type_mod.TYPE_NULL) { var cs4_m: []const u8 = "CS4\n"; pal_mod.markerWrite(cs4_m); }
                    var ck = coercion_mod.classifyCoercion(self.registry, errLitSrcType(self, node.child_1, decl_type, it), decl_type);
                    var ckv_m: []const u8 = "CCK:vr"; pal_mod.markerWriteInt(ckv_m, @intCast(u32, @enumToInt(ck)));
                    if (ck != coercion_mod.CoercionKind.none) {
                        coercion_mod.coercionTableAdd(self.coercion_table, node.child_1, ck, decl_type);
                    } else if (it != type_mod.TYPE_UNDEFINED and !type_mod.typeRegistryIsAssignable(self.registry, it, decl_type)) {
                        var sp = node.span_start;
                        var ep = sp + @intCast(u32, node.span_len);
                        var tmd_msg: []const u8 = "type mismatch in variable declaration — initialization type may not be compatible with declared type";
                        var sk = self.registry.types_items[@intCast(usize, it)].kind;
                        var tk = self.registry.types_items[@intCast(usize, decl_type)].kind;
                        var level: u8 = 1;
                        if (sk == type_mod.TypeKind.error_union_type and tk == type_mod.TypeKind.error_union_type) {
                            var eu_src = self.registry.eu_items[@intCast(usize, self.registry.types_items[@intCast(usize, it)].payload_idx)];
                            var eu_tgt = self.registry.eu_items[@intCast(usize, self.registry.types_items[@intCast(usize, decl_type)].payload_idx)];
                            if (eu_src.error_set == eu_tgt.error_set) {
                                level = 0;
                            }
                        }
                        var di = diag_mod.diagnosticCollectorAdd(self.diag, level, @intCast(u16, 3000),
                            self.source_file_id, sp, ep, tmd_msg);
                        _ = diag_mod.diagnosticCollectorAddNote(self.diag, di, diag_mod.typeKindSrcStr(sk));
                        _ = diag_mod.diagnosticCollectorAddNote(self.diag, di, diag_mod.typeKindTgtStr(tk));
                    }
                }
                if (decl_type == @intCast(u32, type_mod.TYPE_UNDEFINED)) { decl_type = it; }
                if (decl_type == type_mod.TYPE_VOID) {
                    var vdag_m: []const u8 = "VDIAG:void_var\n"; pal_mod.markerWrite(vdag_m);
                    var vfvd_m: []const u8 = "VFLOW:vdag\n"; pal_mod.markerWrite(vfvd_m);
                    var vsp = node.span_start;
                    var vep = vsp + @intCast(u32, node.span_len);
                    var vv_msg: []const u8 = "cannot declare variable of type void";
                    _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, 3000), self.source_file_id, vsp, vep, vv_msg);
                }
                var ct_entry = coercion_mod.coercionTableGet(self.coercion_table, node.child_1);
                if (ct_entry == null) {
                    rtt_mod.resolvedTypeTableSet(self.type_table, node.child_1, decl_type);
                }
            }
            if (self.local_decl_count >= self.local_decl_cap) {
                semanticAnalyzerGrowLocalDecls(self);
            }
            if (decl_type != @intCast(u32, type_mod.TYPE_UNDEFINED)) {
            self.local_decl_names[self.local_decl_count] = node.payload;
            self.local_decl_types[self.local_decl_count] = decl_type;
            self.local_decl_count += @intCast(usize, 1);
            var ck: u64 = @intCast(u64, self.module_id) * @intCast(u64, 4294967296) + @intCast(u64, node.payload);
            type_mod.nameCachePut(self.registry, ck, decl_type);
            var regcp_m: []const u8 = "REG:cp"; pal_mod.markerWriteInt(regcp_m, node.payload);
            var regct_m: []const u8 = "REG:ct"; pal_mod.markerWriteInt(regct_m, decl_type);
            }
        } else if (node.kind == AstKind.if_stmt) {
             semanticAnalyzerResolveIfHeader(self, node_idx);
             if (node.child_2 != @intCast(u32, 0)) {
                 semanticAnalyzerStmtWorkPush(self, node.child_2);
             }
             if (node.child_1 != @intCast(u32, 0)) {
                 semanticAnalyzerStmtWorkPush(self, node.child_1);
             }
          } else if (node.kind == AstKind.while_stmt) {
            semanticAnalyzerResolveWhileHeader(self, node_idx);
            if (node.child_1 != @intCast(u32, 0)) {
                semanticAnalyzerStmtWorkPush(self, node.child_1);
            }
        } else if (node.kind == AstKind.for_stmt) {
             semanticAnalyzerResolveForHeader(self, node_idx);
            if (node.child_1 != @intCast(u32, 0)) {
                semanticAnalyzerStmtWorkPush(self, node.child_1);
            }
        } else if (node.kind == AstKind.return_stmt) {
            resolveReturnStmt(self, node_idx);
        } else if (node.kind == AstKind.plain_assign or
                   node.kind == AstKind.add_assign or node.kind == AstKind.sub_assign or
                   node.kind == AstKind.mul_assign or node.kind == AstKind.div_assign or
                   node.kind == AstKind.mod_assign or node.kind == AstKind.shl_assign or
                   node.kind == AstKind.shr_assign or node.kind == AstKind.and_assign or
                   node.kind == AstKind.or_assign or node.kind == AstKind.xor_assign) {
            _ = semanticAnalyzerResolveExpr(self, node_idx);
        } else if (node.kind == AstKind.defer_stmt or node.kind == AstKind.errdefer_stmt) {
            if (node.child_0 != @intCast(u32, 0)) {
                semanticAnalyzerStmtWorkPush(self, node.child_0);
            }
        } else if (node.kind == AstKind.break_stmt) {
        } else if (node.kind == AstKind.continue_stmt) {
        } else {
            var els_nm: []const u8 = "ELS:n"; pal_mod.markerWriteInt(els_nm, node_idx);
            var els_km: []const u8 = "ELS:k"; pal_mod.markerWriteInt(els_km, @intCast(u32, @enumToInt(node.kind)));
            if (node.child_0 != @intCast(u32, 0)) { var els_c0m: []const u8 = "ELS:c"; pal_mod.markerWriteInt(els_c0m, node.child_0); }
            _ = semanticAnalyzerResolveExpr(self, node_idx);
        }
        if (node.child_0 != @intCast(u32, 0)) {
            var nc = self.store.nodes.items[@intCast(usize, node.child_0)];
            if (nc.kind == AstKind.fn_decl) { continue; }
        }
        if (node.child_1 != @intCast(u32, 0)) {
            var nc = self.store.nodes.items[@intCast(usize, node.child_1)];
            if (nc.kind == AstKind.fn_decl) { continue; }
        }
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
     var ixa_m: []const u8 = "IXA:N"; pal_mod.markerWriteInt(ixa_m, node_idx);
     var node = self.store.nodes.items[@intCast(usize, node_idx)];
     var saved = self._stub_0;
     _ = semanticAnalyzerResolveExpr(self, node.child_1);
     self._stub_0 = semanticAnalyzerResolveExpr(self, node.child_0);
     var c0_node = self.store.nodes.items[@intCast(usize, node.child_0)];
     var c0k_m: []const u8 = "C0K:K"; pal_mod.markerWriteInt(c0k_m, @intCast(u32, @enumToInt(c0_node.kind)));
    if (c0_node.kind == AstKind.ident_expr) {
        var c0_name_id = self.store.identifiers.items[@intCast(usize, c0_node.payload)];
         var ste_m: []const u8 = "STE:N"; pal_mod.markerWriteInt(ste_m, node_idx);
         var src_cur_name = c0_name_id;
        var src_depth: u32 = @intCast(u32, 0);
        var src_name: u32 = @intCast(u32, 0);
        var src_done: u8 = @intCast(u8, 0);
        while (src_done == @intCast(u8, 0) and src_depth < @intCast(u32, 3)) : (src_depth += @intCast(u32, 1)) { src_name = semaTraceStep(self, &src_cur_name, &src_done); }
        if (src_name != @intCast(u32, 0)) {
             var srs_n: []const u8 = "SRC:N"; pal_mod.markerWriteInt(srs_n, node_idx);
             var srs_s: []const u8 = "SRC:S"; pal_mod.markerWriteInt(srs_s, src_name);
             _ = rtt_mod.resolvedSourceTableSet(self.type_table, node.child_0, src_name);
        }
    }
    var ix_m: []const u8 = "IX:T"; pal_mod.markerWriteInt(ix_m, self._stub_0);
    if (self._stub_0 == @intCast(u32, 0) or self._stub_0 == type_mod.TYPE_VOID) { self._stub_0 = saved; rtt_mod.resolvedTypeTableSet(self.type_table, node_idx, type_mod.TYPE_VOID); return type_mod.TYPE_VOID; }
    var bt = self.registry.types_items[@intCast(usize, self._stub_0)];
    var ix_elem = type_mod.typeRegistryIndexedElemType(self.registry, self._stub_0);
    if (ix_elem != type_mod.TYPE_UNDEFINED) {
        var ixr_m: []const u8 = "IX:R"; pal_mod.markerWriteInt(ixr_m, ix_elem);
        self._stub_0 = saved;
        return ix_elem;
    } else if (bt.kind == type_mod.TypeKind.tuple_type) {
        var tp = self.registry.tup_items[@intCast(usize, bt.payload_idx)];
        var r4 = self.registry.xt_items[@intCast(usize, tp.elems_start)];
        var ixr_m: []const u8 = "IX:R"; pal_mod.markerWriteInt(ixr_m, r4);
        self._stub_0 = saved;
        return r4;
    }
    var ret = self._stub_0;
    self._stub_0 = saved;
    return ret;
}

fn semanticAnalyzerResolveSliceExpr(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var saved = self._stub_0;
    self._stub_0 = semanticAnalyzerResolveExpr(self, node.child_0);
    if (node.child_1 != @intCast(u32, 0)) { _ = semanticAnalyzerResolveExpr(self, node.child_1); }
    if (node.child_2 != @intCast(u32, 0)) { _ = semanticAnalyzerResolveExpr(self, node.child_2); }
    if (self._stub_0 == @intCast(u32, 0) or self._stub_0 == type_mod.TYPE_VOID) { self._stub_0 = saved; return type_mod.TYPE_VOID; }
    var bt = self.registry.types_items[@intCast(usize, self._stub_0)];
    self._stub_1 = type_mod.TYPE_VOID;
    var ix_elem2 = type_mod.typeRegistryIndexedElemType(self.registry, self._stub_0);
    if (ix_elem2 != type_mod.TYPE_UNDEFINED) {
        self._stub_1 = ix_elem2;
    } else {
        self._stub_1 = self._stub_0;
    }
    if (self._stub_1 == type_mod.TYPE_VOID) { self._stub_0 = saved; return type_mod.TYPE_VOID; }
    var se_is_const: bool = false;
    if (bt.kind == type_mod.TypeKind.slice_type or bt.kind == type_mod.TypeKind.ptr_type or bt.kind == type_mod.TypeKind.many_ptr_type or bt.kind == type_mod.TypeKind.array_type) {
        if ((bt.flags & @intCast(u8, 1)) != @intCast(u8, 0)) se_is_const = true;
    }
    var ret = type_mod.typeRegistryGetOrCreateSlice(self.registry, self._stub_1, se_is_const);
    self._stub_0 = saved;
    return ret;
}

fn semanticAnalyzerResolveTupleLiteral(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var saved = self._stub_0;
    var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
    if (ec.len == @intCast(usize, 0)) { self._stub_0 = saved; return type_mod.TYPE_VOID; }
    var start: u16 = @intCast(u16, self.registry.xt_len);
    var i: usize = 0;
    while (i < ec.len) : (i += @intCast(usize, 1)) {
        self._stub_0 = semanticAnalyzerResolveExpr(self, ec[i]);
        if (self._stub_0 == type_mod.TYPE_VOID) { self._stub_0 = type_mod.TYPE_I32; }
        type_mod.xtAppend(self.registry, self._stub_0);
    }
    self._stub_0 = saved;
    return type_mod.typeRegistryGetOrCreateTuple(self.registry, start, @intCast(u16, ec.len));
}

fn semanticAnalyzerResolveArrayInit(self: *SemanticAnalyzer, node_idx: u32) u32 {
    var node = self.store.nodes.items[@intCast(usize, node_idx)];
    var saved = self._stub_0;
    if (node.child_0 != @intCast(u32, 0)) {
        var rt = rtt_mod.resolvedTypeTableGet(self.type_table, node.child_0);
        if (rt) |t| {
            var tt = self.registry.types_items[@intCast(usize, t)];
            if (tt.kind == type_mod.TypeKind.array_type) { self._stub_0 = saved; return t; }
        }
    }
     var ec = ast_mod.astStoreGetExtraChildren(self.store, node.payload);
     if (ec.len == @intCast(usize, 0)) { self._stub_0 = saved; return type_mod.TYPE_VOID; }
     var el = self.store.nodes.items[@intCast(usize, ec[@intCast(usize, 0)])];
     self._stub_0 = type_mod.TYPE_VOID;
     if (el.kind == AstKind.char_literal) { self._stub_0 = type_mod.TYPE_U8; }
     else if (el.kind == AstKind.int_literal) { self._stub_0 = type_mod.TYPE_U32; }
     else { self._stub_0 = semanticAnalyzerResolveExpr(self, ec[@intCast(usize, 0)]); }
     if (self._stub_0 == type_mod.TYPE_VOID) { self._stub_0 = saved; return type_mod.TYPE_VOID; }
     var arr_tid = type_mod.typeRegistryGetOrCreateArray(self.registry, self._stub_0, @intCast(u32, ec.len));
     self._stub_0 = saved;
     return arr_tid;
}

pub fn semanticAnalyzerResolveStmt(self: *SemanticAnalyzer, node_idx: u32) void {
    semanticAnalyzerResolveStmtIter(self, node_idx);
}
