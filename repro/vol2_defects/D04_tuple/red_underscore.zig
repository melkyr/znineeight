// D4 sibling shape: `t._0` (underscore field spelling) is also error[3060].
const std = @import("std");

pub fn main() void {
    const anon = .{ 10, 20 };
    std.io.print("elem0={}\n", .{anon._0});
}
