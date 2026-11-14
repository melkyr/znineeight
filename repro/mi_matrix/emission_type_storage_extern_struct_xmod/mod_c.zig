const Point = @import("mod_a.zig").Point;
const P = Point;

pub fn norm() u32 {
    var p: P = P{ .x = 1, .y = 2 };
    return p.x + p.y;
}
