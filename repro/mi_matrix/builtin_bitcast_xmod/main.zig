// builtin_bitcast_xmod — FEATURE-GAP RED fixture (@bitCast).
// Feature: same-size reinterpretation @bitCast(Dest, src).
// RED today: unrecognized -> clean FAIL.
// GREEN (contract): "-1\n" — u32 0xFFFFFFFF reinterpreted as i32.
const std = @import("std");

pub fn main() void {
    var u: u32 = 0xFFFFFFFF;
    var s = @bitCast(i32, u);
    std.io.printInt(s);
    std.io.writeByte('\n');
}
