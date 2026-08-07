extern fn __bootstrap_print_int(n: i32) void;
const lib = @import("lib.zig");
pub fn main() void {
    var p = lib.findPath();
    if (p == null) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
