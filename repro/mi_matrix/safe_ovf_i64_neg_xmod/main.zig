// A15 fixture (C89-AHEAD): i64 unary negate overflow.
//
// `-INT64_MIN` is signed overflow. Under `-fsafe` (default) the overflow guard
// traps before the negation (empty stdout, rc 133 SIGTRAP). Under `-ffast` it
// wraps to INT64_MIN (rc 0).
//
// Locks A15's `neg_with_overflow` + `overflow_flag{op=NEG}` LIR path.
const std = @import("std");

pub fn main() void {
    var a: i64 = -9223372036854775807 - 1;
    var r: i64 = -a;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
