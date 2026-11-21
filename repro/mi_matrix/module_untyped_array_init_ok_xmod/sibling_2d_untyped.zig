// D12 sibling probe: module-scope 2-D untyped array literal. Same D12 class
// as the 1-D shape; the typed control is `multiarray_literal_init_xmod`.
const std = @import("std");

var g: [2][3]u8 = .{ .{ 1, 2, 3 }, .{ 4, 5, 6 } };

pub fn main() void {
    g[1][2] = 9;
    std.io.printInt(@intCast(i32, g[0][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g[0][1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g[0][2]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g[1][0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g[1][1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, g[1][2]));
    std.io.writeByte('\n');
}
