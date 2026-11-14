// safe_int_shl_assign_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` compound
// `<<=` value overflow fixture (A6F).
//
// `x <<= c` with `x: i32 = 1073741824` and `c: i32 = 1` has a valid count
// (1 < 32) but the value doubles out of range. Pre-A6F the raw C `<<=` wraps:
// RED `-2147483648` rc 0.
//
// GREEN (default `-fsafe`): the compound `shl_assign` arm emits the A4 count
// guard AND the A6F value guard before the shift; stdout stays empty, rc 133
// (SIGTRAP). The `-ffast` control keeps the raw wrap (`-2147483648`, rc 0).
const std = @import("std");

pub fn main() void {
    var x: i32 = 1073741824;
    var c: i32 = 1;
    x <<= c;
    std.io.printInt(x);
    std.io.writeByte('\n');
}
