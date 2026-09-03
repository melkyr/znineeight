// builtin_bitsizeof_xmod — FEATURE-GAP RED fixture (@bitSizeOf).
// Feature: comptime bit-size builtin @bitSizeOf(T).
// RED today: @bitSizeOf unrecognized -> clean FAIL.
// GREEN (contract): "1 8 32\n" (bool=1, u8=8, u32=32).
const std = @import("std");

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitSizeOf(bool)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitSizeOf(u8)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitSizeOf(u32)));
    std.io.writeByte('\n');
}
