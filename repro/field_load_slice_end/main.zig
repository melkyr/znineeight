extern fn __bootstrap_print_int(x: i32) void;
const T = struct { input: []const u8, pos: usize };
fn scan(self: *T, start: usize) usize {
    const slice = self.input[start..self.pos];
    return slice.len;
}
pub fn main() void {
    var buf: [8]u8 = [8]u8{ @intCast(u8, 0), @intCast(u8, 1), @intCast(u8, 2), @intCast(u8, 3), @intCast(u8, 4), @intCast(u8, 5), @intCast(u8, 6), @intCast(u8, 7) };
    var t: T = T{ .input = buf[0..8], .pos = @intCast(usize, 5) };
    __bootstrap_print_int(@intCast(i32, scan(&t, @intCast(usize, 2))));
}
