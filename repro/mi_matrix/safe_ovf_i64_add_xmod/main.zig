// A15 fixture (C89-AHEAD): i64 signed add overflow.
//
// `INT64_MAX + 1` is signed overflow. Under `-fsafe` (default) the integer
// overflow guard traps before the add (empty stdout, rc 133 SIGTRAP). Under
// `-ffast` the add wraps to INT64_MIN (rc 0).
//
// This fixture locks the behaviour while A15 moves the kind=6 overflow guard
// out of the C89 emitter into backend-neutral LIR ops (`add_with_overflow` +
// `overflow_flag`) mapped to runtime helpers.
const std = @import("std");

pub fn main() void {
    var a: i64 = 9223372036854775807;
    var b: i64 = 1;
    var r: i64 = a + b;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
