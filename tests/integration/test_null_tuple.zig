const S = struct { a: ?i32, b: ?i32 };
pub fn main() void {
    var s: S = .{ 1, null };
    _ = s;
}
