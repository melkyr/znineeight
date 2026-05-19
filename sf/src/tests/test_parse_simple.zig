const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const token_mod = @import("../token.zig");
const lexer_mod = @import("../lexer.zig");
const parser_mod = @import("../parser.zig");
const ast_mod = @import("../ast.zig");
const pal = @import("../pal.zig");
const diag_mod = @import("../diagnostics.zig");

var perm_buf: [65536]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;
var tok_buf: [4000]Token = undefined;

fn parseFile(path: []const u8) void {
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var content = pal.readFile(path, &scratch) orelse { pal.exit(1); return; };
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
}

pub fn main() void {
    pal.initArgs(0, undefined);
    var p1: []const u8 = "examples/hello/main.zig";
    parseFile(p1);
    var p2: []const u8 = "examples/fibonacci/main.zig";
    parseFile(p2);
    var okmsg: []const u8 = "ok\n";
    pal.stdout_write(okmsg);
}
