const S = @import("types.zig").S;
pub fn main() void {
    var s = S{ .key = "ok", .val = 42 };
    _ = s;
}
