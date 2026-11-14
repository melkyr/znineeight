// D3 cross-module RED entry point.
const std = @import("std");
const picker = @import("picker.zig");

pub fn main() void {
    std.io.print("matched={}\n", .{picker.pick(1)});
    std.io.print("unmatched={}\n", .{picker.pick(7)});
    std.io.print("unmatched_else={}\n", .{picker.pickElse(7)});
}
