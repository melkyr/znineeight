const alloc_mod = @import("allocator.zig");
const interner_mod = @import("string_interner.zig");
const sm_mod = @import("source_manager.zig");
const diag_mod = @import("diagnostics.zig");
const token_mod = @import("token.zig");
const lexer_mod = @import("lexer.zig");
const pal = @import("pal.zig");
const ast_mod = @import("ast.zig");
const parser_mod = @import("parser.zig");
const ast_tests = @import("tests/ast_tests.zig");
const parser_tests = @import("tests/parser_tests.zig");
const Token = @import("token.zig").Token;
const TokenKind = @import("token.zig").TokenKind;
const StringInterner = @import("string_interner.zig").StringInterner;
const DiagnosticCollector = @import("diagnostics.zig").DiagnosticCollector;
const Sand = @import("allocator.zig").Sand;

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var perm_buf: [1024 * 1024]u8 = undefined;
    var perm_sand = alloc_mod.sandInit(perm_buf[0..]);
    var interner = interner_mod.stringInternerInit(&perm_sand, 4);
    var source_man = sm_mod.sourceManagerInit(&perm_sand);
    var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
    var store = ast_mod.astStoreInit(&perm_sand);
    token_mod.initKeywordTable(&perm_sand);

    lexer_mod.lexerRunAllTests();
    const m1: []const u8 = "\n";
    pal.stderr_write(m1);

    ast_tests.runAstUnitTests();
    parser_tests.runParserUnitTests();
    const m2: []const u8 = "\n";
    pal.stderr_write(m2);

    testMandelbrotParse(&perm_sand, &interner, &diag, &store);
    const m3: []const u8 = "All ast/parser tests passed.\n";
    pal.stderr_write(m3);
}

fn testMandelbrotParse(sand: *Sand, interner: *StringInterner, diag: *DiagnosticCollector, store: *AstStore) void {
    var mandel_path: []const u8 = "examples/mandelbrot/mandelbrot.zig";
    var mb = pal.readFile(mandel_path, sand) orelse return;
    var tokens: [512]Token = undefined;
    var lex = lexer_mod.lexerInit(mb, @intCast(u32, 0), interner, diag, sand);
    var i: usize = 0;
    while (i < 512) {
        var tok = lexer_mod.lexerNextToken(&lex);
        tokens[i] = tok;
        i += 1;
        if (tok.kind == TokenKind.eof) break;
    }
    var p = parser_mod.parserInit(tokens[0..i], mb, store, interner, diag, sand);
    var root = parser_mod.parserParseModuleRoot(&p) catch unreachable;
    _ = root;
    var ok: []const u8 = "OK: mandelbrot.zig parsed\n";
    pal.stderr_write(ok);
}

const AstStore = @import("ast.zig").AstStore;
