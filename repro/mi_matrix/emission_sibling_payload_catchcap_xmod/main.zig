const std = @import("std");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    std.io.printInt(@intCast(i32, mod_b.run()));
}
