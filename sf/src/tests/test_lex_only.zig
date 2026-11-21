const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const Token = @import("../token.zig").Token;
const TokenKind = @import("../token.zig").TokenKind;
const token_mod = @import("../token.zig");
const lexer_mod = @import("../lexer.zig");
const pal = @import("../pal.zig");
const diag_mod = @import("../diagnostics.zig");

var perm_buf: [65536]u8 = undefined;
var scratch_buf: [262144]u8 = undefined;

pub fn main() void {
    pal.initArgs(0, undefined);
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var p_gol: []const u8 = "examples/game_of_life/main.zig";
    var content = pal.readFile(p_gol, &scratch) orelse { pal.exit(1); return; };
    var lex = lexer_mod.lexerInit(content, 0, &interner, &diag, &scratch);
    var count: u32 = 0;
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        count += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var msg: []const u8 = "lex ok\n";
    pal.stdout_write(msg);
}
