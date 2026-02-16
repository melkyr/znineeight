extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(n: i32) void;

pub fn print(msg: []const u8) void {
    // Note: slice to pointer cast is handled by @ptrCast in bootstrap
    __bootstrap_print(@ptrCast([*]const u8, msg));
}

pub fn printInt(n: i32) void {
    __bootstrap_print_int(n);
}
