const std = @import("std");
extern fn __bootstrap_print_int(i32) void;

fn makeSlice() ![]u8 {
    const slice: []u8 = &[_]u8{ 1, 2, 3 };
    return slice;
}

pub fn main() void {
    const s = makeSlice() catch return;
    __bootstrap_print_int(@intCast(i32, s.len)); // should print 3
    __bootstrap_print_int(@intCast(i32, s.ptr[0])); // should print 1
}
