// safe_intcast_control_xmod — A18 in-range `@intCast` control (must NOT trap).
//
// The `i8 -> i32`, `i32 -> i64` and `u16 -> u32` steps are widening, and the
// last is same-sign, so they use the plain `int_cast`. The `i16 -> u16` step on
// line 18 is a same-width sign change, so it DOES emit `int_cast_checked`
// (`zig_cast_checked_u` under `-fsafe`); its value (300) is in range, so it does
// not trap. Both modes print the same `100 -100 300` (rc 0). Pins that A18 does
// not over-check lossless widening casts and does not false-trap an in-range
// equal-width sign change.
const std = @import("std");

pub fn main() void {
    var a: i8 = 100;
    var b: i32 = @intCast(i32, a);
    std.io.printInt(b);
    std.io.writeByte(32);
    var c: i32 = -100;
    var d: i64 = @intCast(i64, c);
    std.io.printInt(@intCast(i32, d));
    std.io.writeByte(32);
    var e: i16 = 300;
    var f: u32 = @intCast(u32, @intCast(u16, e));
    std.io.printInt(@intCast(i32, f));
    std.io.writeByte(10);
}
