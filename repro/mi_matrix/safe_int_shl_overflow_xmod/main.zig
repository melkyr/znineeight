// safe_int_shl_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` signed `<<` value
// overflow fixture (A6F). A4 guards only the count (>= width); the value that
// shifts out is A6F's.
//
// `1 << 31` on i32 has a valid count (31 < 32) but an unrepresentable signed
// result (2^31 > INT_MAX; C signed `<<` is UB). Pre-A6F it emits the raw C `<<`
// and x86 produces INT_MIN: RED `-2147483648` rc 0.
//
// GREEN (default `-fsafe`): the value guard
// `if (a != 0 && (a > (2147483647 >> c) || a < ((-2147483647 - 1) >> c))) { pal_trap(); }`
// fires before the shift; stdout stays empty, rc 133 (SIGTRAP). The `-ffast`
// control keeps the raw shift (`-2147483648`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: i32 = 1;
    var c: i32 = 31;
    var r: i32 = a << c;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
