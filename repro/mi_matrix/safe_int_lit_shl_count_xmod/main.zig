// safe_int_lit_shl_count_xmod — RED->GREEN `-fsafe`/`-ffast` literal-LHS `<<`
// count-overflow fixture (A6F review-fix).
//
// `1 << 40` has an integer-literal LHS, which lowers to a `TYPE_INT_LIT` temp
// with width 0, so pre-fix neither the A4 count guard nor the A6F value guard
// could compute a bound. The raw C `<<` masks the count to 8 bits on x86 and
// wraps to `256`: RED `256` rc 0.
//
// GREEN (default `-fsafe`): the literal LHS is materialized to a typed temp, so
// the A4 count guard fires (`40 >= 32`) before the shift; stdout stays empty,
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw masked shift
// (`256`, rc 0).
const std = @import("std");

pub fn main() void {
    var r: u32 = 1 << 40;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
