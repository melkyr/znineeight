// safe_int_lit_shl_value_xmod — RED->GREEN `-fsafe`/`-ffast` literal-LHS `<<`
// value-overflow fixture (A6F review-fix).
//
// `2 << 31` has an integer-literal LHS (width 0), so pre-fix the value guard
// was skipped and the raw C shift wrapped to `0`: RED `0` rc 0.
//
// GREEN (default `-fsafe`): the literal LHS is materialized to a typed temp
// (the coercion target `u32` here), so the A6F value guard
// `a > (0xFFFFFFFFu >> c)` fires before the shift; stdout stays empty, rc 133
// (SIGTRAP). The `-ffast` control keeps the raw wrap (`0`, rc 0).
const std = @import("std");

pub fn main() void {
    var r: u32 = 2 << 31;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
