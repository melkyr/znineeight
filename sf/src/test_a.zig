extern fn __bootstrap_print(s: [*]const u8) void;
pub fn main() void {
    __bootstrap_print("hello");
}
