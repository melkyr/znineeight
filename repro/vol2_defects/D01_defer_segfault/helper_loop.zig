// D1 cross-module helper (split control): `defer` inside a `for` body.
const std = @import("std");

pub fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("helper-defer\n", .{});
        std.io.print("helper-loop {}\n", .{v});
    }
}
