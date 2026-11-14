const std = @import("std");

const Inner = union(enum) {
    a: struct { x: u32 },
    b: struct { y: u32 },
};

fn emitInst(i: Inner, wty: *u32) void {
    if (i.a) |v| {
        wty.* = v.x;
    }
}

pub fn main() void {
    var inst = Inner{ .a = .{ .x = 7 } };
    var w: u32 = 0;
    emitInst(inst, &w);
    std.io.printInt(@intCast(i32, w));
}
