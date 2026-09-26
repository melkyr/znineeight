// D11 cross-module RED: the union type comes from shapes.zig and the
// qualified-prong switch is in main.zig.
const std = @import("std");
const shapes = @import("shapes.zig");

fn val(s: shapes.Shape) f32 {
    return switch (s) {
        shapes.Shape.circle => |r| r,
        else => 0,
    };
}

pub fn main() void {
    var s: shapes.Shape = shapes.Shape{ .circle = 2.0 };
    std.io.print("{}\n", .{val(s)});
}
