const Point = struct { x: i32, y: i32 };
pub fn main() void {
    const p = Point { .x = 1, .y = 2 };
    _ = p;
}
