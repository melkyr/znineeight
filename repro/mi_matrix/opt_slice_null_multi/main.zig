const std = @import("std");
const Point = struct { x: i32, y: i32 };
fn failA() !void { return error.A; }
fn failB() !void { return error.B; }
fn findPath(flag: i32) ?[]Point {
    if (flag == @intCast(i32, 1)) {
        _ = failA() catch return null;
    }
    if (flag == @intCast(i32, 2)) {
        _ = failB() catch return null;
    }
    return null;
}
pub fn main() void {
    var p1 = findPath(@intCast(i32, 1));
    var p2 = findPath(@intCast(i32, 2));
    var p3 = findPath(@intCast(i32, 0));
    if (p1 == null and p2 == null and p3 == null) {
        std.io.printInt(@intCast(i32, 1));
    } else {
        std.io.printInt(@intCast(i32, 0));
    }
}
