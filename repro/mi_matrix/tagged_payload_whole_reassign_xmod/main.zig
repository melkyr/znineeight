const std = @import("std");
const lib = @import("helper.zig");

const Box = struct { w: i32, h: i32 };
const U = union(enum) {
    i: i32,
    box: Box,
    n: i32,
};

fn whole(p: *U) i32 {
    p.* = U{ .i = 21 };
    return p.i;
}

pub fn main() void {
    var x: U = U{ .i = 1 };
    x = .{ .i = 5 };
    std.io.printInt(x.i);
    std.io.writeByte(' ');
    x = .{ .box = Box{ .w = 7, .h = 8 } };
    std.io.printInt(x.box.w);
    std.io.writeByte(' ');
    var y: lib.U = lib.U{ .i = 1 };
    y = .{ .i = 9 };
    std.io.printInt(y.i);
    std.io.writeByte(' ');
    y = lib.U{ .box = lib.Box{ .w = 11, .h = 12 } };
    std.io.printInt(y.box.w);
    std.io.writeByte(' ');
    var z: U = U{ .i = 1 };
    std.io.printInt(whole(&z));
    std.io.writeByte(' ');
    switch (x) {
        .box => |b| { std.io.printInt(b.w); },
        else => { std.io.printInt(0); },
    }
    std.io.writeByte('\n');
}
