const mod_b = @import("mod_b.zig");
const std = @import("std.zig");

pub fn main() void {
    var b = mod_b.makePoint();
    std.io.printInt(@intCast(i32, b.y));
}
