// safe_int_neg_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` signed unary-neg
// fixture (A6F).
//
// `-INT_MIN` on i32 is signed overflow (the negated value is unrepresentable).
// Pre-A6F it emits the raw C unary `-`, which wraps back to INT_MIN: RED
// `-2147483648` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits
// `if (a == (-2147483647 - 1)) { pal_trap(); }` before the negation; stdout
// stays empty, rc 133 (SIGTRAP). The `-ffast` control keeps the raw wrap
// (`-2147483648`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: i32 = -2147483647 - 1;
    var r: i32 = -a;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
