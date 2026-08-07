extern fn __bootstrap_print_int(n: i32) void;
const Point = struct { x: i32, y: i32 };
fn fail() !void {
    return error.Fail;
}
fn findPath() ?[]Point {
    _ = fail() catch return null;
    return null;
}
pub fn main() void {
    var p = findPath();
    if (p == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
