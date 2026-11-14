// D11 control: the anonymous-shorthand prong `.rect => |rc|` binds the
// capture and works. (A float payload would trip the unrelated D6 gcc bug, so
// this control uses the struct payload.)
const std = @import("std");

const Shape = union(enum) {
    circle: f32,
    rect: struct { w: i32, h: i32 },
    empty,
};

fn area(s: Shape) i32 {
    return switch (s) {
        .rect => |rc| rc.w * rc.h,
        else => 0,
    };
}

pub fn main() void {
    var s: Shape = Shape{ .rect = .{ .w = 3, .h = 4 } };
    std.io.print("{}\n", .{area(s)});
}
