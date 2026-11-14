// volatile_cast_nonvolatile_xmod — GREEN guard (A10F review I2). AMENDMENT 8
// makes `@volatileCast` the sanctioned *remover* of the volatile qualifier, so
// its source must actually be volatile. A non-volatile source
// (`*u32 -> *u32`) must be rejected cleanly rather than silently lowered to a
// `ptr_cast`.
//
// RED baseline (before the I2 fix): `@volatileCast` maps straight to
// `ptr_cast`, so a non-volatile source is accepted (dump rc=0, zero
// diagnostics).
// GREEN contract: exactly ONE `error[3000]` (non-volatile @volatileCast
// source), dump rc=2, 0 `.c` emitted.
const std = @import("std");

pub fn main() void {
    var x: u32 = 0;
    const p: *u32 = &x;
    const bad = @volatileCast(*u32, p);
    bad.* = 1;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
