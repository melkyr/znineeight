const std = @import("std");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var p = lib_mod.alloc(@intCast(u32, 16));
    std.io.printInt(@intCast(i32, @ptrToInt(p) == @intCast(usize, 0)));
}
