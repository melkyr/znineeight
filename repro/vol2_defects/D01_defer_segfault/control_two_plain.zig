// D1 control: two bare-`defer` functions compile and run.
const std = @import("std");

fn one() void {
    defer std.io.print("d1\n", .{});
    std.io.print("b1\n", .{});
}

fn two() void {
    defer std.io.print("d2\n", .{});
    std.io.print("b2\n", .{});
}

pub fn main() void {
    one();
    two();
}
