// D1 cross-module helper: BOTH the plain `defer` function and the `for`-body
// `defer` function in one imported module (the crashing combination).
const std = @import("std");

pub fn plain() void {
    defer std.io.print("helper-plain-defer\n", .{});
    std.io.print("helper-plain-body\n", .{});
}

pub fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("helper-loop-defer\n", .{});
        std.io.print("helper-loop {}\n", .{v});
    }
}
