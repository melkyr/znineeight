// safe_int_lit_shl_value_xmod — RED->GREEN `-fsafe`/`-ffast` literal-LHS `<<`
// value-overflow fixture (A6F review-fix; shape adapted by the Task 4 fix
// round).
//
// `2 << 31` has an integer-literal LHS (width 0), so pre-fix the value guard
// was skipped and the raw C shift wrapped to `0`: RED `0` rc 0.
//
// GREEN (default `-fsafe`): the literal LHS is materialized to a typed temp
// (the coercion target `u32` here), so the A6F value guard
// `a > (0xFFFFFFFFu >> c)` fires before the shift; stdout stays empty, rc 133
// (SIGTRAP). The `-ffast` control keeps the raw wrap (`0`, rc 0).
//
// Task 4 fix round (review Important 1): a DECLARATION slot now range-checks a
// `var`'s arithmetic init exactly, so the original spelling
// `var r: u32 = 2 << 31;` is a Zig-matching `error[3000]` (Zig 0.15.2:
// `type 'u32' cannot represent integer value '4294967296'`). The same
// literal-LHS shift is illegal there, but it is still lowered at runtime as a
// call argument (the argument fit check covers bare literals only), which is
// exactly the path the A6F value guard protects — so the fixture moves the
// shift into `sink(2 << 31);` and keeps the documented `-fsafe` trap /
// `-ffast` wrap.
const std = @import("std");

fn sink(x: u32) void {
    std.io.printInt(@intCast(i32, x));
}

pub fn main() void {
    sink(2 << 31);
    std.io.writeByte('\n');
}
