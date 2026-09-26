// D11 sibling shape: multiple qualified prongs, each with a capture.
const std = @import("std");

const Shape = union(enum) {
    circle: f32,
    rect: struct { w: i32, h: i32 },
    empty,
};

fn describe(s: Shape) i32 {
    return switch (s) {
        Shape.circle => |r| @intCast(i32, r),
        Shape.rect => |rc| rc.w + rc.h,
        Shape.empty => 0,
    };
}

pub fn main() void {
    var a: Shape = Shape{ .circle = 2.0 };
    var b: Shape = Shape{ .rect = .{ .w = 3, .h = 4 } };
    std.io.print("a={} b={}\n", .{ describe(a), describe(b) });
}
