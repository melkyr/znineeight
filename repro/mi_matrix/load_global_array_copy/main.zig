extern fn __bootstrap_print_int(n: i32) void;
pub var buf: [16]i32 = undefined;
pub fn main() void {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        buf[i] = @intCast(i32, i);
    }
    __bootstrap_print_int(buf[3]);
    __bootstrap_print_int(buf[15]);
}
