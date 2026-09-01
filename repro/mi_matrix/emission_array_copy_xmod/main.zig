const std = @import("std");
const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");

pub fn main() void {
    var t = mod_b.copyArr();
    t = mod_a.addOne(t);
    std.io.printInt(@intCast(i32, t));
}
