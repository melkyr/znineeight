// switch_neg_const_ok_xmod — a negative named constant used as a case item on
// a signed `i32` condition. Zig 0.17.1 accepts `NEG` and the prong matches;
// the named constant must resolve to the negative value, not be dropped.
//
// Contract: `x` is -1 and `NEG` is -1, so the `NEG` prong sets `r = 7`;
// stdout `7\n`, rc 0.
const std = @import("std");

const NEG: i32 = -1;

pub fn main() void {
    const x: i32 = -1;
    var r: i32 = 0;
    switch (x) {
        NEG => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
