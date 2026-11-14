const lib_mod = @import("lib.zig");
const std = @import("std");

pub fn main() void {
    std.io.printInt(lib_mod.compute(@intCast(i32, 0)));
}
