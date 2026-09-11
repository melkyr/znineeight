// safe_div_min_i64_neg1_xmod — A16F i64 div `INT64_MIN / -1` guard pin.
//
// `INT64_MIN / -1` is signed 64-bit division overflow; in C89 the raw `/` is UB
// and on x86-32 `idiv` raises SIGFPE. Under `-fsafe` (default) the div/mod guard
// traps before the division (empty stdout, rc 133 SIGTRAP). Under `-ffast` no
// guard is emitted, so the raw division is UB (rc 136 SIGFPE).
//
// The guard's MIN literal is the width-64 signed minimum. A16 originally routed
// it through the shared `int_const` magnitude arm, which rendered the
// non-C89-clean `-9223372036854775808LL` (gcc: "integer constant is so large
// that it is unsigned" / "this decimal constant is unsigned only in ISO C90").
// The A16F fix renders the portable `(<type>)(-9223372036854775807 - 1)` form in
// both the statement and rvalue `int_const` arms, so the guard is warning-clean
// while remaining behaviour-identical (`pal_trap()` on the overflow).
const std = @import("std");

pub fn main() void {
    var a: i64 = -9223372036854775807 - 1;
    var b: i64 = -1;
    var r: i64 = a / b;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
