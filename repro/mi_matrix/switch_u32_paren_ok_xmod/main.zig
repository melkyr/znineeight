// switch_u32_paren_ok_xmod — a doubly parenthesized positive integer case item
// on an unsigned `u32` condition (`((1))`). The paren unwrap must not disturb
// the already-working unsigned positive path.
//
// Contract: `x` is 1, so the `((1))` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const x: u32 = 1;
    var r: i32 = 0;
    switch (x) {
        ((1)) => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
