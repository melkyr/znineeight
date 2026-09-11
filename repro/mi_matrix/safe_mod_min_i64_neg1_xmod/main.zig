// safe_mod_min_i64_neg1_xmod — A16F i64 mod `INT64_MIN % -1` guard pin.
//
// `INT64_MIN % -1` is the modulo twin of signed 64-bit division overflow; the C89
// `%` is UB and on x86-32 `idiv` raises SIGFPE. Under `-fsafe` (default) the
// div/mod guard traps before the operation (empty stdout, rc 133 SIGTRAP);
// under `-ffast` no guard is emitted (rc 136 SIGFPE).
//
// Pins the width-64 portable MIN rendering (A16F): `(-9223372036854775807 - 1)`
// instead of the non-C89-clean `-9223372036854775808LL`. Behaviour identical.
const std = @import("std");

pub fn main() void {
    var a: i64 = -9223372036854775807 - 1;
    var b: i64 = -1;
    var r: i64 = a % b;
    if (r == 0) {
        std.io.writeByte(48);
    } else {
        std.io.writeByte(49);
    }
    std.io.writeByte(10);
}
