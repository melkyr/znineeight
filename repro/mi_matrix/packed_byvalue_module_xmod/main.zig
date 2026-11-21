// packed_byvalue_module_xmod — FEATURE-GAP RED fixture (L6: packed by-value +
//   cross-module layout identity). Two modules must agree on the packed layout.
// GREEN (contract): "1 21 187\n" — size 1; sum(10,11)=21; byte = hi<<4|lo =
//   0b1011_1010? no: lo=10(1010 bits0-3), hi=11(1011 bits4-7) => 0xBA = 186.
//   CONFIRM byte expectation in I8 (LSB-first) and fix header if wrong.
const std = @import("std");
const types = @import("types");

pub fn main() void {
    var p = types.build(@intCast(u4, 10), @intCast(u4, 11));
    std.io.printInt(@intCast(i32, @sizeOf(types.Pair)));
    std.io.writeByte(' ');
    std.io.printInt(types.sum(p));
    std.io.writeByte(' ');
    var bp = @ptrCast([*]const u8, &p);
    std.io.printInt(@intCast(i32, bp[0]));
    std.io.writeByte('\n');
}
