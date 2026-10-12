const std = @import("std");

var counter: u32 = 5;
var grid: [4]u32 = [4]u32{ 1, 2, 3, 4 };

fn bump() void {
    counter = counter + 1;
}

fn addPair(x: u32, y: u32) u32 {
    return x + y;
}

fn scale(v: u32) u32 {
    return v * 2;
}

pub fn main() void {
    var a = counter;
    bump();
    std.io.printInt(@intCast(i32, a));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, counter));
    std.io.writeByte('\n');
    var t = a - 1;
    std.io.printInt(@intCast(i32, t));
    std.io.writeByte('\n');
    var u = addPair(grid[0], grid[1]);
    std.io.printInt(@intCast(i32, u));
    std.io.writeByte('\n');
    var v = scale(grid[2]);
    std.io.printInt(@intCast(i32, v));
    std.io.writeByte('\n');
    var w = t + u;
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte('\n');
    var x = counter - a;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
