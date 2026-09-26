// D11 sibling shape: a qualified prong with a struct payload capture.
const std = @import("std");

const Shape = union(enum) {
    circle: f32,
    rect: struct { w: i32, h: i32 },
    empty,
};

fn area(s: Shape) i32 {
    return switch (s) {
        Shape.rect => |rc| rc.w * rc.h,
        else => 0,
    };
}

pub fn main() void {
    var s: Shape = Shape{ .rect = .{ .w = 3, .h = 4 } };
    std.io.print("area={}\n", .{area(s)});
}
