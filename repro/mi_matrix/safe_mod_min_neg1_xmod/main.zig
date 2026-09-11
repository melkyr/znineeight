// safe_mod_min_neg1_xmod — A16 mod `INT_MIN % -1` guard pin (C89-AHEAD).
//
// `INT_MIN % -1` is the modulo twin of signed division overflow; in C89 the raw
// `%` is UB and on x86-32 `idiv` raises SIGFPE. Under `-fsafe` (default) the
// div/mod guard traps before the operation (empty stdout, rc 133 SIGTRAP).
// Under `-ffast` no guard is emitted (rc 136 SIGFPE).
//
// A16 moves the kind-2 `INT_MIN/-1` half of the guard into backend-neutral LIR
// comparisons computed in lowering; the emitter only prints
// `if (!(cond)) { pal_trap(); }`.
const std = @import("std");

pub fn main() void {
    var a: i32 = -2147483647 - 1;
    var b: i32 = -1;
    var r: i32 = a % b;
    std.io.printInt(r);
    std.io.writeByte('\n');
}
