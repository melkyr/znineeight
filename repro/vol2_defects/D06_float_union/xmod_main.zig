// D6 cross-module RED: the union type comes from shapes.zig; the annotated
// float init stays in main.zig.
const std = @import("std");
const shapes = @import("shapes.zig");

pub fn main() void {
    var a: shapes.ShapeF = shapes.ShapeF{ .circle = 2.0 };
    std.io.print("f={}\n", .{a.circle});
}
