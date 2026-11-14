// enum_wide_macro_i64_min_ok_xmod — the i64 minimum keeps its dedicated
// portable body `Z98_I64_MIN`, while the implicit-successor value `min + 1`
// is a wide negative (`(-Z98_I64_C(9223372036854775807))`) and must not stay
// an unsuffixed decimal.
//
// Contract: both members are used; stdout `3\n`, rc 0.
const std = @import("std");

const E = enum(i64) { A = -9223372036854775808, B = -9223372036854775807 };

pub fn main() void {
    const a: E = E.A;
    const b: E = E.B;
    var r: i32 = 0;
    if (@enumToInt(a) == -9223372036854775808) {
        r = r + 1;
    }
    if (@enumToInt(b) == -9223372036854775807) {
        r = r + 2;
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
