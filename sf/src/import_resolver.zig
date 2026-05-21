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
    var tok_items: [*]Token = undefined;
    var tok_len: usize = 0;
    var tok_cap: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), reg.interner, reg.diag, scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tokenArrayAppend(&tok_items, &tok_len, &tok_cap, scratch, t);
        if (t.kind == TokenKind.eof) break;
    }
    var p = parser_mod.parserInit(tok_items[0..tok_len], content, shared_store, reg.interner, reg.diag, module_arena);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
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
                var pct: []const u8 = "P"; pal_mod.stderr_write(pct);
                var mi_buf: [20]u8 = undefined;
                var mi_len = itoa_mod.itoa(mod_id, mi_buf[0..]);
                var mi_start: usize = @intCast(usize, 19) - @intCast(usize, mi_len);
                pal_mod.stderr_write(mi_buf[mi_start..@intCast(usize, 19)]);
                var pcl: []const u8 = ":"; pal_mod.stderr_write(pcl);
                var ar_buf: [20]u8 = undefined;
                var ar_len = itoa_mod.itoa(ast_root, ar_buf[0..]);
                var ar_start: usize = @intCast(usize, 19) - @intCast(usize, ar_len);
                pal_mod.stderr_write(ar_buf[ar_start..@intCast(usize, 19)]);
                pal_mod.stderr_write(pcl);
                var pay_buf: [20]u8 = undefined;
                var pay_len = itoa_mod.itoa(root.payload, pay_buf[0..]);
                var pay_start: usize = @intCast(usize, 19) - @intCast(usize, pay_len);
                pal_mod.stderr_write(pay_buf[pay_start..@intCast(usize, 19)]);
                pal_mod.stderr_write(pcl);
                var decls = ast_mod.astStoreGetExtraChildren(shared_store, root.payload);
                var dc_buf: [20]u8 = undefined;
                var dc_len = itoa_mod.itoa(@intCast(u32, decls.len), dc_buf[0..]);
                var dc_start: usize = @intCast(usize, 19) - @intCast(usize, dc_len);
                pal_mod.stderr_write(dc_buf[dc_start..@intCast(usize, 19)]);
                var bar: []const u8 = "|"; pal_mod.stderr_write(bar);
                var di2: usize = @intCast(usize, 0);
                while (di2 < decls.len) : (di2 += @intCast(usize, 1)) {
                    var ii_buf: [20]u8 = undefined;
                    var ii_len = itoa_mod.itoa(decls[di2], ii_buf[0..]);
                    var ii_start: usize = @intCast(usize, 19) - @intCast(usize, ii_len);
                    pal_mod.stderr_write(ii_buf[ii_start..@intCast(usize, 19)]);
                    var ss: []const u8 = "="; pal_mod.stderr_write(ss);
                    var dcl = shared_store.nodes.items[@intCast(usize, decls[di2])];
                    var dk: u32 = @intCast(u32, @enumToInt(dcl.kind));
                    var dk_buf: [20]u8 = undefined;
                    var dk_len = itoa_mod.itoa(dk, dk_buf[0..]);
                    var dk_start: usize = @intCast(usize, 19) - @intCast(usize, dk_len);
                    pal_mod.stderr_write(dk_buf[dk_start..@intCast(usize, 19)]);
                    var spc: []const u8 = " "; pal_mod.stderr_write(spc);
                }
                var nl: []const u8 = "\n"; pal_mod.stderr_write(nl);
            }

            var start = @intCast(usize, entry.imports_start);
            var end = start + @intCast(usize, entry.import_count);
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
    var nmsg: []const u8 = "nodes="; pal_mod.stderr_write(nmsg);
    var n_buf: [20]u8 = undefined;
    var n_len = itoa_mod.itoa(@intCast(u32, shared_store.nodes.len), n_buf[0..]);
    var n_start: usize = @intCast(usize, 19) - @intCast(usize, n_len);
    pal_mod.stderr_write(n_buf[n_start..@intCast(usize, 19)]);
    var emsg: []const u8 = " extra="; pal_mod.stderr_write(emsg);
    var e_buf: [20]u8 = undefined;
    var e_len = itoa_mod.itoa(@intCast(u32, shared_store.extra_children.len), e_buf[0..]);
    var e_start: usize = @intCast(usize, 19) - @intCast(usize, e_len);
    pal_mod.stderr_write(e_buf[e_start..@intCast(usize, 19)]);
    var nl2: []const u8 = "\n"; pal_mod.stderr_write(nl2);
}
