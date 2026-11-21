// D6 sibling shape: an INFERRED (unannotated) f32 payload declaration fails
// the same way -- the defect is the f32 payload, not the annotation.
const std = @import("std");

const ShapeF = union(enum) {
    circle: f32,
    empty,
};

pub fn main() void {
    var v = ShapeF{ .circle = 2.0 };
    std.io.print("f={}\n", .{v.circle});
}
