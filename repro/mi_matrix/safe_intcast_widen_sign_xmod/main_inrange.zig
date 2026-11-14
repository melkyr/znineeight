// safe_intcast_widen_sign_xmod (in-range control) — companion to main.zig.
//
// Pins the in-range half of the A18 widening sign-change predicate: the cast
// `@intCast(u16, @as(i8, 100))` (`i8 -> u16`) is representable, so the new
// `int_cast_checked` path (`zig_cast_checked_u`) must NOT trap. Both `-fsafe`
// and `-ffast` print `100` (rc 0), proving the widened predicate does not
// false-trap a valid signed -> unsigned widening cast.
const std = @import("std");

pub fn main() void {
    var w: u16 = @intCast(u16, @as(i8, 100));
    std.io.printInt(@intCast(i32, w));
    std.io.writeByte(10);
}
