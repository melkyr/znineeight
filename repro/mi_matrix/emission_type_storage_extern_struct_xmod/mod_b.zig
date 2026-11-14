const mod_a = @import("mod_a.zig");

pub const Point = mod_a.Point;

pub fn sum(p: Point) u32 {
    return p.x + p.y;
}
