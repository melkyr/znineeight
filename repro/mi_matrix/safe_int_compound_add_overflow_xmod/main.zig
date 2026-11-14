// safe_int_compound_add_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` compound
// `+=` overflow fixture (A6F). Exercises the first compound path (statement).
//
// `s += 1` with `s: i32 = INT_MAX` overflows. Pre-A6F the raw C `+=` wraps:
// RED `-2147483648` rc 0.
//
// GREEN (default `-fsafe`): the compound `add_assign` arm emits the A6F
// overflow guard before the add; stdout stays empty, rc 133 (SIGTRAP). The
// `-ffast` control keeps the raw wrap (`-2147483648`, rc 0).
const std = @import("std");

pub fn main() void {
    var s: i32 = 2147483647;
    s += 1;
    std.io.printInt(s);
    std.io.writeByte('\n');
}
