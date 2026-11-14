// switch_u32_paren_neg_reject_xmod — a parenthesized negative integer case
// item on an unsigned `u32` condition. Sema's unsigned-negative check already
// ran before lowering for this shape (the const evaluator unwraps parentheses),
// so this pins the existing `error[3062]` reject after the paren-unwrap fix.
//
// Contract: rc 2, no `.c`, `error[3062]`
// `type 'u32' cannot represent integer value '-1'`.
const std = @import("std");

pub fn main() void {
    const x: u32 = 1;
    var r: i32 = 0;
    switch (x) {
        (-1) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
