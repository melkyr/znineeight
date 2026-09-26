// D10 cross-module RED: the single-item pointer is indexed in helper.zig.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var arr = [2]i32{ 7, 8 };
    const p: *i32 = &arr[0];
    std.io.print("helper={}\n", .{helper.atOne(p)});
}
