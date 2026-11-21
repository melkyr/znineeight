const lexer_mod = @import("../lexer.zig");
const pal = @import("../pal.zig");

pub fn main(argc: i32, argv: [*]*const u8) void {
    pal.initArgs(argc, argv);
    lexer_mod.lexerRunAllTests();
    var ok: []const u8 = "Lexer tests passed.\n";
    pal.stderr_write(ok);
}
