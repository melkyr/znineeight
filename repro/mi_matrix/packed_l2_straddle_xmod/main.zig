// packed_l2_straddle_xmod — FEATURE-GAP RED fixture (packed struct, L2: straddle).
// b spans bytes 0-1 (bits 5..12). GREEN (contract): "2 255 31 31 255\n" —
//   size 2; a=31(11111 bits0-4), b=255(8 bits @5..12) => byte0 0xFF, byte1 0x1F;
//   field reads 31 255.
const std = @import("std");

const Strad = packed struct {
    a: u5,
    b: u8,
};

pub fn main() void {
    var s: Strad = undefined;
    s.a = 31;
    s.b = 255;
    std.io.printInt(@intCast(i32, @sizeOf(Strad)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &s);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, bp[1]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s.a));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, s.b));
    std.io.writeByte('\n');
}
