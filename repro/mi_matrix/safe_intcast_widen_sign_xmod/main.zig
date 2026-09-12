// safe_intcast_widen_sign_xmod — A18 widening sign-change `@intCast` pin.
//
// `@intCast(u16, @as(i8, -1))` is a WIDENING sign change (`i8 -> u16`): it is
// neither narrowing (`src_bits > dst_bits`) nor equal-width (`src_bits ==
// dst_bits`), so pre-fix the lowering `chk` predicate did not fire and the
// emitter printed a plain `(unsigned short)(signed char)value`, giving 65535
// and rc 0 even under `-fsafe`. Zig's `@intCast` RANGE-CHECKS the value, so -1
// must trap. A18 extends the predicate with the widening case `src_signed &&
// !dst_signed && src_bits < dst_bits`, routing it through `int_cast_checked` /
// `zig_cast_checked_u`.
//
// The in-range widening sign change (`i8 100 -> u16`) must NOT trap and yields
// 100; it is pinned in isolation (a `-fsafe` run of this program traps at the
// out-of-range cast, so the earlier output stays buffered and is lost) by
// `main_inrange.zig`.
//
// GREEN: `-fsafe` (default) traps before stdout (empty, rc 133 SIGTRAP); the
// `-ffast` control keeps the unchecked C cast, so the wrapped `u16` is `65535`,
// printing `65535` (rc 0).
const std = @import("std");

pub fn main() void {
    var w: u16 = @intCast(u16, @as(i8, -1));
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte(10);
}
