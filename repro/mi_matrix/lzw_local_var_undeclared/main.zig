pub fn main() void {
    var code: i32 = 42;
    if (code == 0) {
        _ = code;
    } else {
        var buf: [10]u8 = undefined;
        var i: usize = 0;
        var n = code;
        while (n > 0) {
            buf[i] = @intCast(u8, @intCast(i32, '0') + (n % 10));
            n /= 10;
            i += 1;
        }
        while (i > 0) {
            i -= 1;
            _ = buf[i];
        }
    }
}
