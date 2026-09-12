// safe_intcast_control_xmod — A18 lossless `@intCast` control (must NOT trap).
//
// All casts here are widening or same-width/same-sign, so no `int_cast_checked`
// op is emitted (the plain `int_cast` suffices) and both modes print the same
// `100 -100 300` (rc 0). Pins that A18 does not over-check lossless casts.
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
