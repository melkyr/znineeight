// safe_int_lit_shl_count_xmod — RED->GREEN `-fsafe`/`-ffast` literal-LHS `<<`
// count-overflow fixture (A6F review-fix; shape adapted by the Task 4 fix
// round).
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
//
// Task 4 fix round (review Important 1): a DECLARATION slot now range-checks a
// `var`'s arithmetic init exactly, so the original spelling
// `var r: u32 = 1 << 40;` is a Zig-matching `error[3000]` (Zig 0.15.2:
// `type 'u32' cannot represent integer value '1099511627776'`). The same
// literal-LHS shift is illegal there, but it is still lowered at runtime as a
// call argument (the argument fit check covers bare literals only), which is
// exactly the path the A6F guard protects — so the fixture moves the shift into
// `sink(1 << 40);` and keeps the documented `-fsafe` trap / `-ffast` wrap.
const std = @import("std");

fn sink(x: u32) void {
    std.io.printInt(@intCast(i32, x));
}

pub fn main() void {
    sink(1 << 40);
    std.io.writeByte('\n');
}
