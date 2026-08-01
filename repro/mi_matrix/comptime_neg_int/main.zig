extern fn __bootstrap_print_int(x: i32) void;

const N = @intCast(i32, -5);

pub fn main() void {
    __bootstrap_print_int(N);
}
