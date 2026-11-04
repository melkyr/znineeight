// switch_neg_paren_range_ok_xmod — a negative inclusive range whose endpoints
// are parenthesized (`(-5)...(-1)`) on a signed `i32` condition. Both range
// endpoints are resolved through `lowerSwitchCaseItemValue`, which dropped the
// parenthesized endpoints and left the range with no lowered case.
//
// Contract: `x` is -3, so the `(-5)...(-1)` prong sets `r = 7`; stdout `7\n`,
// rc 0.
const std = @import("std");

pub fn main() void {
    const x: i32 = -3;
    var r: i32 = 0;
    switch (x) {
        (-5)...(-1) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
