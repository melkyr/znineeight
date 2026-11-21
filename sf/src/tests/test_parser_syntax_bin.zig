const alloc_mod = @import("../allocator.zig");
const interner_mod = @import("../string_interner.zig");
const sm_mod = @import("../source_manager.zig");
const diag_mod = @import("../diagnostics.zig");
const token_mod = @import("../token.zig");
const ast_mod = @import("../ast.zig");
const parser_mod = @import("../parser.zig");
const parser_tests = @import("../tests/parser_tests.zig");
const pal = @import("../pal.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    parser_tests.runCriticalPatternTests();
    var m: []const u8 = "\n";
    pal.stderr_write(m);
    var ok: []const u8 = "Critical pattern tests passed.\n";
    pal.stderr_write(ok);
}
