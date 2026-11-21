const std = @import("std");
const lib = @import("helper.zig");

const Box = struct { w: i32, h: i32 };
const U = union(enum) {
    i: i32,
    box: Box,
    n: i32,
};

var g: U = U{ .i = 1 };

fn setPayload(p: *U) void {
    p.i = 5;
}

pub fn main() void {
    var x: U = U{ .i = 1 };
    x.i = 5;
    var b: U = U{ .box = Box{ .w = 1, .h = 2 } };
    b.box = .{ .w = 3, .h = 4 };
    b.box.w = 7;
    g.i = 5;
    setPayload(&x);
    var y: U = U{ .i = 1 };
    y.i += 5;
    const ap = &y.i;
    _ = ap;
    var z: lib.U = lib.U{ .i = 1 };
    z.i = 5;
    z.box.w = 7;
    std.io.writeByte('\n');
}
