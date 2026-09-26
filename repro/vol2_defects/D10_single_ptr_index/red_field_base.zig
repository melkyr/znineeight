// D10 sibling shape: indexing a single-item pointer-to-struct, then field
// access (`ps[0].x`).
const std = @import("std");

const Point = struct { x: i32, y: i32 };

pub fn main() void {
    var pt: Point = .{ .x = 5, .y = 6 };
    const ps: *Point = &pt;
    std.io.print("ps[0].x={} ps.x={}\n", .{ ps[0].x, ps.x });
}
