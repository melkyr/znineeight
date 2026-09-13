pub const Point = struct {
    x: i32,
    y: i32,
};

pub const Color = enum {
    Red,
    Green,
    Blue,
};

pub fn sumX(p: Point) i32 {
    return p.x + p.y;
}

pub fn colorInt(c: Color) i32 {
    return switch (c) {
        .Red => 0,
        .Green => 1,
        .Blue => 2,
    };
}
