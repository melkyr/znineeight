const alloc_mod = @import("allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const diag_mod = @import("diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const ast_mod = @import("ast.zig");
const AstKind = ast_mod.AstKind;
const AstStore = ast_mod.AstStore;
const mr_mod = @import("module_registry.zig");
const ModuleRegistry = mr_mod.ModuleRegistry;
const sym_mod = @import("symbol_table.zig");
const SymbolRegistry = sym_mod.SymbolRegistry;
const type_mod = @import("type_registry.zig");
const TypeRegistry = type_mod.TypeRegistry;
const resolved_type_table = @import("resolved_type_table.zig");
const ResolvedTypeTable = resolved_type_table.ResolvedTypeTable;
const coercion_mod = @import("coercion.zig");
const CoercionTable = coercion_mod.CoercionTable;
const sa_mod = @import("semantic_analyzer.zig");
const type_resolver = @import("type_resolver.zig");
const hash_mod = @import("util/hash.zig");
const pal = @import("pal.zig");

pub const FrontResCtx = struct {
    store: *AstStore,
    typereg: *TypeRegistry,
    symbol_reg: *SymbolRegistry,
    resolved_types: *ResolvedTypeTable,
    module_reg: *ModuleRegistry,
    interner: *StringInterner,
    diag: *DiagnosticCollector,
    scratch: *Sand,
    coercion_table: *CoercionTable,
    enum_value_table: *hash_mod.U32ToU32Map,
    error_code_registry: *hash_mod.U32ToU32Map,
    call_arg_types: *hash_mod.U32ToU32Map,
    call_param_map: *hash_mod.U32ToU32Map,
};

fn resolveTypeExpr(ct: *FrontResCtx, module_id: u32, node_idx: u32) type_mod.TypeId {
    var env = type_resolver.TypeResolveEnv{ .store = ct.store, .typereg = ct.typereg, .symbol_reg = ct.symbol_reg, .interner = ct.interner, .module_id = module_id };
    return type_resolver.resolveTypeExprFull(&env, node_idx, @intCast(u32, 0));
}

fn countUntypedGlobals(ct: *FrontResCtx) u32 {
    var cnt: u32 = 0;
    var ti: usize = 0;
    while (ti < ct.symbol_reg.tables_len) : (ti += 1) {
        var table = ct.symbol_reg.tables_items[ti];
        var si: usize = 0;
        while (si < table.len) : (si += 1) {
            var sym = table.items[si];
            if (sym.type_id != @intCast(u32, 0)) continue;
            if (sym.kind == sym_mod.SymbolKind.global or sym.kind == sym_mod.SymbolKind.type_alias) {
                cnt += 1;
            }
        }
    }
    return cnt;
}

pub fn frontResolveModuleInits(ct: *FrontResCtx) void {
    alloc_mod.sandReset(ct.scratch);
    var bound: u32 = countUntypedGlobals(ct) + @intCast(u32, 1);
    var iter: u32 = 0;
    while (iter < bound) : (iter += 1) {
        var changed: u8 = @intCast(u8, 0);
        var mods = mr_mod.moduleRegistryGetModules(ct.module_reg);
        var mi: usize = 0;
        while (mi < mods.len) : (mi += 1) {
            alloc_mod.sandReset(ct.scratch);
            var ast_root = mods[mi].ast_root;
            if (ast_root == @intCast(u32, 0)) continue;
            var root = ct.store.nodes.items[@intCast(usize, ast_root)];
            var decls = ast_mod.astStoreNodeExtraChildren(ct.store, ast_root);
            var src_fid = mods[mi].source_file_id;
            var sa = sa_mod.semanticAnalyzerInit(ct.scratch, ct.resolved_types, ct.diag, ct.typereg, ct.symbol_reg, ct.store, mods[mi].id, src_fid, ct.coercion_table, ct.enum_value_table, ct.error_code_registry, ct.interner, ct.call_arg_types, ct.call_param_map, &ct.module_reg.path_to_id);
            var di: usize = 0;
            while (di < decls.len) : (di += 1) {
                var decl = ct.store.nodes.items[@intCast(usize, decls[di])];
                if (decl.kind != AstKind.var_decl) continue;
                if (decl.child_0 != @intCast(u32, 0)) {
                    var rtype = resolveTypeExpr(ct, mods[mi].id, decl.child_0);
                    if (rtype != type_mod.TYPE_UNDEFINED) {
                        resolved_type_table.resolvedTypeTableSet(ct.resolved_types, decl.child_0, rtype);
                        resolved_type_table.resolvedTypeTableSet(ct.resolved_types, decls[di], rtype);
                    }
                }
                if (decl.child_1 != @intCast(u32, 0)) {
                    var init = ct.store.nodes.items[@intCast(usize, decl.child_1)];
                    if (init.kind != AstKind.struct_decl and init.kind != AstKind.union_decl) {
                        var init_type = sa_mod.semanticAnalyzerResolveModuleVarDecl(&sa, decls[di]);
                        if (init.kind == AstKind.ident_expr) {
                            if (init_type != type_mod.TYPE_UNDEFINED) {
                                var ck: u64 = @intCast(u64, mods[mi].id) * @intCast(u64, 4294967296) + @intCast(u64, ast_mod.astStoreNodePayload(ct.store, decls[di]));
                                type_mod.nameCachePut(ct.typereg, ck, init_type);
                            }
                        }
                        var vd_existing = resolved_type_table.resolvedTypeTableGet(ct.resolved_types, decls[di]);
                        if (init_type != type_mod.TYPE_VOID and init_type != type_mod.TYPE_UNDEFINED and init_type != type_mod.TYPE_TYPE and vd_existing == null) {
                            resolved_type_table.resolvedTypeTableSet(ct.resolved_types, decls[di], init_type);
                        }
                        if (init_type == type_mod.TYPE_INT_LIT and decl.child_0 != @intCast(u32, 0)) {
                            var mdt2 = resolved_type_table.resolvedTypeTableGet(ct.resolved_types, decl.child_0);
                            if (mdt2) |mt2| {
                                if (mt2 != type_mod.TYPE_UNDEFINED) {
                                    resolved_type_table.resolvedTypeTableSet(ct.resolved_types, decl.child_1, mt2);
                                }
                            }
                        }
                        if (init_type != @intCast(u32, 0) and init_type != type_mod.TYPE_VOID and init_type != type_mod.TYPE_UNDEFINED and init_type != type_mod.TYPE_TYPE) {
                            var name_id: u32 = ast_mod.astStoreNodePayload(ct.store, decls[di]);
                            var sym = sym_mod.symbolRegistryQualifiedLookup(ct.symbol_reg, mods[mi].id, name_id);
                            if (sym) |s| {
                                if (s.type_id == @intCast(u32, 0)) {
                                    s.type_id = init_type;
                                    changed = @intCast(u8, 1);
                                }
                            }
                        }
                    }
                }
            }
        }
        if (changed == @intCast(u8, 0)) { break; }
    }
    alloc_mod.sandReset(ct.scratch);
}

pub fn resolveStmtTypes(ct: *FrontResCtx, module_id: u32, node_idx: u32, depth: u32) void {
    if (depth > @intCast(u32, 16)) return;
    var node = ct.store.nodes.items[@intCast(usize, node_idx)];
    if (node.kind == AstKind.var_decl) {
        if (node.child_0 != 0) {
            var rtype = resolveTypeExpr(ct, module_id, node.child_0);
            if (rtype != type_mod.TYPE_UNDEFINED) {
                resolved_type_table.resolvedTypeTableSet(ct.resolved_types, node.child_0, rtype);
                resolved_type_table.resolvedTypeTableSet(ct.resolved_types, node_idx, rtype);
            }
        }
    }
    if (node.kind == AstKind.array_init or node.kind == AstKind.struct_init or node.kind == AstKind.tuple_literal) {
        if (node.child_0 != 0) {
            var rtype = resolveTypeExpr(ct, module_id, node.child_0);
            if (rtype != type_mod.TYPE_UNDEFINED) {
                resolved_type_table.resolvedTypeTableSet(ct.resolved_types, node.child_0, rtype);
            }
        }
    }
    if (node.kind == AstKind.block) {
        var decls = ast_mod.astStoreNodeExtraChildren(ct.store, node_idx);
        var di: usize = 0;
        while (di < decls.len) : (di += 1) {
            resolveStmtTypes(ct, module_id, decls[di], depth + @intCast(u32, 1));
        }
    }
    var cd = depth + @intCast(u32, 1);
    if (node.kind != AstKind.builtin_call) {
        if (node.child_0 != 0) { resolveStmtTypes(ct, module_id, node.child_0, cd); }
        if (node.child_1 != 0) { resolveStmtTypes(ct, module_id, node.child_1, cd); }
    }
}
