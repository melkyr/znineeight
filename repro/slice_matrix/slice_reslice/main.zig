extern fn __bootstrap_print_int(i: i32) void;
pub fn main() void {
    var a: [8]u8 = undefined;
    var i: usize = 0;
    while (i < 8) { a[i] = @intCast(u8, i); i += 1; }
    var base: []u8 = a[0..];
    var s: []u8 = base[1..3];
    __bootstrap_print_int(@intCast(i32, s.len));
    __bootstrap_print_int(@intCast(i32, s[0]));
}
