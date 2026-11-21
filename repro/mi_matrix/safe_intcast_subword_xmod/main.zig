// safe_intcast_subword_xmod — A18 sub-word checked `@intCast` bounds pin.
//
// `@intCast(i8, a)` with `a: u16 = 300` narrows 300 into i8; 300 is out of range,
// so it MUST trap under `-fsafe`. This exercises the signed sub-word target
// (`zig_cast_checked_s` with `src_width=16, dst_width=8`) and its exact bound
// comparison. The second cast `@intCast(u16, c)` with `c: i16 = -1` is a
// same-width sign change (`i16 -> u16`) and must trap too.
//
// GREEN: `-fsafe` (default) traps before stdout (empty, rc 133 SIGTRAP); the
// `-ffast` control keeps the unchecked C casts and prints the truncated payload
// `44 65535` (rc 0).
const std = @import("std");

pub fn main() void {
    var a: u16 = 300;
    var b: i8 = @intCast(i8, a);
    std.io.printInt(@intCast(i32, b));
    std.io.writeByte(32);
    var c: i16 = -1;
    var d: u16 = @intCast(u16, c);
    std.io.printInt(@intCast(i32, d));
    std.io.writeByte(10);
}
