const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const mr_mod = @import("module_registry.zig");
const pal_mod = @import("pal.zig");
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const ast_mod = @import("ast.zig");
const interner_mod = @import("string_interner.zig");
const diag_mod = @import("diagnostics.zig");
const sm_mod = @import("source_manager.zig");
const ga_mod = @import("growable_array.zig");
const AstKind = @import("ast.zig").AstKind;
const ce_mod = @import("comptime_eval.zig");
const type_resolver = @import("type_resolver.zig");
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const SymbolRegistry = @import("symbol_table.zig").SymbolRegistry;

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore, p_arena: *Sand, import_scratch: *Sand) ?u32 {
    var path_s = interner_mod.stringInternerGet(reg.interner, reg.modules.items[mod_id].path_id);
    var file_id = sm_mod.sourceManagerAddFileTransient(reg.source_man, path_s, content);
    reg.modules.items[mod_id].source_file_id = file_id;

    var lex = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
    var p = parser_mod.parserInitStreaming(&lex, content, shared_store, reg.interner, reg.diag, p_arena);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
    parser_mod.parserSetImportScratch(&p, import_scratch);
    var ecb0: u32 = @intCast(u32, 0); var ecb1: u32 = @intCast(u32, 0); var ecb2: u32 = @intCast(u32, 0); var ecb3: u32 = @intCast(u32, 0); var ecb4: u32 = @intCast(u32, 0); var ecb5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { ecb0 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 0)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { ecb1 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 1)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { ecb2 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 2)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { ecb3 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 3)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { ecb4 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 4)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { ecb5 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 5)); }
    var se0: []const u8 = "ECB0:"; pal_mod.markerWriteInt(se0, ecb0);
    var se1: []const u8 = "ECB1:"; pal_mod.markerWriteInt(se1, ecb1);
    var se2: []const u8 = "ECB2:"; pal_mod.markerWriteInt(se2, ecb2);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
    var ecd0: u32 = @intCast(u32, 0); var ecd1: u32 = @intCast(u32, 0); var ecd2: u32 = @intCast(u32, 0); var ecd3: u32 = @intCast(u32, 0); var ecd4: u32 = @intCast(u32, 0); var ecd5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { ecd0 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 0)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { ecd1 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 1)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { ecd2 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 2)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { ecd3 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 3)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { ecd4 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 4)); }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { ecd5 = ast_mod.astStoreExtraChildAtRaw(shared_store, @intCast(u32, 5)); }
    var sd0: []const u8 = "ECD0:"; pal_mod.markerWriteInt(sd0, ecd0);
    var sd1: []const u8 = "ECD1:"; pal_mod.markerWriteInt(sd1, ecd1);
    var sd2: []const u8 = "ECD2:"; pal_mod.markerWriteInt(sd2, ecd2);
    if (ecb0 != ecd0 or ecb1 != ecd1 or ecb2 != ecd2) {
        var cp: []const u8 = "ECBED"; pal_mod.markerWrite(cp);
    }
    _ = ecb0; _ = ecb1; _ = ecb2;
    _ = ecd0; _ = ecd1; _ = ecd2;
    _ = ecb3; _ = ecb4; _ = ecb5;
    _ = ecd3; _ = ecd4; _ = ecd5;
    return ast_root;
}

// D3 (Phase 3.5): full deferral of `@import` resolution. The parser records
// every `@import` as an `import_expr` node and never resolves/opens it. After a
// module is parsed, this walk selects the live arm/prong with the shared
// comptime evaluator (plus the module/local `const` scope) and resolves ONLY
// the imports that can actually be selected. A comptime-dead arm is never
// resolved, queued, opened or parsed. An unfoldable condition keeps both arms
// live (conservative: a live import is never under-loaded; wrong-module
// selection is impossible).
fn importDeferredValEq(a: ce_mod.ComptimeVal, b: ce_mod.ComptimeVal) bool {
    if (a.kind != b.kind) return false;
    if (a.kind == ce_mod.KIND_FLOAT) return a.float_bits == b.float_bits;
    return ce_mod.ciCmp(a.v, b.v) == @intCast(i32, 0);
}

