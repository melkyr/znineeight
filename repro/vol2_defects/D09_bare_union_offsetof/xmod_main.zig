// D9 cross-module RED: the bare union comes from raw.zig.
const std = @import("std");
const raw = @import("raw.zig");

pub fn main() void {
    std.io.print("off_i={}\n", .{@offsetOf(raw.Raw, "i")});
}
