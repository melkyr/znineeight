const std = @import("std");

pub fn main() void {
    var a: u63 = @intCast(u63, 9223372036854775807);
    var b: u63 = @intCast(u63, 1);
    var s = a + b;
    std.io.printInt(@intCast(i64, s));
    std.io.writeByte('\n');
    var n: i63 = @intCast(i63, -1);
    std.io.printInt(@intCast(i64, n));
    std.io.writeByte('\n');
}
