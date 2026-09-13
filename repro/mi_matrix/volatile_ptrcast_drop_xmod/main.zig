// volatile_ptrcast_drop_xmod — GREEN guard (A10F qualifier safety C). An
// explicit `@ptrCast(*u32, ...)` from a `*volatile u32` drops a qualifier the
// source has; `@ptrCast` may not change volatile. `@volatileCast` is the only
// sanctioned remover.
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: exactly ONE `error[3000]` (implicit volatile discard),
// dump rc=2, 0 `.c` emitted.
const std = @import("std");

pub fn main() void {
    var x: u32 = 0;
    const mmio: *volatile u32 = &x;
    const bad = @ptrCast(*u32, mmio);
    bad.* = 1;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