fn importDeferredFoldBool(ce: *ce_mod.ComptimeEval, node_idx: u32) ?bool {
    if (node_idx == @intCast(u32, 0)) return null;
    if (ce_mod.comptimeEvalEvaluate(ce, node_idx)) |cv| {
        if (cv.kind == ce_mod.KIND_BOOL) return !ce_mod.ciIsZero(cv.v);
    }
    return null;
}

fn importDeferredSubtreeHasImport(store: *ast_mod.AstStore, memo: [*]u8, node_idx: u32, depth: u32) bool {
    if (node_idx == @intCast(u32, 0)) return false;
    // Depth exhaustion is conservative: treat the subtree as relevant so its
    // live arms are scanned (imports are never silently dropped).
    if (depth >= @intCast(u32, 512)) return true;
    if (memo[@intCast(usize, node_idx)] == @intCast(u8, 1)) return false;
    if (memo[@intCast(usize, node_idx)] == @intCast(u8, 2)) return true;
    var n = ast_mod.astStoreNodeAt(store, node_idx);
    var has: bool = n.kind == AstKind.import_expr;
    if (!has and ast_mod.nodeHasNodeExtraChildren(n.kind) and ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
        var ec_n = ast_mod.astStoreNodeExtraChildCount(store, node_idx);
        var ei: u32 = 0;
        while (ei < ec_n) : (ei += 1) {
            if (importDeferredSubtreeHasImport(store, memo, ast_mod.astStoreNodeExtraChildAt(store, node_idx, ei), depth + @intCast(u32, 1))) { has = true; break; }
        }
    }
    if (!has and n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 2))) {
        has = importDeferredSubtreeHasImport(store, memo, n.child_2, depth + @intCast(u32, 1));
    }
    if (!has and n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 1))) {
        has = importDeferredSubtreeHasImport(store, memo, n.child_1, depth + @intCast(u32, 1));
    }
    if (!has and n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 0))) {
        has = importDeferredSubtreeHasImport(store, memo, n.child_0, depth + @intCast(u32, 1));
    }
    memo[@intCast(usize, node_idx)] = if (has) @intCast(u8, 2) else @intCast(u8, 1);
    return has;
}

fn importDeferredPushModuleConsts(store: *ast_mod.AstStore, root_idx: u32, scope: *type_resolver.LocalConstScope) void {
    var ec_n = ast_mod.astStoreNodeExtraChildCount(store, root_idx);
    var i: u32 = 0;
    while (i < ec_n) : (i += 1) {
        var c = ast_mod.astStoreNodeExtraChildAt(store, root_idx, i);
        var cn = ast_mod.astStoreNodeAt(store, c);
        if (cn.kind == AstKind.var_decl and (cn.flags & @intCast(u8, 1)) == @intCast(u8, 0) and cn.child_1 != @intCast(u32, 0)) {
            type_resolver.localConstScopePush(scope, ast_mod.astStoreNodePayload(store, c), c);
        }
    }
}

