const S = struct { a: i32, b: i32 };
pub fn main() void {
    var s = S{ .a = 1, .b = 2 };
    s.a = 5;
    _ = s;
}
