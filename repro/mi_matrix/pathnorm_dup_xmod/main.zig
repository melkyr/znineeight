const std = @import("std");
const mod = @import("mod.zig");

pub fn main() void {
    std.io.printInt(@intCast(i32, mod.modValue()));
}
