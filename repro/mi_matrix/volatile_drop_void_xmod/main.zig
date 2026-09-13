// volatile_drop_void_xmod — GREEN guard (A10F qualifier safety D). A
// `*volatile u32 -> *void` conversion drops volatility (C `void` cannot carry
// the qualifier), so it must be rejected implicitly. `@ptrCast` cannot rescue
// it; `@volatileCast` is the sanctioned remover.
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: exactly ONE `error[3000]` (implicit volatile discard),
// dump rc=2, 0 `.c` emitted.
const std = @import("std");

pub fn main() void {
    var x: u32 = 0;
    const mmio: *volatile u32 = &x;
    const bad: *void = mmio;
    _ = bad;
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
