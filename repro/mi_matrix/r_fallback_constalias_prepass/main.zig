const mod_a = @import("mod_a.zig");
const mod_b = @import("mod_b.zig");
const std = @import("std.zig");

pub fn main() void {
    var b = mod_b.makeBar();
    std.io.printInt(@intCast(i32, b.y));
}
