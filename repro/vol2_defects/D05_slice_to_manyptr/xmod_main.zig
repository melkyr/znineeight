// D5 cross-module RED: the slice is coerced to `[*]i32` at the call into
// helper.zig; gcc rejects the emitted C for the caller.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var arr = [3]i32{ 10, 20, 30 };
    const sl: []i32 = arr;
    std.io.print("first-ish={}\n", .{helper.first(sl)});
}
