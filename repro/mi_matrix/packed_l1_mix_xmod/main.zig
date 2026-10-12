// packed_l1_mix_xmod — FEATURE-GAP RED fixture (packed struct, L1: u1+u3+u4 in 1 byte).
// GREEN (contract): "1 155 1 5 9\n" — size 1; x=1(bit0), y=5(bits1-3), z=9(bits4-7)
//   => byte 0b10011011 = 155; field reads 1 5 9.
const std = @import("std");

const Mix = packed struct {
    x: u1,
    y: u3,
    z: u4,
};

pub fn main() void {
    var m: Mix = undefined;
    m.x = 1;
    m.y = 5;
    m.z = 9;
    std.io.printInt(@intCast(i32, @sizeOf(Mix)));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &m);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.x));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.y));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, m.z));
    std.io.writeByte('\n');
}
