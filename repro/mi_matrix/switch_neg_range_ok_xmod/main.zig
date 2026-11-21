// switch_neg_range_ok_xmod — negative range case item `-5...-1` on a signed
// `i32` condition. Zig 0.17.1 accepts the range and the prong matches; both
// endpoints must resolve as negative values and the range must not be dropped.
//
// Contract: `x` is -3, so the `-5...-1` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const x: i32 = -3;
    var r: i32 = 0;
    switch (x) {
        -5...-1 => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
