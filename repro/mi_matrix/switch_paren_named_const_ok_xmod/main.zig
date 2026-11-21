// switch_paren_named_const_ok_xmod — a parenthesized negative named constant
// used as a case item on a signed `i32` condition, in both a single-wrapper
// `(NEG)` and a doubly wrapped `((NEG))` form. The `paren_expr` wrapper hid
// the `ident_expr` from `lowerSwitchCaseItemValue`, so both prongs were
// silently dropped before the fix.
//
// Contract: `x` is -1 and `NEG` is -1, so both prongs set their result to 7;
// stdout `7\n7\n`, rc 0.
const std = @import("std");

const NEG: i32 = -1;

pub fn main() void {
    const x: i32 = -1;
    var r: i32 = 0;
    switch (x) {
        ((NEG)) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');

    var r2: i32 = 0;
    switch (x) {
        (NEG) => { r2 = 7; },
        else => { r2 = 9; },
    }
    std.io.printInt(@intCast(i32, r2));
    std.io.writeByte('\n');
}
