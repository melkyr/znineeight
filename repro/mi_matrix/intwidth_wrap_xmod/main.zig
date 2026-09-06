const std = @import("std");

pub fn main() void {
    var a: u3 = @intCast(u3, 7);
    var b: u3 = @intCast(u3, 1);
    var w = a + b;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte('\n');
    var x: u12 = @intCast(u12, 4095);
    var y: u12 = @intCast(u12, 1);
    var w2 = x + y;
    std.io.printInt(@intCast(i32, w2));
    std.io.writeByte('\n');
}
