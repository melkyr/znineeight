extern fn __bootstrap_print(s: [*]const u8) void;
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    __bootstrap_print("zig1 bootstrap test\n");
    __bootstrap_print_int(42);
}
