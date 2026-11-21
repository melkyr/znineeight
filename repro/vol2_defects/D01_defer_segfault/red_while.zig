// D1 sibling shape: plain `defer` fn + `defer` inside a `while` body.
const std = @import("std");

fn plain() void {
    defer std.io.print("plain-defer\n", .{});
    std.io.print("plain-body\n", .{});
}

fn whileDefer() void {
    var i: i32 = 0;
    while (i < 2) : (i = i + 1) {
        defer std.io.print("while-defer\n", .{});
        std.io.print("while {}\n", .{i});
    }
}

pub fn main() void {
    plain();
    whileDefer();
}
