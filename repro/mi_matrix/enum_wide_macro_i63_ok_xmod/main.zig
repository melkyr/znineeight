// enum_wide_macro_i63_ok_xmod — a signed `enum(i63)` at both width extremes.
// The declared minimum `-2^62` and the maximum `2^62-1` both need 64-bit C
// literal spelling: `(-Z98_I64_C(4611686018427387904))` and
// `Z98_U64_C(4611686018427387903)`.
//
// Contract: both members are used; stdout `3\n`, rc 0.
const std = @import("std");

const E = enum(i63) { MIN = -4611686018427387904, MAX = 4611686018427387903 };

pub fn main() void {
    const lo: E = E.MIN;
    const hi: E = E.MAX;
    var r: i32 = 0;
    if (@enumToInt(lo) == -4611686018427387904) {
        r = r + 1;
    }
    if (@enumToInt(hi) == 4611686018427387903) {
        r = r + 2;
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
