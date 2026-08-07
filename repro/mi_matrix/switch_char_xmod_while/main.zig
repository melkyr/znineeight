extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    __bootstrap_print_int(lib.run());
}
