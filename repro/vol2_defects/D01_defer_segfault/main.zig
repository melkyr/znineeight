// D1 in-module RED: one function with a plain `defer` plus another function
// with a `defer` inside a `for` body makes the compiler SIGSEGV (rc 139).
const std = @import("std");

fn plain() void {
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn loopDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |v| {
        defer std.io.print("loop-defer\n", .{});
        std.io.print("loop {}\n", .{v});
    }
}

pub fn main() void {
    plain();
    loopDefer();
}
