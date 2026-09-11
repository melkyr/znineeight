// safe_int_neg_unsigned_xmod — RED->GREEN `-fsafe`/`-ffast` unsigned unary-neg
// fixture (A6F).
//
// Zig rejects `-unsigned` at compile time; Z98 currently accepts and wraps it
// (`-5` as u8 -> 251). A6F's approved fallback is a runtime trap that
// approximates the static rejection: under `-fsafe` any nonzero unsigned
// negation traps.
//
// RED (`-ffast` and PRE): raw C unary `-` wraps to `251`, rc 0.
// GREEN (default `-fsafe`): `if (a != 0) { pal_trap(); }` before the negation;
// stdout stays empty, rc 133 (SIGTRAP).
const std = @import("std");

pub fn main() void {
    var a: u8 = 5;
    var r: u8 = -a;
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
