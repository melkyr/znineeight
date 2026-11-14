// D4 sibling shape: `t.0` member access on an anonymous tuple literal is
// rejected with error[3060].
const std = @import("std");

pub fn main() void {
    const anon = .{ 10, 20 };
    std.io.print("elem0={}\n", .{anon.0});
}
