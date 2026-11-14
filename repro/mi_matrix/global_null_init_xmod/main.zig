const std = @import("std");
const lib_mod = @import("lib.zig");

pub fn main() void {
    var p = lib_mod.get();
    if (p == null) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
