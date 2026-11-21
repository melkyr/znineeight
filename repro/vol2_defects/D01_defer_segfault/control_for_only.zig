// D1 control: a `for`-body `defer` alone (no bare-defer fn) compiles and runs.
const std = @import("std");

fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("loop-defer\n", .{});
        std.io.print("loop {}\n", .{v});
    }
}

pub fn main() void {
    loopDefer();
}
