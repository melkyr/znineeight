const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const token_mod = @import("../token.zig");
const ast_mod = @import("../ast.zig");
const parser_mod = @import("../parser.zig");
const parser_tests = @import("../tests/parser_tests.zig");
const ast_tests = @import("../tests/ast_tests.zig");
const pal = @import("../pal.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    ast_tests.runAstUnitTests();
    var m: []const u8 = "\n";
    pal.stderr_write(m);
    parser_tests.runParserUnitTests();
    var ok: []const u8 = "Parser tests passed.\n";
    pal.stderr_write(ok);
}
