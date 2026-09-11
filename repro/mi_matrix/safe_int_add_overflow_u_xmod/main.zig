// safe_int_add_overflow_u_xmod — RED->GREEN `-fsafe`/`-ffast` unsigned-add fixture (A6F).
//
// `UINT_MAX + 1` on u32 is unsigned overflow. Pre-A6F it emits the raw C `+`,
// which wraps: RED `0` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits
// `if (a > (0xFFFFFFFFu - b)) { pal_trap(); }` before the add, so stdout stays
// empty and rc 133 (SIGTRAP). The `-ffast` control keeps the raw wrap (`0`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: u32 = 4294967295;
    var one: u32 = 1;
    var r: u32 = a + one;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
