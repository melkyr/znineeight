const S = struct { key: []const u8, val: i32 };
pub fn main() void {
    var s = S{ .key = "ok", .val = 42 };
    _ = s;
}
