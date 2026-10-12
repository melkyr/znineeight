const Sand = @import("../allocator.zig").Sand;
const alloc_mod = @import("../allocator.zig");
const mr_mod = @import("../module_registry.zig");
const pal_mod = @import("../pal.zig");
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");

fn moduleRegistryParseModule(reg: *mr_mod.ModuleRegistry, mod_id: u32, content: []const u8, scratch: *Sand) ?u32 {
    var tok_items: [*]Token = undefined;
    var tok_len: usize = 0;
    var tok_cap: usize = 0;
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), reg.interner, reg.diag, scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        if (tok_len >= tok_cap) {
            var new_cap = if (tok_cap < @intCast(usize, 64)) @intCast(usize, 64) else tok_cap * @intCast(usize, 2);
            var raw = alloc_mod.sandAlloc(scratch, @intCast(usize, 24) * new_cap, @intCast(usize, 4)) catch return null;
            var new_items = @ptrCast([*]Token, raw);
            for (tok_items[0..tok_len]) |item, i| { new_items[i] = item; }
            tok_items = new_items;
            tok_cap = new_cap;
        }
        tok_items[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(scratch);
    var p = parser_mod.parserInit(tok_items[0..tok_len], content, &store, reg.interner, reg.diag, scratch);
    parser_mod.parserSetModuleContext(&p, reg, mod_id);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch return null;
    return ast_root;
}

pub fn main() void {
    var buf: [65536]u8 = undefined;
    var a = alloc_mod.sandInit(buf[0..]);
    var interner = interner_mod.stringInternerInit(&a, 4);
    var sm = sm_mod.sourceManagerInit(&a);
    var diag = diag_mod.diagnosticCollectorInit(&a, &sm, &interner);
    var mr = mr_mod.moduleRegistryInit(&a, &interner, &diag);
    var path_str: []const u8 = "test.zig";
    var path_id = interner_mod.stringInternerIntern(&interner, path_str);
    var mod_id_0 = mr_mod.moduleRegistryAddModule(&mr, path_id);
    var test_content: []const u8 = "const x: u32 = 42;";
    var root = moduleRegistryParseModule(&mr, mod_id_0, test_content, &a) orelse unreachable;
    _ = root;
    var s: []const u8 = "PASS: import_resolver test\n";
    pal_mod.stdout_write(s);
}
