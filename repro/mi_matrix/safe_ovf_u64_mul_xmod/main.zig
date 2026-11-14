// A15 fixture (C89-AHEAD): u64 unsigned multiply overflow.
//
// `2^32 * 2^32 == 2^64` overflows the unsigned 64-bit range. Under `-fsafe`
// (default) the overflow guard traps before the multiply (empty stdout,
// rc 133 SIGTRAP). Under `-ffast` it wraps to 0 (rc 0, prints '0').
//
// Locks A15's unsigned `mul_with_overflow` + `overflow_flag{op=MUL}` path.
const std = @import("std");

pub fn main() void {
    var a: u64 = 4294967296;
    var b: u64 = 4294967296;
    var r: u64 = a * b;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
