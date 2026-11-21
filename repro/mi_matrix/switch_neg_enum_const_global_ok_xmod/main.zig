// switch_neg_enum_const_global_ok_xmod — a module-level const initialized with
// a shorthand enum literal on a signed `enum(i64)` backing. The const-init
// evaluator must take the exact i64 member value (not the low-32 table value),
// so `X` is -1 and the `.A` prong matches.
//
// Contract: `X` is `.A` (value -1), so the `.A` prong sets `r = 7`;
// stdout `7\n`, rc 0.
const std = @import("std");

const E = enum(i64) { A = -1, B = 2 };
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
