const Point = struct { x: i32, y: i32 };

fn fail() !void {
    return error.Fail;
}

pub fn findPath() ?[]Point {
    _ = fail() catch return null;
    return null;
}

pub fn main() void {
    _ = findPath();
}
