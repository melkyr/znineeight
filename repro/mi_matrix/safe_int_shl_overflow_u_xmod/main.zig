// safe_int_shl_overflow_u_xmod — RED->GREEN `-fsafe`/`-ffast` unsigned `<<`
// value overflow fixture (A6F).
//
// `2 << 31` on u32 has a valid count (31 < 32) but the value 2^32 does not fit
// in u32. Pre-A6F the raw C `<<` masks/wraps to `0`: RED `0` rc 0.
//
// GREEN (default `-fsafe`): the value guard
// `if (a > (0xFFFFFFFFu >> c)) { pal_trap(); }` fires before the shift; stdout
// stays empty, rc 133 (SIGTRAP). The `-ffast` control keeps the raw wrap
// (`0`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: u32 = 2;
    var c: u32 = 31;
    var r: u32 = a << c;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
