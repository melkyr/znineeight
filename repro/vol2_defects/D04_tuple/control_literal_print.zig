// D4 control: tuple literals and `{}` printing of tuples work today.
const std = @import("std");

pub fn main() void {
    const anon = .{ 10, 20 };
    std.io.print("anon={}\n", .{anon});
    std.io.print("nested={}\n", .{.{ 1, .{ 2, 3 } }});
}
