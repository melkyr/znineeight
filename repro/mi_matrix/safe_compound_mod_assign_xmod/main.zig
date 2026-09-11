// safe_compound_mod_assign_xmod — RED->GREEN `-fsafe`/`-ffast` compound fixture (A4F fix).
//
// `a %= 0` on signed i32 is modulo by zero. Pre-fix the compound `mod_assign`
// arm emitted the raw C `%` with no `check_trap`, so it raised hardware SIGFPE
// in BOTH modes: RED rc 136.
//
// GREEN (default `-fsafe`): the compound arm now emits `emitSafeCheckDivMod`
// (`check_trap{kind=2}`) before the modulo, so stdout stays empty and rc 133
// (SIGTRAP). The `-ffast` control keeps the raw modulo (SIGFPE rc 136).
const std = @import("std");

pub fn main() void {
    std.io.writeStr("before\n");
    var a: i32 = 10;
    var z: i32 = 0;
    a %= z;
    std.io.printInt(a);
    std.io.writeByte('\n');
}
