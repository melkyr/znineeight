// D6 sibling shape: anonymous payload literal `.{ .circle = 3.0 }` with an
// annotated declaration.
const std = @import("std");

const ShapeF = union(enum) {
    circle: f32,
    empty,
};

pub fn main() void {
    var c: ShapeF = .{ .circle = 3.0 };
    std.io.print("f2={}\n", .{c.circle});
}
