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

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore, p_arena: *Sand, import_scratch: *Sand) ?u32 {
    var path_s = interner_mod.stringInternerGet(reg.interner, reg.modules.items[mod_id].path_id);
    var file_id = sm_mod.sourceManagerAddFile(reg.source_man, path_s, content);
    reg.modules.items[mod_id].source_file_id = file_id;

    var lex = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
    var p = parser_mod.parserInitStreaming(&lex, content, shared_store, reg.interner, reg.diag, p_arena);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
    parser_mod.parserSetImportScratch(&p, import_scratch);
    var ecb0: u32 = @intCast(u32, 0); var ecb1: u32 = @intCast(u32, 0); var ecb2: u32 = @intCast(u32, 0); var ecb3: u32 = @intCast(u32, 0); var ecb4: u32 = @intCast(u32, 0); var ecb5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { ecb0 = shared_store.extra_children.items[@intCast(usize, 0)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { ecb1 = shared_store.extra_children.items[@intCast(usize, 1)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { ecb2 = shared_store.extra_children.items[@intCast(usize, 2)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { ecb3 = shared_store.extra_children.items[@intCast(usize, 3)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { ecb4 = shared_store.extra_children.items[@intCast(usize, 4)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { ecb5 = shared_store.extra_children.items[@intCast(usize, 5)]; }
    var se0: []const u8 = "ECB0:"; pal_mod.markerWriteInt(se0, ecb0);
    var se1: []const u8 = "ECB1:"; pal_mod.markerWriteInt(se1, ecb1);
    var se2: []const u8 = "ECB2:"; pal_mod.markerWriteInt(se2, ecb2);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
    var ecd0: u32 = @intCast(u32, 0); var ecd1: u32 = @intCast(u32, 0); var ecd2: u32 = @intCast(u32, 0); var ecd3: u32 = @intCast(u32, 0); var ecd4: u32 = @intCast(u32, 0); var ecd5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { ecd0 = shared_store.extra_children.items[@intCast(usize, 0)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { ecd1 = shared_store.extra_children.items[@intCast(usize, 1)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { ecd2 = shared_store.extra_children.items[@intCast(usize, 2)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { ecd3 = shared_store.extra_children.items[@intCast(usize, 3)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { ecd4 = shared_store.extra_children.items[@intCast(usize, 4)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { ecd5 = shared_store.extra_children.items[@intCast(usize, 5)]; }
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

pub fn moduleRegistryResolveImports(reg: *mr_mod.ModuleRegistry, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore) void {
    var parser_arena: alloc_mod.GrowableSand = undefined;
    var parser_name: []const u8 = "parser";
    alloc_mod.growableSandInit(&parser_arena, alloc_mod.poolPtr(), 4096, parser_name);

    var import_scratch_gs: alloc_mod.GrowableSand = undefined;
    var import_scratch_name: []const u8 = "import_scratch";
    alloc_mod.growableSandInit(&import_scratch_gs, alloc_mod.poolPtr(), 256, import_scratch_name);

    while (true) {
        var mod_id_opt = mr_mod.importQueueDequeue(&reg.import_queue);
        if (mod_id_opt) |mod_id| {
            var entry = reg.modules.items[mod_id];
            if (entry.state != mr_mod.ModuleState.pending) continue;

            alloc_mod.sandReset(scratch);
            alloc_mod.sandReset(&parser_arena.view);

            entry.state = mr_mod.ModuleState.parsing;
            reg.modules.items[mod_id] = entry;

            var path_s = interner_mod.stringInternerGet(reg.interner, entry.path_id);
            var content = pal_mod.readFile(path_s, reg.alloc) orelse {
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

            var root = ast_mod.astStoreNodeAt(shared_store, ast_root);
            if (root.kind == AstKind.module_root) {
                var p1: []const u8 = "IRP:m"; pal_mod.measureMarkerWriteInt(p1, mod_id);
                var p2: []const u8 = "IRP:n"; pal_mod.measureMarkerWriteInt(p2, ast_root);
                var p3: []const u8 = "IRP:p"; pal_mod.measureMarkerWriteInt(p3, @intCast(u32, ast_mod.astStoreNodePayloadPacked(shared_store, ast_root, root.kind) & @intCast(u64, 0xFFFFFFFF)));
                var decls = ast_mod.astStoreNodeExtraChildren(shared_store, ast_root);
                var p4: []const u8 = "IRD:c"; pal_mod.markerWriteInt(p4, @intCast(u32, decls.len));
                var di2: usize = @intCast(usize, 0);
                while (di2 < decls.len) : (di2 += @intCast(usize, 1)) {
                    var p5: []const u8 = "IRD:n"; pal_mod.markerWriteInt(p5, decls[di2]);
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
                var vdecls = ast_mod.astStoreNodeExtraChildren(shared_store, ve.ast_root);
                var v2: []const u8 = "IRV:c"; pal_mod.markerWriteInt(v2, @intCast(u32, vdecls.len));
                var vdi: usize = @intCast(usize, 0);
                while (vdi < vdecls.len) : (vdi += @intCast(usize, 1)) {
                    var v3: []const u8 = "IRV:n"; pal_mod.markerWriteInt(v3, vdecls[vdi]);
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
