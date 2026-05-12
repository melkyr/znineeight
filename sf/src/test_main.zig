const alloc_mod = @import("allocator.zig");
const interner_mod = @import("string_interner.zig");
const sm_mod = @import("source_manager.zig");
const diag_mod = @import("diagnostics.zig");
const token_mod = @import("token.zig");
const lexer_mod = @import("lexer.zig");
const pal = @import("pal.zig");
const ast_mod = @import("ast.zig");
const ast_tests = @import("tests/ast_tests.zig");
const parser_tests = @import("tests/parser_tests.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    var compiler_alloc = alloc_mod.initCompilerAlloc();
    var perm_sand = compiler_alloc.permanent;
    var interner = interner_mod.stringInternerInit(&perm_sand, 4);
    var source_man = sm_mod.sourceManagerInit(&perm_sand);
    var diag = diag_mod.diagnosticCollectorInit(&perm_sand, &source_man, &interner);
    compiler_alloc.permanent = perm_sand;
    token_mod.initKeywordTable(&perm_sand);

    lexer_mod.lexerRunAllTests();
    const m1: []const u8 = "\n";
    pal.stderr_write(m1);

    ast_tests.runAstUnitTests();
    parser_tests.runParserUnitTests();
    const m2: []const u8 = "All ast/parser tests passed.\n";
    pal.stderr_write(m2);
}
