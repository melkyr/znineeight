// D1 control: a no-`defer` function next to a `for`-body-`defer` function
// compiles and runs.
const std = @import("std");

fn noDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        std.io.print("plain-loop {}\n", .{v});
    }
}

fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("loop-defer\n", .{});
        std.io.print("loop {}\n", .{v});
    }
}

pub fn main() void {
    noDefer();
    loopDefer();
}
