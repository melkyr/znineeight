// volatile_cast_wrong_base_xmod — GREEN guard (A10F review I2). AMENDMENT 8
// says `@volatileCast` keeps the same base type and clears just the volatile
// bit. A cast whose destination base differs from the source base
// (`*volatile u32 -> *u64`) must be rejected cleanly rather than silently
// lowered to a `ptr_cast`.
//
// RED baseline (before the I2 fix): `@volatileCast` maps straight to
// `ptr_cast`, so the wrong-base cast is accepted (dump rc=0, zero
// diagnostics).
// GREEN contract: exactly ONE `error[3000]` (@volatileCast base mismatch),
// dump rc=2, 0 `.c` emitted.
const std = @import("std");

pub fn main() void {
    var x: u32 = 0;
    const mmio: *volatile u32 = &x;
    const bad = @volatileCast(*u64, mmio);
    bad.* = 1;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
