const Path = struct { x: i32, y: i32 };
fn fail() !void {
    return error.Fail;
}
pub fn findPath() ?[]Path {
    _ = fail() catch return null;
    return null;
}
