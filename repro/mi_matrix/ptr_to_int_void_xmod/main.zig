extern fn __bootstrap_print_int(n: i32) void;
const lib_mod = @import("lib.zig");

pub fn main() void {
    var buf: [10]u8 = undefined;
    var addr: usize = lib_mod.getPtrAddr(&buf[0]);
    if (addr != @intCast(usize, 0)) {
        __bootstrap_print_int(@intCast(i32, 1));
    } else {
        __bootstrap_print_int(@intCast(i32, 0));
    }
}
