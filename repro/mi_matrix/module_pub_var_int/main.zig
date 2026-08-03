extern fn __bootstrap_print_int(n: i32) void;

pub var x: i32 = 42;

pub fn main() void {
    x = x + 1;
    __bootstrap_print_int(x);
}
