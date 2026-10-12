const std = @import("std");
pub fn main() void {
    var minv: i64 = @intCast(i64, -9223372036854775808);
    var negone: i64 = -1;
    var maxv: i64 = @intCast(i64, 9223372036854775807);
    var twov: i64 = 2;
    var big: i64 = @intCast(i64, @intCast(u32, 3037000500));
    var one: i64 = 1;
    var x: i64 = 0;
    var e1: i64 = @intCast(i64, 9223372036854775807);
    var e2: i64 = @intCast(i64, -9223372036854775808);
    x = minv *| negone;
    if (x == e1) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(@intCast(u8, ' '));
    x = maxv *| twov;
    if (x == e1) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(@intCast(u8, ' '));
    x = minv *| twov;
    if (x == e2) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(@intCast(u8, ' '));
    x = big *| big;
    if (x == e1) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(@intCast(u8, ' '));
    x = maxv *| one;
    if (x == e1) { std.io.printInt(1); } else { std.io.printInt(0); }
    std.io.writeByte(@intCast(u8, ' '));
    x = minv *| one;
    if (x == e2) { std.io.printInt(1); } else { std.io.printInt(0); }
}
