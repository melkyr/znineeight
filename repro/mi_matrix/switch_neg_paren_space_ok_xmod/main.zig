// switch_neg_paren_space_ok_xmod — a parenthesized negative integer case item
// with whitespace after the sign (`(- 1)`) on a signed `i32` condition. The
// `paren_expr` wrapper hid the `negate` node from `lowerSwitchCaseItemValue`,
// so the prong was silently dropped.
//
// Contract: `x` is -1, so the `(- 1)` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const x: i32 = -1;
    var r: i32 = 0;
    switch (x) {
        (- 1) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
