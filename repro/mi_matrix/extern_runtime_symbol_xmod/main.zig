extern fn __bootstrap_print_int(n: i32) void;
const lib_mod = @import("lib.zig");

pub fn main() void {
    var p = lib_mod.alloc(@intCast(u32, 16));
    __bootstrap_print_int(@intCast(i32, @ptrToInt(p) == @intCast(usize, 0)));
}
