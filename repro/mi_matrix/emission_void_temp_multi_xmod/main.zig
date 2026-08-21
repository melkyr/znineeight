const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var lex = mod_b.Lexer{ .pos = 0 };
    var t = mod_b.nextToken(lex);
    std.io.printInt(@intCast(i32, t.start));
}
