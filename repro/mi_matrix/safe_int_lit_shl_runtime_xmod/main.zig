// safe_int_lit_shl_runtime_xmod — RED->GREEN `-fsafe`/`-ffast` literal-LHS `<<`
// with a runtime shift count (A6F review-fix).
//
// `2 << c` with a runtime `c = 31`: the literal LHS has width 0 pre-fix, so the
// value guard was skipped. The raw C shift wraps to `0`: RED `0` rc 0.
//
// GREEN (default `-fsafe`): the literal LHS is materialized to a typed temp
// (the coercion target `u32`), so the A6F value guard `a > (0xFFFFFFFFu >> c)`
// fires before the runtime-count shift; stdout stays empty, rc 133 (SIGTRAP).
// The `-ffast` control keeps the raw wrap (`0`, rc 0).
const std = @import("std");

pub fn main() void {
    var c: u32 = 31;
    var r: u32 = 2 << c;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
