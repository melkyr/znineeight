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
const diag_mod = @import("../diagnostics.zig");

var perm_buf: [2097152]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;

pub fn main() void {
    pal.initArgs(0, undefined);
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var p: []const u8 = "sf/src/tests/mud_full.zig";
    var content = pal.readFile(p, &scratch) orelse { pal.exit(1); return; };
    var tok_buf: [16000]Token = undefined;
    var tok_len: usize = 0;
    var lex = lexer_mod.lexerInit(content, 0, &interner, &diag, &scratch);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&perm);
    var pp = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    _ = parser_mod.parserParseModuleRoot(&pp) catch { pal.exit(1); return; };
    alloc_mod.sandReset(&scratch);
    var msg: []const u8 = "parse mud ok\n";
    pal.stdout_write(msg);
}
