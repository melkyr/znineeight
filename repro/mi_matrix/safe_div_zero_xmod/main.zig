// safe_div_zero_xmod — RED->GREEN `-fsafe`/`-ffast` fixture (A4F).
//
// `10 / 0` on signed i32 is division by zero. Pre-A4F it executes the raw C
// `/`, which raises hardware SIGFPE: RED rc 136, stdout empty/partial.
//
// GREEN (default `-fsafe`): the `check_trap{kind=2}` guard emits
// `if (!(z != 0)) { pal_trap(); }` before the division, so stdout is empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the raw division (SIGFPE rc
// 136) — no new emission on the fast path.
const std = @import("std");

fn dv(a: i32, z: i32) i32 {
    return a / z;
}

pub fn main() void {
    std.io.writeStr("before\n");
    var r: i32 = dv(10, 0);
    std.io.printInt(r);
    std.io.writeByte('\n');
}
