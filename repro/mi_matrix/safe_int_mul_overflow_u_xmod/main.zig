// safe_int_mul_overflow_u_xmod — RED->GREEN `-fsafe`/`-ffast` unsigned-mul fixture (A6F).
//
// `65536 * 65536` on u32 is unsigned overflow (2^32 > UINT_MAX). Pre-A6F it
// emits the raw C `*`, which wraps: RED `0` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits
// `if (b != 0 && a > (0xFFFFFFFFu / b)) { pal_trap(); }` before the mul, so
// stdout stays empty and rc 133 (SIGTRAP). The `-ffast` control keeps the raw
// wrap (`0`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: u32 = 65536;
    var b: u32 = 65536;
    var r: u32 = a * b;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
