// switch_neg_enum_const_wide_ok_xmod — a module-level const initialized with
// `.A` where the signed `enum(i64)` discriminant needs more than 32 bits
// (-4294967297). A low-32 truncation would not match the case label.
//
// Contract: `X` is `.A` (value -4294967297), so the `.A` prong sets `r = 7`;
// stdout `7\n`, rc 0.
const std = @import("std");

const E = enum(i64) { A = -4294967297, B = 2 };
const X: E = .A;

pub fn main() void {
    var r: i32 = 0;
    switch (X) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
