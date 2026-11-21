// safe_int_mul_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` signed-mul fixture (A6F).
//
// `100000 * 100000` on i32 is signed overflow (1e10 > INT_MAX). Pre-A6F it
// emits the raw C `*`, which wraps: RED `1410065408` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits the division
// pre-check (no widening; short-circuited so no division by zero / MIN/-1)
// before the mul, so stdout stays empty and rc 133 (SIGTRAP). The `-ffast`
// control keeps the raw wrap (`1410065408`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: i32 = 100000;
    var b: i32 = 100000;
    var r: i32 = a * b;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
