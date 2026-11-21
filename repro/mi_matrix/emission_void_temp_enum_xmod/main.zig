const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var lex = mod_b.Lexer{ .pos = 0 };
    std.io.printInt(mod_b.nextToken(lex));
}
