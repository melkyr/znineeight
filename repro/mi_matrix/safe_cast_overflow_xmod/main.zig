// safe_cast_overflow_xmod — RED->GREEN `-fsafe`/`-ffast` fixture (A4F).
//
// `@intCast(i8, a)` with `a: i16 = 300` narrows 300 into i8; 300 is out of
// range, so the cast MUST trap under `-fsafe`. The fixed-width (i16 -> i8)
// pair has no registered checked helper, so pre-A4F the checked path falls
// through to a silent plain C cast in BOTH modes: RED prints the truncated
// payload (`44`, rc 0).
//
// GREEN (default `-fsafe`): the general width check is emitted and
// `pal_trap()` fires before the stdout buffer flushes; stdout is empty, rc 133
// (SIGTRAP). The `-ffast` control keeps the silent pre-A4F cast (`44`, rc 0).
const std = @import("std");

pub fn main() void {
    var a: i16 = 300;
    var b: i8 = @intCast(i8, a);
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte('\n');
}
