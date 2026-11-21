const S = @import("types.zig").S;
pub fn main() void {
    var s = S{ .a = 1, .b = 2 };
    s.a = 5;
    _ = s;
}
