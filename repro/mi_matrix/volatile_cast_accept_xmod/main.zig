// volatile_cast_accept_xmod — GREEN (A10F). `@volatileCast(Dest, value)` is
// the sanctioned explicit removal of the volatile qualifier: same base, drops
// just the volatile bit, emits a real C cast (warning-clean under
// `-Wall -Wextra`).
//
// RED baseline: `*volatile` does not parse (`error[2000]`); `@volatileCast`
// is `error[3000] unsupported builtin function`.
// GREEN contract: compile/link/run clean, prints "9\n".
const std = @import("std");

pub fn main() void {
    var x: u32 = 5;
    const mmio: *volatile u32 = &x;
    const plain: *u32 = @volatileCast(*u32, mmio);
    plain.* = 9;
    std.io.printInt(@intCast(i32, mmio.*));
    std.io.writeByte('\n');
}
