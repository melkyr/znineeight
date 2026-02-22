extern fn __bootstrap_print(s: *const u8) void;
extern fn __bootstrap_print_int(n: i32) void;

pub fn print(fmt: *const u8, args: anytype) void {
    __bootstrap_print(fmt);
}

pub fn printInt(n: i32) void {
    __bootstrap_print_int(n);
}
