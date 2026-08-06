extern fn __bootstrap_print_int(x: i32) void;

const A: i32 = 30;
const B: i32 = A + 5;
const C: i32 = B * 2;

pub fn main() void {
    __bootstrap_print_int(B);
    __bootstrap_print_int(C);
}
