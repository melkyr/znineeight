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
    var b0: u32 = @intCast(u32, 0); var b1: u32 = @intCast(u32, 0); var b2: u32 = @intCast(u32, 0); var b3: u32 = @intCast(u32, 0); var b4: u32 = @intCast(u32, 0); var b5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { b0 = shared_store.extra_children.items[@intCast(usize, 0)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { b1 = shared_store.extra_children.items[@intCast(usize, 1)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { b2 = shared_store.extra_children.items[@intCast(usize, 2)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { b3 = shared_store.extra_children.items[@intCast(usize, 3)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { b4 = shared_store.extra_children.items[@intCast(usize, 4)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { b5 = shared_store.extra_children.items[@intCast(usize, 5)]; }
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
    var d0: u32 = @intCast(u32, 0); var d1: u32 = @intCast(u32, 0); var d2: u32 = @intCast(u32, 0); var d3: u32 = @intCast(u32, 0); var d4: u32 = @intCast(u32, 0); var d5: u32 = @intCast(u32, 0);
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 0)) { d0 = shared_store.extra_children.items[@intCast(usize, 0)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 1)) { d1 = shared_store.extra_children.items[@intCast(usize, 1)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 2)) { d2 = shared_store.extra_children.items[@intCast(usize, 2)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 3)) { d3 = shared_store.extra_children.items[@intCast(usize, 3)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 4)) { d4 = shared_store.extra_children.items[@intCast(usize, 4)]; }
    if (@intCast(usize, shared_store.extra_children.len) > @intCast(usize, 5)) { d5 = shared_store.extra_children.items[@intCast(usize, 5)]; }
    var sm: []const u8 = "S"; pal_mod.markerWrite(sm);
    var sr1: u32 = b0; var sr2: u32 = b1; var sr3: u32 = b2; var sr4: u32 = b3; var sr5: u32 = b4; var sr6: u32 = b5;
    _ = sr1; _ = sr2; _ = sr3; _ = sr4; _ = sr5; _ = sr6;
    var sm2: []const u8 = " "; pal_mod.markerWrite(sm2);
    var se1: u32 = d0; var se2: u32 = d1; var se3: u32 = d2; var se4: u32 = d3; var se5: u32 = d4; var se6: u32 = d5;
    _ = se1; _ = se2; _ = se3; _ = se4; _ = se5; _ = se6;
    if (b0 != d0 or b1 != d1 or b2 != d2 or b3 != d3 or b4 != d4 or b5 != d5) {
        var cp: []const u8 = "C"; pal_mod.markerWrite(cp);
        var cb1: [20]u8 = undefined; var cl1 = itoa_mod.itoa(b0, cb1[0..]); var cs1: usize = @intCast(usize, 19) - @intCast(usize, cl1); pal_mod.markerWrite(cb1[cs1..@intCast(usize, 19)]); var csp1: []const u8 = "/"; pal_mod.markerWrite(csp1);
        var cd1: [20]u8 = undefined; var cl2 = itoa_mod.itoa(d0, cd1[0..]); var cs2: usize = @intCast(usize, 19) - @intCast(usize, cl2); pal_mod.markerWrite(cd1[cs2..@intCast(usize, 19)]); var csp2: []const u8 = " "; pal_mod.markerWrite(csp2);
        var cb4: [20]u8 = undefined; var cl4 = itoa_mod.itoa(b1, cb4[0..]); var cs4: usize = @intCast(usize, 19) - @intCast(usize, cl4); pal_mod.markerWrite(cb4[cs4..@intCast(usize, 19)]); pal_mod.markerWrite(csp1);
        var cd4: [20]u8 = undefined; var cl5 = itoa_mod.itoa(d1, cd4[0..]); var cs5: usize = @intCast(usize, 19) - @intCast(usize, cl5); pal_mod.markerWrite(cd4[cs5..@intCast(usize, 19)]); pal_mod.markerWrite(csp2);
        var cb7: [20]u8 = undefined; var cl7 = itoa_mod.itoa(b2, cb7[0..]); var cs7: usize = @intCast(usize, 19) - @intCast(usize, cl7); pal_mod.markerWrite(cb7[cs7..@intCast(usize, 19)]); pal_mod.markerWrite(csp1);
        var cd7: [20]u8 = undefined; var cl8 = itoa_mod.itoa(d2, cd7[0..]); var cs8: usize = @intCast(usize, 19) - @intCast(usize, cl8); pal_mod.markerWrite(cd7[cs8..@intCast(usize, 19)]);
    }
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
                var pct: []const u8 = "P"; pal_mod.markerWrite(pct);
                var mi_buf: [20]u8 = undefined;
                var mi_len = itoa_mod.itoa(mod_id, mi_buf[0..]);
                var mi_start: usize = @intCast(usize, 19) - @intCast(usize, mi_len);
                pal_mod.markerWrite(mi_buf[mi_start..@intCast(usize, 19)]);
                var pcl: []const u8 = ":"; pal_mod.markerWrite(pcl);
                var ar_buf: [20]u8 = undefined;
                var ar_len = itoa_mod.itoa(ast_root, ar_buf[0..]);
                var ar_start: usize = @intCast(usize, 19) - @intCast(usize, ar_len);
                pal_mod.markerWrite(ar_buf[ar_start..@intCast(usize, 19)]);
                pal_mod.markerWrite(pcl);
                var pay_buf: [20]u8 = undefined;
                var pay_len = itoa_mod.itoa(root.payload, pay_buf[0..]);
                var pay_start: usize = @intCast(usize, 19) - @intCast(usize, pay_len);
                pal_mod.markerWrite(pay_buf[pay_start..@intCast(usize, 19)]);
                pal_mod.markerWrite(pcl);
                var decls = ast_mod.astStoreGetExtraChildren(shared_store, root.payload);
                var dc_buf: [20]u8 = undefined;
                var dc_len = itoa_mod.itoa(@intCast(u32, decls.len), dc_buf[0..]);
                var dc_start: usize = @intCast(usize, 19) - @intCast(usize, dc_len);
                pal_mod.markerWrite(dc_buf[dc_start..@intCast(usize, 19)]);
                var bar: []const u8 = "|"; pal_mod.markerWrite(bar);
                var di2: usize = @intCast(usize, 0);
                while (di2 < decls.len) : (di2 += @intCast(usize, 1)) {
                    var ii_buf: [20]u8 = undefined;
                    var ii_len = itoa_mod.itoa(decls[di2], ii_buf[0..]);
                    var ii_start: usize = @intCast(usize, 19) - @intCast(usize, ii_len);
                    pal_mod.markerWrite(ii_buf[ii_start..@intCast(usize, 19)]);
                    var ss: []const u8 = "="; pal_mod.markerWrite(ss);
                    var dcl = shared_store.nodes.items[@intCast(usize, decls[di2])];
                    var dk: u32 = @intCast(u32, @enumToInt(dcl.kind));
                    var dk_buf: [20]u8 = undefined;
                    var dk_len = itoa_mod.itoa(dk, dk_buf[0..]);
                    var dk_start: usize = @intCast(usize, 19) - @intCast(usize, dk_len);
                    pal_mod.markerWrite(dk_buf[dk_start..@intCast(usize, 19)]);
                    var spc: []const u8 = " "; pal_mod.markerWrite(spc);
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
                var vchk: []const u8 = "V"; pal_mod.markerWrite(vchk);
                var vdecls = ast_mod.astStoreGetExtraChildren(shared_store, vr.payload);
                var vdi: usize = @intCast(usize, 0);
                while (vdi < vdecls.len) : (vdi += @intCast(usize, 1)) {
                    var vn = shared_store.nodes.items[@intCast(usize, vdecls[vdi])];
                    var vk: u32 = @intCast(u32, @enumToInt(vn.kind));
                    var vbuf: [20]u8 = undefined;
                    var vlen = itoa_mod.itoa(vk, vbuf[0..]);
                    var vs: usize = @intCast(usize, 19) - @intCast(usize, vlen);
                    pal_mod.markerWrite(vbuf[vs..@intCast(usize, 19)]);
                    var vsp: []const u8 = " ";
                    pal_mod.markerWrite(vsp);
                }
                var vnl: []const u8 = "\n";
                pal_mod.markerWrite(vnl);
            }
        }
    }
    var nmsg: []const u8 = "nodes="; pal_mod.markerWrite(nmsg);
    var n_buf: [20]u8 = undefined;
    var n_len = itoa_mod.itoa(@intCast(u32, shared_store.nodes.len), n_buf[0..]);
    var n_start: usize = @intCast(usize, 19) - @intCast(usize, n_len);
    pal_mod.markerWrite(n_buf[n_start..@intCast(usize, 19)]);
    var emsg: []const u8 = " extra="; pal_mod.markerWrite(emsg);
    var e_buf: [20]u8 = undefined;
    var e_len = itoa_mod.itoa(@intCast(u32, shared_store.extra_children.len), e_buf[0..]);
    var e_start: usize = @intCast(usize, 19) - @intCast(usize, e_len);
    pal_mod.markerWrite(e_buf[e_start..@intCast(usize, 19)]);
    var nl2: []const u8 = "\n"; pal_mod.markerWrite(nl2);
}
