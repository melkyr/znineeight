const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var t = mod_b.resolveType(5);
    t = mod_b.lookupType(t);
    std.io.printInt(@intCast(i32, t));
}
