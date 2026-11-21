// D6 sibling shape: f64 payload, annotated.
const std = @import("std");

const ShapeD = union(enum) {
    circle: f64,
    empty,
};

pub fn main() void {
    var a: ShapeD = ShapeD{ .circle = 2.0 };
    std.io.print("d={}\n", .{a.circle});
}
