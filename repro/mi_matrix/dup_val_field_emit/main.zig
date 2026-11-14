const Point = struct {
    x: i32,
    y: i32,
};

const Line = struct {
    a: Point,
    b: Point,
};

pub fn main() void {
    var l: Line = undefined;
    l.a.x = 1;
    l.b.y = 2;
    _ = l;
}
