// safe_compound_shr_assign_xmod — RED->GREEN `-fsafe`/`-ffast` compound fixture (A4F fix).
//
// `x >>= s` with `x: u32 = 256` and `s: u32 = 40`. The count is >= the width,
// which is undefined. Pre-fix the compound `shr_assign` arm emitted the raw C
// `>>` with no `check_trap`, so x86 masked the count mod 32 (40 & 31 == 8) and
// silently produced 1 in BOTH modes: RED `before\n1` rc 0.
//
// GREEN (default `-fsafe`): the compound arm now emits `emitSafeCheckShift`
// (`check_trap{kind=3}`) before the shift, so stdout stays empty and rc 133
// (SIGTRAP). The `-ffast` control keeps the masked `1` (rc 0).
const std = @import("std");

pub fn main() void {
    std.io.writeStr("before\n");
    var x: u32 = 256;
    var s: u32 = 40;
    x >>= s;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
