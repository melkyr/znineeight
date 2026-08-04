const lib = @import("lib.zig");
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    lib.bump();
    lib.bump();
    __bootstrap_print_int(lib.counter);
}
