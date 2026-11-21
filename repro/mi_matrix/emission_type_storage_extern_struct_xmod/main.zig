const std = @import("std");
const mod_b = @import("mod_b.zig");
const mod_c = @import("mod_c.zig");
const Point = mod_b.Point;

pub fn main() void {
    var p = Point{ .x = 1, .y = 2 };
    std.io.printInt(@intCast(i32, mod_c.norm() + mod_b.sum(p)));
}
