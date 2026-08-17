const std = @import("std");
const P = [*]u8;
pub fn main() void {
    var arr: [4]u8 = .{ 1, 2, 3, 4 };
    var q: P = @ptrCast(P, &arr);
    std.io.printInt(@intCast(i32, q[0]));
}
