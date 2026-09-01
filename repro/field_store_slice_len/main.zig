extern fn __bootstrap_print_int(x: i32) void;
pub fn main() void {
    var arr: [4]u8 = [4]u8{ @intCast(u8, 1), @intCast(u8, 2), @intCast(u8, 3), @intCast(u8, 4) };
    var s: []u8 = arr[0..4];
    s.len = @intCast(usize, 2);
    __bootstrap_print_int(@intCast(i32, s.len));
}
