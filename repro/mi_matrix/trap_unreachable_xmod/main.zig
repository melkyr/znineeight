// trap_unreachable_xmod — RED->GREEN trap fixture (A2F, unconditional
// divergence). A bare `unreachable` statement MUST terminate via pal_trap()
// (x86 int3), independent of -fsafe/-ffast.
//
// RED (seed v9): `unreachable` lowers to .nop, falls through and "after" runs;
// rc 0, stdout `before\nafter\n`. GREEN: pal_trap() fires after "before";
// stdout `before\n`, rc != 0 (SIGTRAP / rc 133 on x86 linux).
const std = @import("std");

pub fn main() void {
    std.io.writeStr("before\n");
    unreachable;
    std.io.writeStr("after\n");
}
