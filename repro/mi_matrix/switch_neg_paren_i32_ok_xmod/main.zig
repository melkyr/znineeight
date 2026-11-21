// switch_neg_paren_i32_ok_xmod — a parenthesized negative integer case item
// on a signed `i32` condition. `lowerSwitchCaseItemValue` had no `paren_expr`
// arm, so `(-1)` fell through to `null` and the prong was silently dropped
// (the emitted switch had only `default:`). Zig 0.17.1 accepts the
// parenthesized form.
//
// Contract: `x` is -1, so the `(-1)` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const x: i32 = -1;
    var r: i32 = 0;
    switch (x) {
        (-1) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
