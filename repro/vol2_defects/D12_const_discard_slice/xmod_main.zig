// D12 cross-module RED: a `[]const i32` is passed to an imported helper that
// takes `[]i32`; warning-only, then the mutation lands.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var arr = [3]i32{ 1, 2, 3 };
    const c: []const i32 = arr;
    helper.take(c);
    std.io.print("m0={}\n", .{arr[0]});
}
