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
const AstStore = ast_mod.AstStore;
const AstKind = ast_mod.AstKind;
const diag_mod = @import("../diagnostics.zig");
const DiagnosticCollector = diag_mod.DiagnosticCollector;
const pal = @import("../pal.zig");

var perm_buf: [65536]u8 = undefined;
var scratch_buf: [32768]u8 = undefined;
var tok_buf: [4096]Token = undefined;

fn writeU32(val: usize) void {
    var buf: [20]u8 = undefined;
    if (val == 0) {
        var s: []const u8 = "0";
        pal.stderr_write(s);
        return;
    }
    var i: usize = @intCast(usize, 20);
    buf[@intCast(usize, 19)] = '0' + @intCast(u8, val % 10);
    var v = val;
    while (v > 0) : (v = v / 10) {
        i -= 1;
        buf[i] = '0' + @intCast(u8, v % 10);
    }
    pal.stderr_write(buf[i..@intCast(usize, 20)]);
}

pub fn main() void {
    pal.initArgs(@intCast(i32, 0), undefined);
    var perm = alloc_mod.sandInit(perm_buf[0..]);
    var scratch = alloc_mod.sandInit(scratch_buf[0..]);
    token_mod.initKeywordTable(&perm);
    var interner = interner_mod.stringInternerInit(&perm, 4);
    var diag = diag_mod.diagnosticCollectorInit(&perm, undefined, &interner);
    var content: []const u8 = "fn foo() void { bar(); }";
    var lex = lexer_mod.lexerInit(content, @intCast(u32, 0), &interner, &diag, &scratch);
    var tok_len: usize = @intCast(usize, 0);
    while (true) {
        var t = lexer_mod.lexerNextToken(&lex);
        tok_buf[tok_len] = t;
        tok_len += 1;
        if (t.kind == TokenKind.eof) break;
    }
    var store = ast_mod.astStoreInit(&perm);
    var p = parser_mod.parserInit(tok_buf[0..tok_len], content, &store, &interner, &diag, &perm);
    var ast_root = parser_mod.parserParseModuleRoot(&p) catch {
        var e: []const u8 = "FAIL: parse error\n";
        pal.stderr_write(e);
        pal.exit(1);
        return;
    };
    var root = ast_mod.astStoreNodeAt(&store, ast_root);
    if (root.kind != AstKind.module_root) {
        var e: []const u8 = "FAIL: not module_root\n";
        pal.stderr_write(e);
        pal.exit(1);
        return;
    }
    var decls = ast_mod.astStoreNodeExtraChildren(&store, ast_root);
    var fm: []const u8 = "decls.len=";
    pal.stderr_write(fm);
    writeU32(decls.len);
    var nl2: []const u8 = "\n";
    pal.stderr_write(nl2);
    var di: usize = 0;
    while (di < decls.len) : (di += 1) {
        var d = ast_mod.astStoreNodeAt(&store, decls[di]);
        if (d.kind == AstKind.fn_decl) {
            var body_idx = d.child_0;
            var body = ast_mod.astStoreNodeAt(&store, body_idx);
            var fm2: []const u8 = "body.kind=";
            pal.stderr_write(fm2);
            writeU32(@intCast(usize, @intCast(u32, body.kind)));
            var fm3: []const u8 = " child_0=";
            pal.stderr_write(fm3);
            writeU32(@intCast(usize, body.child_0));
            var nl: []const u8 = "\n";
            pal.stderr_write(nl);
            if (body.kind == AstKind.block) {
                var ec = ast_mod.astStoreNodeExtraChildren(&store, body_idx);
                var fm4: []const u8 = "block children count=";
                pal.stderr_write(fm4);
                writeU32(ec.len);
                var nl3: []const u8 = "\n";
                pal.stderr_write(nl3);
            }
        }
    }
    var ok: []const u8 = "ok\n";
    pal.stdout_write(ok);
}
