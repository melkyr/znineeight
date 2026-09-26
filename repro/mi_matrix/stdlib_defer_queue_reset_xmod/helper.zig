// FG cross-module trigger for stdlib_defer_queue_reset_xmod: BOTH the
// plain-`defer` function and the `for`-body-`defer` function live in this one
// module, so the pre-fix compiler crashes while analyzing this module even
// though main.zig only calls them (the D1 trigger is per-module).
const std = @import("std");

pub fn plainFirst() void {
    defer std.io.print("helpplain-defer\n", .{});
    std.io.print("helpplain-body\n", .{});
}

pub fn forDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("helpfor-defer\n", .{});
        std.io.print("helpfor {}\n", .{v});
    }
}
