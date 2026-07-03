pub const Point = struct {
    x: u8,
    y: u8,
};

pub fn Point_eq(a: Point, b: Point) bool {
    return a.x == b.x and a.y == b.y;
}
