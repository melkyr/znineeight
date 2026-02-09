const std = @import("std");  // Will be rejected
fn generic(comptime T: type, x: T) T { return x; }
fn errorFunc() !void { return error.Test; }
fn main() void {
    var x = generic(i32, 42);
    _ = errorFunc() catch {};
}
