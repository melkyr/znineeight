// safe_intcast_u64_i64_xmod — A18 equal-width sign-change `@intCast(u64 -> i64)`
// checked-bounds pin (the mirror of safe_intcast_i64_u64_xmod).
//
// `@intCast(i64, m)` with `m: u64 = 18446744073709551615` (2^64-1) is not
// representable in i64, so it MUST trap under `-fsafe`; A18's
// `int_cast_checked` op carries `src_signed=0, src_width=64` and the
// `zig_cast_checked_s` helper rejects a high-bit-set unsigned source.
//
// GREEN: `-fsafe` (default) traps before stdout (empty, rc 133 SIGTRAP); the
// `-ffast` control keeps the unchecked C cast, so the wrapped `i64` is `-1`
// (non-zero), printing `1` (rc 0).
const std = @import("std");

pub fn main() void {
    var m: u64 = 18446744073709551615;
    var s: i64 = @intCast(i64, m);
    if (s == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
