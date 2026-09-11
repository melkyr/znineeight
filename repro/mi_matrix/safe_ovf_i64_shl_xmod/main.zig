// A15 fixture (C89-AHEAD): i64 left-shift value overflow.
//
// `1 << 63` on i64 overflows the signed 64-bit range. Under `-fsafe` (default)
// the overflow guard traps before the shift (empty stdout, rc 133 SIGTRAP),
// after the A4 shift-count guard succeeds. Under `-ffast` it wraps.
//
// Locks A15's `shl_with_overflow` + `overflow_flag{op=SHL}` LIR path.
const std = @import("std");

pub fn main() void {
    var a: i64 = 1;
    var r: i64 = a << 63;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
