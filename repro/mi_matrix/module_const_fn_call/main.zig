extern fn __bootstrap_print_int(n: i32) void;

fn getInit() i32 { return 42; }
const x: i32 = getInit();

pub fn main() void {
    __bootstrap_print_int(x);
}
