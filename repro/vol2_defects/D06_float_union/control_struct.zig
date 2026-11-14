// D6 control: annotated struct payloads work.
const std = @import("std");

const Shape = union(enum) {
    rect: struct { w: i32, h: i32 },
    empty,
};

pub fn main() void {
    var s: Shape = Shape{ .rect = .{ .w = 3, .h = 4 } };
    std.io.print("area={}\n", .{ s.rect.w * s.rect.h });
}
