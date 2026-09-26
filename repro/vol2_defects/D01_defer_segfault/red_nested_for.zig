// D1 sibling shape: plain `defer` fn + `defer` inside a nested `for` body.
const std = @import("std");

fn plain() void {
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn nestedForDefer() void {
    const arr = [2]i32{ 1, 2 };
    for (arr) |a| {
        for (arr) |b| {
            defer std.io.print("nested-defer\n", .{});
            std.io.print("nested {} {}\n", .{ a, b });
        }
    }
}

pub fn main() void {
    plain();
    nestedForDefer();
}
