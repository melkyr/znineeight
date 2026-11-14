extern fn __bootstrap_print(s: *const c_char) void;

pub fn print(fmt: *const c_char, args: anytype) void {
    __bootstrap_print(fmt);
}
