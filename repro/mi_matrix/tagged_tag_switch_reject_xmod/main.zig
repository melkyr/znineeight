const std = @import("std");
const lib = @import("helper.zig");

const Shape = union(enum) {
    Circle: i32,
    Square: f64,
};

pub fn main() void {
    var s: Shape = Shape{ .Circle = @intCast(i32, 7) };
    switch (s.tag) {
        .Bogus => { std.io.printInt(1); },
        else => { std.io.printInt(9); },
    }
    switch (s.tag) {
        lib.Other.Red => { std.io.printInt(2); },
        else => { std.io.printInt(9); },
    }
    std.io.writeByte('\n');
}
