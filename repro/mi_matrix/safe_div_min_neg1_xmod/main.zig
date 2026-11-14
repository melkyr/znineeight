// safe_div_min_neg1_xmod — A16 div `INT_MIN / -1` guard pin (C89-AHEAD).
//
// `INT_MIN / -1` is signed division overflow; in C89 the raw `/` is UB and on
// x86-32 `idiv` raises SIGFPE. Under `-fsafe` (default) the div/mod guard traps
// before the division (empty stdout, rc 133 SIGTRAP). Under `-ffast` no guard
// is emitted, so the raw division is UB (rc 136 SIGFPE).
//
// A16 moves the kind-2 `INT_MIN/-1` half of the guard out of the C89 emitter
// into backend-neutral LIR comparisons computed in lowering; the cond is built
// as `(rhs != 0) && ((lhs != MIN) || (rhs != -1))`, so the emitter only prints
// `if (!(cond)) { pal_trap(); }`.
const std = @import("std");

pub fn main() void {
    var a: i32 = -2147483647 - 1;
    var b: i32 = -1;
    var r: i32 = a / b;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
