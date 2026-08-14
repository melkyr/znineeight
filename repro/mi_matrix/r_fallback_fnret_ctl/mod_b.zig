pub const Point = struct { x: i32, y: i32 };

pub fn makePoint() Point {
    var p = Point{ .x = 10, .y = 20 };
    return p;
}
