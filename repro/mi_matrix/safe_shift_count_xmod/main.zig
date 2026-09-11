// safe_shift_count_xmod — RED->GREEN `-fsafe`/`-ffast` fixture (A4F).
//
// `x << s` with `x: u32 = 1` and `s: u32 = 40`. The count 40 is >= the width
// (32), which is undefined for a shift. Pre-A4F the raw C `<<` is emitted and
// x86 masks the count mod 32, silently producing 256: RED prints `256` rc 0.
//
// GREEN (default `-fsafe`): the `check_trap{kind=3}` guard emits
// `if (!(s < 32)) { pal_trap(); }` before the shift, so stdout is empty and
// rc 133 (SIGTRAP). The `-ffast` control keeps the masked `256` (rc 0) — no
// new emission on the fast path. (Left-shift VALUE overflow is out of A4F
// scope; only the count >= width guard belongs here.)
const std = @import("std");

pub fn main() void {
    var x: u32 = 1;
    var s: u32 = 40;
    std.io.writeStr("before\n");
    var r: u32 = x << s;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
