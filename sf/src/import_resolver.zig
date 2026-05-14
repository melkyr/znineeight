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

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, module_arena: *Sand, scratch: *Sand) ?u32 {
    var tok_items: [*]Token = undefined;
    var tok_len: usize = 0;
    var tok_cap: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), reg.interner, reg.diag, scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tokenArrayAppend(&tok_items, &tok_len, &tok_cap, scratch, t);
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(module_arena);
    var p = parser_mod.parserInit(tok_items[0..tok_len], content, &store, reg.interner, reg.diag, module_arena);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
    return ast_root;
}

pub fn moduleRegistryResolveImports(reg: *mr_mod.ModuleRegistry, module_arena: *Sand, scratch: *Sand) void {
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

            var ast_root = moduleRegistryParseModule(reg, mod_id, content, module_arena, scratch) orelse {
                entry.state = mr_mod.ModuleState.failed;
                reg.modules.items[mod_id] = entry;
                continue;
            };

            entry.ast_root = ast_root;
            entry.state = mr_mod.ModuleState.parsed;
            reg.modules.items[mod_id] = entry;

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
}
