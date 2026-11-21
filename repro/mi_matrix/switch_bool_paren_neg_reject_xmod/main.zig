// switch_bool_paren_neg_reject_xmod — a parenthesized negative integer case
// item on a `bool` condition. Before the paren-unwrap fix this shape was
// silently dropped (rc 0); after unwrapping it must take the same clean
// `error[3062]` reject as the bare form, never reach lowering, and never emit
// the invalid `case 18446744073709551615:` label.
//
// Contract: rc 2, no `.c`, `error[3062]`
// `type 'bool' cannot represent integer value '-1'`.
const std = @import("std");

pub fn main() void {
    const b: bool = true;
    var r: i32 = 0;
    switch (b) {
        (-1) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
