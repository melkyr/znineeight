// switch_bool_paren_ok_xmod — a parenthesized `true` boolean case item on a
// `bool` condition. The `paren_expr` wrapper hid the `bool_literal` from
// `lowerSwitchCaseItemValue`, so the prong was silently dropped.
//
// Contract: `b` is true, so the `(true)` prong sets `r = 7`; stdout `7\n`,
// rc 0.
const std = @import("std");

pub fn main() void {
    const b: bool = true;
    var r: i32 = 0;
    switch (b) {
        (true) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
