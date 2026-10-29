// Off-corpus mutable-for fixture (Task 4 Step 1h): nested mutable captures
// with distinct names. The outer item pointer and the inner item pointer must
// both address their own arrays; the printed values prove both writes landed.
const std = @import("std");

pub fn main() void {
    var a: [3]u32 = [3]u32{ 0, 0, 0 };
    var b: [2]u32 = [2]u32{ 10, 20 };
    for (a) |*x| {
        x.* += 1;
        for (b) |*y| {
            y.* += 1;
        }
    }
    std.io.printInt(@intCast(i32, a[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, a[2]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, b[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, b[1]));
    std.io.writeByte('\n');
}
