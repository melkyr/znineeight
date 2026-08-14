const std = @import("std");
const Point = struct { x: i32, y: i32 };
fn fail() !void {
    return error.Fail;
}
fn findPath() ?[]Point {
    _ = fail() catch return null;
    return null;
}
pub fn main() void {
    var p = findPath();
    if (p == null) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
