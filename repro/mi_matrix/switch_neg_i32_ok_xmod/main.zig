// switch_neg_i32_ok_xmod — negative integer case item on a signed `i32`
// condition. Zig 0.17.1 accepts `-1` and the prong matches; the signed
// condition must compare the negative value by value, not drop the prong.
//
// Contract: `x` is -1, so the `-1` prong sets `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

pub fn main() void {
    const x: i32 = -1;
    var r: i32 = 0;
    switch (x) {
        -1 => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
