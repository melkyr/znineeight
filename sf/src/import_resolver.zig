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
const itoa_mod = @import("util/itoa.zig");
const sm_mod = @import("source_manager.zig");
const AstKind = @import("ast.zig").AstKind;

fn tokenArrayEnsureCapacity(items: *[*]Token, len: *usize, cap: *usize, alloc: *Sand, new_cap: usize) void {
    if (new_cap <= cap.*) return;
    var nc = new_cap;
    if (nc < cap.* * 2) nc = cap.* * 2;
    if (nc < @intCast(usize, 64)) nc = @intCast(usize, 64);
    var raw = alloc_mod.sandAlloc(alloc, @intCast(usize, 24) * nc, @intCast(usize, 4)) catch unreachable;
    var new_items = @ptrCast([*]Token, raw);
    for (items.*[0..len.*]) |item, i| { new_items[i] = item; }
    items.* = new_items;
    cap.* = nc;
}

fn tokenArrayAppend(items: *[*]Token, len: *usize, cap: *usize, alloc: *Sand, value: Token) void {
    tokenArrayEnsureCapacity(items, len, cap, alloc, len.* + 1);
    items.*[len.*] = value;
    len.* += 1;
}

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, module_arena: *Sand, scratch: *Sand, shared_store: *ast_mod.AstStore) ?u32 {
    var path_s = interner_mod.stringInternerGet(reg.interner, reg.modules.items[mod_id].path_id);
    var file_id = sm_mod.sourceManagerAddFile(reg.source_man, path_s, content);
    reg.modules.items[mod_id].source_file_id = file_id;

    var tok_items: [*]Token = undefined;
    var tok_len: usize = 0;
    var tok_cap: usize = 0;
    var lex = lexer_mod.lexerInit(content, file_id, reg.interner, reg.diag, scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tokenArrayAppend(&tok_items, &tok_len, &tok_cap, scratch, t);
        if (t.kind == TokenKind.eof) break;
    }
    var p_arena_buf: [4096]u8 = undefined;
    var p_arena = alloc_mod.sandInit(p_arena_buf[0..]);
    var p = parser_mod.parserInit(tok_items[0..tok_len], content, shared_store, reg.interner, reg.diag, &p_arena);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
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
    while (true) {
        var mod_id_opt = mr_mod.importQueueDequeue(&reg.import_queue);
        if (mod_id_opt) |mod_id| {
            var entry = reg.modules.items[mod_id];
            if (entry.state != mr_mod.ModuleState.pending) continue;

            alloc_mod.sandReset(scratch);

            entry.state = mr_mod.ModuleState.parsing;
            reg.modules.items[mod_id] = entry;

            var path_s = interner_mod.stringInternerGet(reg.interner, entry.path_id);
            var content = pal_mod.readFile(path_s, scratch) orelse {
                entry.state = mr_mod.ModuleState.failed;
                reg.modules.items[mod_id] = entry;
                continue;
            };

            var ast_root = moduleRegistryParseModule(reg, mod_id, content, module_arena, scratch, shared_store) orelse {
                entry.state = mr_mod.ModuleState.failed;
                reg.modules.items[mod_id] = entry;
                continue;
            };

            entry.ast_root = ast_root;
            entry.state = mr_mod.ModuleState.parsed;
            reg.modules.items[mod_id] = entry;

            var root = shared_store.nodes.items[@intCast(usize, ast_root)];
            if (root.kind == AstKind.module_root) {
                var p1: []const u8 = "IRP:m"; pal_mod.markerWriteInt(p1, mod_id);
                var p2: []const u8 = "IRP:n"; pal_mod.markerWriteInt(p2, ast_root);
                var p3: []const u8 = "IRP:p"; pal_mod.markerWriteInt(p3, root.payload);
                var decls = ast_mod.astStoreGetExtraChildren(shared_store, root.payload);
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
                var vdecls = ast_mod.astStoreGetExtraChildren(shared_store, vr.payload);
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
