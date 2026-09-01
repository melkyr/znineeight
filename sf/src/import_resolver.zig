const Sand = @import("allocator.zig").Sand;
const alloc_mod = @import("allocator.zig");
const mr_mod = @import("module_registry.zig");
const pal_mod = @import("pal.zig");
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const lexer_mod = @import("lexer.zig");
const parser_mod = @import("parser.zig");
const ast_mod = @import("ast.zig");
const interner_mod = @import("string_interner.zig");
const diag_mod = @import("diagnostics.zig");
const itoa_mod = @import("util/itoa.zig");
const sm_mod = @import("source_manager.zig");
const ga_mod = @import("growable_array.zig");
const hash_mod = @import("util/hash.zig");
const mem_mod = @import("util/mem.zig");
const AstKind = @import("ast.zig").AstKind;

// Side-effect-free import-closure discovery + token count for AST-store pre-sizing.
// Walks the import graph via a path stack (LIFO, mirroring the import queue) and a
// seen-set, lexes each file to find `@import("...")` builtins, and resolves the
// target via the module resolver (interning resolved paths in parse order). Creates
// no modules, emits no diagnostics, and writes nothing to the AST store.
// Returns the total token count of the closure; measured across the gate programs
// the AST-store ratios are stable per token (~0.51-0.55 nodes/token, ~0.18-0.22
// extra-children/token), unlike per-line ratios which vary ~2x by program.
fn moduleScanDiscover(reg: *mr_mod.ModuleRegistry, scratch: *Sand) usize {
    var seen = hash_mod.u32ToU32MapInit(reg.alloc);
    var worklist = ga_mod.u32ArrayListInit(reg.alloc);
    var root_path_id = reg.modules.items[@intCast(usize, 0)].path_id;
    ga_mod.u32ArrayListAppend(&worklist, root_path_id);
    _ = hash_mod.u32ToU32MapPut(&seen, root_path_id, @intCast(u32, 1));
    var total_tokens: usize = 0;
    var import_s: []const u8 = "@import";
    while (worklist.len > 0) {
        var pop_opt = ga_mod.u32ArrayListPopOrNull(&worklist);
        if (pop_opt) |path_id| {
            var path_s = interner_mod.stringInternerGet(reg.interner, path_id);
            alloc_mod.sandReset(scratch);
            var content = pal_mod.readFile(path_s, scratch) orelse continue;
            var scan_diag = diag_mod.diagnosticCollectorInit(scratch, reg.source_man, reg.interner);
            var import_targets = ga_mod.u32ArrayListInit(scratch);
            var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), reg.interner, &scan_diag, scratch);
            while (true) {
                var tok = lexer_mod.lexerNextToken(&lex);
                total_tokens += 1;
                if (tok.kind == TokenKind.eof) break;
                if (tok.kind != TokenKind.builtin_identifier) continue;
                var name = interner_mod.stringInternerGet(reg.interner, tok.value.string_id);
                if (mem_mod.mem_eql(name, import_s)) {
                    var t1 = lexer_mod.lexerNextToken(&lex);
                    if (t1.kind != TokenKind.lparen) continue;
                    var t2 = lexer_mod.lexerNextToken(&lex);
                    if (t2.kind != TokenKind.string_literal) continue;
                    var t3 = lexer_mod.lexerNextToken(&lex);
                    if (t3.kind != TokenKind.rparen) continue;
                    ga_mod.u32ArrayListAppend(&import_targets, t2.value.string_id);
                }
            }
            var ji: usize = 0;
            while (ji < import_targets.len) : (ji += @intCast(usize, 1)) {
                var target = interner_mod.stringInternerGet(reg.interner, import_targets.items[ji]);
                var resolved_id = mr_mod.moduleResolverResolve(&reg.resolver, path_s, target, scratch);
                if (resolved_id) |rid| {
                    if (hash_mod.u32ToU32MapGet(&seen, rid) == null) {
                        _ = hash_mod.u32ToU32MapPut(&seen, rid, @intCast(u32, 1));
                        ga_mod.u32ArrayListAppend(&worklist, rid);
                    }
                }
            }
        }
    }
    return total_tokens;
}

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore, p_arena: *Sand, import_scratch: *Sand) ?u32 {
    var path_s = interner_mod.stringInternerGet(reg.interner, reg.modules.items[mod_id].path_id);
    var file_id = sm_mod.sourceManagerAddFile(reg.source_man, path_s, content);
    reg.modules.items[mod_id].source_file_id = file_id;

    var token_count: usize = 0;
    var lex1 = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
    lex1.count_only = true;
    while (true) {
        var t1 = lexer_mod.lexerNextToken(&lex1);
        token_count += 1;
        if (t1.kind == TokenKind.eof) break;
    }
    var raw = alloc_mod.sandAlloc(scratch, @intCast(usize, @sizeOf(Token)) * token_count, @intCast(usize, 4)) catch return null;
    var tok_items = @ptrCast([*]Token, raw);
    var lex2 = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
    var tok_len: usize = 0;
    while (true) {
        var t2 = lexer_mod.lexerNextToken(&lex2);
        tok_items[tok_len] = t2;
        tok_len += 1;
        if (t2.kind == TokenKind.eof) break;
    }
    var p = parser_mod.parserInit(tok_items[0..tok_len], content, shared_store, reg.interner, reg.diag, p_arena);
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

    // Pre-size the AST store nodes/extra_children from the import-closure token count
    // (token-count heuristic: ~0.6 nodes / ~0.25 extra-children entries per token)
    // so the arrays land near their final size in a single allocation. This eliminates
    // most of the copy-into-bump ~2x growth waste in the module arena.
    var total_tokens = moduleScanDiscover(reg, scratch);
    var nodes_target = total_tokens * @intCast(usize, 6) / @intCast(usize, 10);
    var ec_target = total_tokens / @intCast(usize, 4);
    ast_mod.astStoreEnsureNodesCapacity(shared_store, nodes_target);
    ast_mod.astStoreEnsureExtraChildrenCapacity(shared_store, ec_target);

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

            var root = shared_store.nodes.items[@intCast(usize, ast_root)];
            if (root.kind == AstKind.module_root) {
                var p1: []const u8 = "IRP:m"; pal_mod.markerWriteInt(p1, mod_id);
                var p2: []const u8 = "IRP:n"; pal_mod.markerWriteInt(p2, ast_root);
                var p3: []const u8 = "IRP:p"; pal_mod.markerWriteInt(p3, @intCast(u32, ast_mod.astStoreNodePayloadPacked(shared_store, ast_root, root.kind) & @intCast(u64, 0xFFFFFFFF)));
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
            var vr = shared_store.nodes.items[@intCast(usize, ve.ast_root)];
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
    var n1: []const u8 = "IRN:n"; pal_mod.markerWriteInt(n1, @intCast(u32, shared_store.nodes.len));
    var n2: []const u8 = "IRE:x"; pal_mod.markerWriteInt(n2, @intCast(u32, shared_store.extra_children.len));
    var nl2: []const u8 = "\n"; pal_mod.markerWrite(nl2);
}
