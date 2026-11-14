const std = @import("std");

const Buf = [10]u8;

pub fn main() void {
    var b: Buf = undefined;
    b[0] = @intCast(u8, 3);
    std.io.printInt(@intCast(i32, b[0]));
}
