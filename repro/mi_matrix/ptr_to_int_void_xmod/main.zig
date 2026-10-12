const std = @import("std");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var buf: [10]u8 = undefined;
    var addr: usize = lib_mod.getPtrAddr(&buf[0]);
    if (addr != @intCast(usize, 0)) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
