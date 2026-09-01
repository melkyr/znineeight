const pal = @import("../pal.zig");
const interner_mod = @import("../string_interner.zig");
const StringInterner = interner_mod.StringInterner;
const token_mod = @import("../token.zig");
const Token = token_mod.Token;
const TokenKind = token_mod.TokenKind;
const lexer_mod = @import("../lexer.zig");
const Lexer = lexer_mod.Lexer;
const parser_mod = @import("../parser.zig");
const Parser = parser_mod.Parser;
const ast_mod = @import("../ast.zig");
const AstStore = ast_mod.AstStore;
const AstNode = ast_mod.AstNode;
const AstKind = ast_mod.AstKind;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const alloc_mod = @import("../allocator.zig");
const Sand = alloc_mod.Sand;

var perm_buf: [2*1024*1024]u8 = undefined;
var tok_buf: [32768]Token = undefined;

pub fn main() void {
    var perm: Sand = alloc_mod.sandInit(perm_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner: StringInterner = interner_mod.stringInternerInit(&perm, 4);
    var diag: DiagnosticCollector = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var content_opt = pal.readFile("examples/hello/main.zig", &perm);
    if (content_opt) |content_val| {
        var content: []const u8 = content_val;
        var lex: Lexer = lexer_mod.lexerInit(content, @intCast(u32, 0), &interner, &diag, &perm);
        var tok_len: usize = 0;
        while (true) {
            var t: Token = lexer_mod.lexerNextToken(&lex);
            tok_buf[tok_len] = t;
            tok_len += 1;
            if (t.kind == TokenKind.eof) break;
        }
        var store: AstStore = ast_mod.astStoreInit(&perm);
        var p: Parser = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
        var ast_root = parser_mod.parserParseModuleRoot(&p) catch unreachable;
        var root: AstNode = store.nodes.items[@intCast(usize, ast_root)];
        if (root.kind == AstKind.module_root) {
            var decls: []u32 = ast_mod.astStoreNodeExtraChildren(&store, ast_root);
            var di: usize = @intCast(usize, 0);
            while (di < decls.len) : (di += @intCast(usize, 1)) {
                var decl: AstNode = store.nodes.items[@intCast(usize, decls[di])];
                if (decl.kind == AstKind.fn_decl) {
                    var mf: []const u8 = "F";
                    pal.stderr_write(mf);
                } else {
                    var md: []const u8 = ".";
                    pal.stderr_write(md);
                }
            }
            var ok: []const u8 = "ok\n";
            pal.stderr_write(ok);
        }
    }
}