fn importDeferredScanNode(reg: *mr_mod.ModuleRegistry, importer_id: u32, scratch: *Sand, store: *ast_mod.AstStore, ce: *ce_mod.ComptimeEval, scope: *type_resolver.LocalConstScope, memo: [*]u8, node_idx: u32, depth: u32) void {
    if (node_idx == @intCast(u32, 0)) return;
    if (depth >= @intCast(u32, 1024)) return;
    if (!importDeferredSubtreeHasImport(store, memo, node_idx, @intCast(u32, 0))) return;
    var n = ast_mod.astStoreNodeAt(store, node_idx);

    if (n.kind == AstKind.if_expr or n.kind == AstKind.if_stmt) {
        importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_0, depth + @intCast(u32, 1));
        if (importDeferredFoldBool(ce, n.child_0)) |cv| {
            if (cv) {
                importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_1, depth + @intCast(u32, 1));
            } else if (n.child_2 != @intCast(u32, 0)) {
                importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_2, depth + @intCast(u32, 1));
            }
        } else {
            importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_1, depth + @intCast(u32, 1));
            if (n.child_2 != @intCast(u32, 0)) {
                importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_2, depth + @intCast(u32, 1));
            }
        }
        return;
    }

    if (n.kind == AstKind.swt_ex) {
        importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_0, depth + @intCast(u32, 1));
        var sel = ce_mod.comptimeEvalEvaluate(ce, n.child_0);
        var sel_known: bool = sel != null;
        var prong_n = ast_mod.astStoreNodeExtraChildCount(store, node_idx);
        var matched: u32 = @intCast(u32, 0);
        var else_prong: u32 = @intCast(u32, 0);
        var pi: u32 = 0;
        if (sel) |sv| {
            while (pi < prong_n) : (pi += 1) {
                var prong = ast_mod.astStoreNodeExtraChildAt(store, node_idx, pi);
                var pn = ast_mod.astStoreNodeAt(store, prong);
                var ci_n = ast_mod.astStoreNodeExtraChildCount(store, prong);
                var cii: u32 = 0;
                while (cii < ci_n) : (cii += 1) {
                    importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, ast_mod.astStoreNodeExtraChildAt(store, prong, cii), depth + @intCast(u32, 1));
                }
                if ((pn.flags & @intCast(u8, 1)) != @intCast(u8, 0)) {
                    if (else_prong == @intCast(u32, 0)) else_prong = prong;
                } else if (matched == @intCast(u32, 0)) {
                    var hit: bool = false;
                    var cj: u32 = 0;
                    while (cj < ci_n) : (cj += 1) {
                        var item = ast_mod.astStoreNodeExtraChildAt(store, prong, cj);
                        if (ce_mod.comptimeEvalEvaluate(ce, item)) |iv| {
                            if (importDeferredValEq(sv, iv)) { hit = true; break; }
                        }
                    }
                    if (hit) matched = prong;
                }
            }
            if (matched == @intCast(u32, 0)) matched = else_prong;
        }
        pi = 0;
        while (pi < prong_n) : (pi += 1) {
            var prong = ast_mod.astStoreNodeExtraChildAt(store, node_idx, pi);
            var pn = ast_mod.astStoreNodeAt(store, prong);
            if (sel_known) {
                if (prong == matched) {
                    importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, pn.child_0, depth + @intCast(u32, 1));
                }
            } else {
                var ci_n2 = ast_mod.astStoreNodeExtraChildCount(store, prong);
                var cii2: u32 = 0;
                while (cii2 < ci_n2) : (cii2 += 1) {
                    importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, ast_mod.astStoreNodeExtraChildAt(store, prong, cii2), depth + @intCast(u32, 1));
                }
                importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, pn.child_0, depth + @intCast(u32, 1));
            }
        }
        return;
    }

    if (n.kind == AstKind.block) {
        var saved: usize = scope.count;
        var block_n = ast_mod.astStoreNodeExtraChildCount(store, node_idx);
        var bi: u32 = 0;
        while (bi < block_n) : (bi += 1) {
            var c = ast_mod.astStoreNodeExtraChildAt(store, node_idx, bi);
            importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, c, depth + @intCast(u32, 1));
            var cn = ast_mod.astStoreNodeAt(store, c);
            if (cn.kind == AstKind.var_decl and (cn.flags & @intCast(u8, 1)) == @intCast(u8, 0) and cn.child_1 != @intCast(u32, 0)) {
                type_resolver.localConstScopePush(scope, ast_mod.astStoreNodePayload(store, c), c);
            }
        }
        scope.count = saved;
        return;
    }

    if (n.kind == AstKind.import_expr) {
        var path_id: u32 = ast_mod.astStoreNodePayload(store, node_idx);
        _ = mr_mod.moduleRegistryResolveImport(reg, path_id, importer_id, scratch);
        return;
    }

    if (ast_mod.nodeHasNodeExtraChildren(n.kind) and ast_mod.astStoreNodePayload(store, node_idx) != @intCast(u32, 0)) {
        var ec_n = ast_mod.astStoreNodeExtraChildCount(store, node_idx);
        var ei: u32 = 0;
        while (ei < ec_n) : (ei += 1) {
            importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, ast_mod.astStoreNodeExtraChildAt(store, node_idx, ei), depth + @intCast(u32, 1));
        }
    }
    if (n.child_2 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 2))) {
        importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_2, depth + @intCast(u32, 1));
    }
    if (n.child_1 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 1))) {
        importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_1, depth + @intCast(u32, 1));
    }
    if (n.child_0 != @intCast(u32, 0) and ast_mod.nodeChildIsNode(n.kind, @intCast(u8, 0))) {
        importDeferredScanNode(reg, importer_id, scratch, store, ce, scope, memo, n.child_0, depth + @intCast(u32, 1));
    }
}

