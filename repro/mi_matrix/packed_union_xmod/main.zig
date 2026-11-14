// packed_union_xmod — FEATURE-GAP RED fixture (packed union, L4: overlap at bit0).
// GREEN (contract): "2 8\n" — members overlap at bit 0; 12 bits => size 2;
//   write b=3000, read a = low 4 bits of 3000 = 8.
const std = @import("std");

const U = packed union {
    a: u4,
    b: u12,
};

pub fn main() void {
    var u: U = undefined;
    u.b = 3000;
    std.io.printInt(@intCast(i32, @sizeOf(U)));
    std.io.writeByte(' ');
    std.io.printInt(@intCast(i32, u.a));
    std.io.writeByte('\n');
}
