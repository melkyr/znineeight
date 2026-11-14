extern fn __bootstrap_print_int(n: i32) void;

pub fn printInt(n: i32) void {
    __bootstrap_print_int(n);
}
