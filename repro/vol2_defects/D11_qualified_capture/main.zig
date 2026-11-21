// D11 in-module RED: a qualified prong with a payload capture leaves the
// capture unbound: error[20]: identifier 'r' is not declared.
const std = @import("std");

const Shape = union(enum) {
    circle: f32,
    rect: struct { w: i32, h: i32 },
    empty,
};

fn val(s: Shape) f32 {
    return switch (s) {
        Shape.circle => |r| r,
        else => 0,
    };
}

pub fn main() void {
    var s: Shape = Shape{ .circle = 2.0 };
    std.io.print("{}\n", .{val(s)});
}
