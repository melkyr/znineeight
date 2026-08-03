extern "c" fn __bootstrap_print(s: *const u8) void;
pub fn printHello() void {
    __bootstrap_print("hello");
}
