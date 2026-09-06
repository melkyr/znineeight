const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitSizeOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u12)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u20)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @sizeOf(u33)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @alignOf(u3)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, @bitSizeOf(i7)));
    std.io.writeByte('\n');
}
