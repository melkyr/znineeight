const std = @import("std");

pub fn main() void {
    var t: u3 = @intCast(u3, 255);
    std.io.printInt(@intCast(i32, t));
    std.io.writeByte('\n');
    var c: u8 = @intCast(u8, 256);
    std.io.printInt(@intCast(i32, c));
    std.io.writeByte('\n');
    var u: u8 = @intCast(u8, 255);
    var w3: u8 = @intCast(u8, u);
    std.io.printInt(@intCast(i32, w3));
    std.io.writeByte('\n');
}
