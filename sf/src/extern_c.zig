pub extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;
pub extern fn __bootstrap_print(s: [*]const u8) void;
pub extern fn __bootstrap_print_int(n: i32) void;
