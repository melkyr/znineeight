// enum_wide_macro_i40_ok_xmod — a signed `enum(i40)` with members above 2^31.
// The negative `#define` body must be `(-Z98_I64_C(3000000000))` (raw
// `-3000000000` is unary minus on `unsigned long` in C90), and the positive
// one must carry the `u` suffix: `3000000000u`.
//
// Contract: both members are used; stdout `3\n`, rc 0.
const std = @import("std");

const E = enum(i40) { N = -3000000000, P = 3000000000 };
const NEG: i64 = -3000000000;
const POS: i64 = 3000000000;

pub fn main() void {
    const n: E = E.N;
    const p: E = E.P;
    var r: i32 = 0;
    if (@enumToInt(n) == NEG) {
        r = r + 1;
    }
    if (@enumToInt(p) == POS) {
        r = r + 2;
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
