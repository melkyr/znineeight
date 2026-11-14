// safe_int_add_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` signed-add fixture (A6F).
//
// `INT_MAX + 1` on i32 is signed overflow. Pre-A6F it emits the raw C `+`,
// which wraps: RED `-2147483648` rc 0.
//
// GREEN (default `-fsafe`): a `check_trap{kind=6}` guard emits the signed
// short-circuit check `if ((b > 0 && a > (2147483647 - b)) || ...) { pal_trap(); }`
// before the add, so stdout stays empty and rc 133 (SIGTRAP). The `-ffast`
// control keeps the raw wrap (`-2147483648`, rc 0) — no new emission.
const std = @import("std");

pub fn main() void {
    var a: i32 = 2147483647;
    var one: i32 = 1;
    var r: i32 = a + one;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
