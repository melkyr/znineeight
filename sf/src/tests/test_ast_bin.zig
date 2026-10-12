const alloc_mod = @import("../allocator.zig");
const ast_tests = @import("../tests/ast_tests.zig");
const pal = @import("../pal.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    ast_tests.runAstUnitTests();
    var ok: []const u8 = "AST tests passed.\n";
    pal.stderr_write(ok);
}
