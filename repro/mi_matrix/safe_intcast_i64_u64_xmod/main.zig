// safe_intcast_i64_u64_xmod — A18 equal-width sign-change `@intCast(i64 -> u64)`
// checked-bounds pin.
//
// `@intCast(u64, a)` with `a: i64 = -1` is an equal-width sign change: -1 is not
// representable in u64, so it MUST trap under `-fsafe`. This is a CONTROL for
// the equal-width `i64 -> u64` direction: pre-A18 the emitter already selected
// the `__bootstrap_u64_from_i64` helper, so PRE also trapped (rc 133). A18 moves
// the check into the `int_cast_checked` LIR op, mapped to the signed-aware
// `zig_cast_checked_u` helper. Only the OPPOSITE direction (`u64 -> i64`) was
// the open gap; it is pinned by `safe_intcast_u64_i64_xmod`.
//
// GREEN: `-fsafe` (default) traps before stdout (empty, rc 133 SIGTRAP); the
// `-ffast` control keeps the unchecked C cast, so the wrapped `u64` is `2^64-1`
// (non-zero), printing `1` (rc 0).
const std = @import("std");

pub fn main() void {
    var a: i64 = -1;
    var u: u64 = @intCast(u64, a);
    if (u == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
