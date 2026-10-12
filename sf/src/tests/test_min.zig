const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const token_mod = @import("../token.zig");
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const pal = @import("../pal.zig");
const sym_mod = @import("../symbol_table.zig");
const diag_mod = @import("../diagnostics.zig");
const type_mod = @import("../type_registry.zig");

var perm_buf: [2097152]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;

fn testFile(path: []const u8, name: []const u8) void {
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var content = pal.readFile(path, &scratch) orelse { pal.exit(1); return; };
    var tok_buf: [8192]Token = undefined;
    var tok_len: usize = 0;
    var lex = lexer_mod.lexerInit(content, 0, &interner, &diag, &scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    _ = parser_mod.parserParseModuleRoot(&p) catch { pal.exit(1); return; };
    alloc_mod.sandReset(&scratch);
    var msg: []const u8 = "  ok ";
    pal.stderr_write(msg);
    pal.stderr_write(name);
    pal.stderr_write("\n");
}

pub fn main() void {
    pal.initArgs(0, undefined);
    testFile("examples/game_of_life/main.zig", "game_of_life");
    pal.stdout_write("Done.\n");
}
