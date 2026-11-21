const std = @import("std");
pub var buf: [16]i32 = undefined;
pub fn main() void {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        buf[i] = @intCast(i32, i);
    }
    std.io.printInt(buf[3]);
    std.io.printInt(buf[15]);
}