fn moduleRegistryScanDeferredImports(reg: *mr_mod.ModuleRegistry, mod_id: u32, ast_root: u32, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore, ce: *ce_mod.ComptimeEval) void {
    var memo_len: usize = @intCast(usize, shared_store.nodes.len);
    var memo_raw = alloc_mod.sandAlloc(scratch, memo_len, @intCast(usize, 1)) catch unreachable;
    var memo: [*]u8 = @ptrCast([*]u8, memo_raw);
    var zi: usize = 0;
    while (zi < memo_len) : (zi += 1) { memo[zi] = @intCast(u8, 0); }
    var scope = type_resolver.localConstScopeInit(module_arena);
    var scan_ce = ce.*;
    scan_ce.module_id = mod_id;
    scan_ce.local_consts = &scope;
    importDeferredPushModuleConsts(shared_store, ast_root, &scope);
    importDeferredScanNode(reg, mod_id, scratch, shared_store, &scan_ce, &scope, memo, ast_root, @intCast(u32, 0));
}

pub fn moduleRegistryResolveImports(reg: *mr_mod.ModuleRegistry, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore, typereg: *TypeRegistry, symbol_reg: *SymbolRegistry) void {
    var parser_arena: alloc_mod.GrowableSand = undefined;
    var parser_name: []const u8 = "parser";
    alloc_mod.growableSandInit(&parser_arena, alloc_mod.poolPtr(), 4096, parser_name);

    var import_scratch_gs: alloc_mod.GrowableSand = undefined;
    var import_scratch_name: []const u8 = "import_scratch";
    alloc_mod.growableSandInit(&import_scratch_gs, alloc_mod.poolPtr(), 256, import_scratch_name);

    var src_arena: alloc_mod.GrowableSand = undefined;
    var src_name: []const u8 = "source";
    alloc_mod.growableSandInit(&src_arena, alloc_mod.poolPtr(), 4096, src_name);

    // D3: one shared comptime evaluator for the deferred import selection.
    // Initialized BEFORE the first module parse so its builtin interns happen
    // before source lexing (F1 is root-fixed: id order no longer changes
    // compilation semantics; see the interner re-verification in the report).
    var deferred_ce = ce_mod.comptimeEvalInit(typereg, shared_store, reg.interner, symbol_reg);
    deferred_ce.host_is_windows = reg.target_is_windows;

    while (true) {
        var mod_id_opt = mr_mod.importQueueDequeue(&reg.import_queue);
        if (mod_id_opt) |mod_id| {
            var entry = reg.modules.items[mod_id];
            if (entry.state != mr_mod.ModuleState.pending) continue;

            alloc_mod.sandReset(scratch);
            alloc_mod.sandReset(&parser_arena.view);
            alloc_mod.sandReset(&src_arena.view);

            entry.state = mr_mod.ModuleState.parsing;
            reg.modules.items[mod_id] = entry;

            var path_s = interner_mod.stringInternerGet(reg.interner, entry.path_id);
            var content = pal_mod.readFile(path_s, &src_arena.view) orelse {
                var p1: []const u8 = "could not read imported file '";
                var p2: []const u8 = "'";
                var parts: [3][]const u8 = [3][]const u8{ p1, path_s, p2 };
                var msg = diag_mod.diagnosticBuilderMakeMsg(reg.interner, &parts[0], @intCast(u32, 3));
                diag_mod.diagnosticCollectorAdd(reg.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3048_CANNOT_READ_FILE)), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), msg);
                entry.state = mr_mod.ModuleState.failed;
                reg.modules.items[mod_id] = entry;
                continue;
            };

            var ast_root = moduleRegistryParseModule(reg, mod_id, content, module_arena, scratch, shared_store, &parser_arena.view, &import_scratch_gs.view) orelse {
                entry.state = mr_mod.ModuleState.failed;
                reg.modules.items[mod_id] = entry;
                continue;
            };

            reg.modules.items[mod_id].ast_root = ast_root;
            reg.modules.items[mod_id].state = mr_mod.ModuleState.parsed;

            // D3: resolve only the imports the comptime evaluator can select.
            moduleRegistryScanDeferredImports(reg, mod_id, ast_root, module_arena, scratch, shared_store, &deferred_ce);
            entry = reg.modules.items[mod_id];

            var root = ast_mod.astStoreNodeAt(shared_store, ast_root);
            if (root.kind == AstKind.module_root) {
                var p1: []const u8 = "IRP:m"; pal_mod.measureMarkerWriteInt(p1, mod_id);
                var p2: []const u8 = "IRP:n"; pal_mod.measureMarkerWriteInt(p2, ast_root);
                var p3: []const u8 = "IRP:p"; pal_mod.measureMarkerWriteInt(p3, @intCast(u32, ast_mod.astStoreNodePayloadPacked(shared_store, ast_root, root.kind) & @intCast(u64, 0xFFFFFFFF)));
                var decls_n = ast_mod.astStoreNodeExtraChildCount(shared_store, ast_root);
                var p4: []const u8 = "IRD:c"; pal_mod.markerWriteInt(p4, @intCast(u32, decls_n));
                var di2: usize = @intCast(usize, 0);
                while (di2 < @intCast(usize, decls_n)) : (di2 += @intCast(usize, 1)) {
                    var p5: []const u8 = "IRD:n"; pal_mod.markerWriteInt(p5, ast_mod.astStoreNodeExtraChildAt(shared_store, ast_root, @intCast(u32, di2)));
                }
                var nl: []const u8 = "\n"; pal_mod.markerWrite(nl);
            }

            var start = @intCast(usize, entry.imports_start);
            var end: usize = start + @intCast(usize, entry.import_count);
            var i: usize = start;
            while (i < end) {
                var imported_id = reg.import_edges_items[i];
                var imp_entry = reg.modules.items[imported_id];
                if (imp_entry.state == mr_mod.ModuleState.pending) {
                    mr_mod.importQueueEnqueue(&reg.import_queue, imported_id);
                }
                i += 1;
            }
        } else {
            break;
        }
    }
    var vmi: usize = @intCast(usize, 0);
    while (vmi < reg.modules.len) : (vmi += @intCast(usize, 1)) {
        var ve = reg.modules.items[vmi];
        if (ve.ast_root != @intCast(u32, 0)) {
            var vr = ast_mod.astStoreNodeAt(shared_store, ve.ast_root);
            if (vr.kind == AstKind.module_root) {
                var v1: []const u8 = "IRV:m"; pal_mod.markerWriteInt(v1, vmi);
                var vdecls_n = ast_mod.astStoreNodeExtraChildCount(shared_store, ve.ast_root);
                var v2: []const u8 = "IRV:c"; pal_mod.markerWriteInt(v2, @intCast(u32, vdecls_n));
                var vdi: usize = @intCast(usize, 0);
                while (vdi < @intCast(usize, vdecls_n)) : (vdi += @intCast(usize, 1)) {
                    var v3: []const u8 = "IRV:n"; pal_mod.markerWriteInt(v3, ast_mod.astStoreNodeExtraChildAt(shared_store, ve.ast_root, @intCast(u32, vdi)));
                }
                var vnl: []const u8 = "\n";
                pal_mod.markerWrite(vnl);
            }
        }
    }
    var n1: []const u8 = "IRN:n"; pal_mod.measureMarkerWriteInt(n1, @intCast(u32, shared_store.nodes.len));
    var n2: []const u8 = "IRE:x"; pal_mod.measureMarkerWriteInt(n2, @intCast(u32, shared_store.extra_children.len));
    var nl2: []const u8 = "\n"; pal_mod.markerWrite(nl2);
}
