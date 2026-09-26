// D6 in-module RED: an annotated float tagged-union payload compiles (rc 0)
// but emits C that gcc rejects.
// gcc: incompatible types when assigning to type 'union <anonymous>' from type 'double'
const std = @import("std");

const ShapeF = union(enum) {
    circle: f32,
    empty,
};

pub fn main() void {
    var a: ShapeF = ShapeF{ .circle = 2.0 };
    std.io.print("f={}\n", .{a.circle});
}
