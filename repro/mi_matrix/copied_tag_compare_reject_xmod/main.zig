const std = @import("std");

const Shape = union(enum) {
    Circle: i32,
    Square: f64,
    Empty,
    Line: u32,
};

pub fn main() void {
    var s: Shape = Shape{ .Circle = @intCast(i32, 7) };
    const t = s.tag;
    if (t == .Circle) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (t != .Square) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (t < .Empty) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (.Square == t) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (.Circle < t) { std.io.printInt(1); } else { std.io.printInt(0); }
    if (t >= .Circle) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte('\n');
}
