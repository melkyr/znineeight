const lib_mod = @import("lib.zig");
const std = @import("std");

pub fn main() void {
    var v = lib_mod.makeValue(@intCast(i32, 7));
    std.io.printInt(@intCast(i32, v.data.I));
    std.io.printInt(@intCast(i32, @sizeOf(lib_mod.Data)));
    std.io.printInt(@intCast(i32, @sizeOf(lib_mod.Value)));
}
