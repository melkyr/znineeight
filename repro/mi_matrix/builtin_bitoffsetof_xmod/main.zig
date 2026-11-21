// builtin_bitoffsetof_xmod — FEATURE-GAP RED fixture (@bitOffsetOf).
// Feature: comptime bit offset builtin @bitOffsetOf(T, "field").
// RED today: @bitOffsetOf unrecognized -> clean FAIL.
// GREEN (contract): "0 32 64\n" (byte offsets 0/4/8 x 8 on a non-packed struct).
// Full value arrives with packed structs (bit-accurate) — see R8.
const std = @import("std");

const Mixed = struct {
    c: u8,
    b: u32,
    d: u16,
};

pub fn main() void {
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "c")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "b")));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, @bitOffsetOf(Mixed, "d")));
    std.io.writeByte('\n');
}
