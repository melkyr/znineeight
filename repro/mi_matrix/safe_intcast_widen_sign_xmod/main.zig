// safe_intcast_widen_sign_xmod — A18 widening sign-change `@intCast` pin,
// RE-PINNED by Task 11U (AMENDMENT 15 option A).
//
// ORIGINAL contract: `@intCast(u16, @as(i8, -1))` is a WIDENING sign change
// (`i8 -> u16`). Before Task 11U, `@as` did not fold, so the cast operand was
// runtime-valued and the A18 lowering predicate (`src_signed && !dst_signed &&
// src_bits < dst_bits`) routed it through `int_cast_checked` — under `-fsafe`
// the program trapped (rc 133) before printing, and under `-ffast` the
// unchecked C cast printed `65535` (rc 0).
//
// SUPERSEDED (Task 11U, AMENDMENT 15 general `@as` fold + option A): `@as`
// now folds at comptime (integer targets only), so `@as(i8, -1)` is a
// comptime-known -1 and `@intCast(u16, -1)` is a comptime OUT-OF-RANGE cast,
// which official Zig rejects. The program is therefore now a clean reject.
// The A18 RUNTIME widening-sign-change trap stays covered by the general
// runtime-operand cast check (see `intcast_range_check`).
//
// Contract (post-11U): dump rc=2, 0 `.c`, `error[3000]` — the canonical
// classifier's GREEN clean-reject bucket. The IN-RANGE widening sign change
// (`i8 100 -> u16`) must NOT reject and is pinned by the companion
// `main_inrange.zig` (prints `100`, rc=0 under both modes).
const std = @import("std");

pub fn main() void {
    var w: u16 = @intCast(u16, @as(i8, -1));
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte(10);
}
