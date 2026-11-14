// safe_int_sub_overflow_u_xmod — RED->GREEN `-fsafe`/`-ffast` unsigned-sub fixture (A6F).
//
// `0 - 1` on u32 is unsigned underflow. Pre-A6F it emits the raw C `-`, which
// wraps: RED `4294967295` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits
// `if (a < b) { pal_trap(); }` before the sub, so stdout stays empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw wrap (`4294967295`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: u32 = 0;
    var one: u32 = 1;
    var r: u32 = a - one;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
