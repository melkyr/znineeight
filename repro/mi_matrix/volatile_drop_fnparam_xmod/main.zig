// volatile_drop_fnparam_xmod — GREEN guard (A10F qualifier safety). Passing a
// `*volatile u32` to a `*u32` function parameter must be rejected: the call
// coercion may not silently discard the argument's volatile qualifier.
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: exactly ONE `error[3000]` (implicit volatile discard),
// dump rc=2, 0 `.c` emitted.
const std = @import("std");

fn take(p: *u32) void {
    p.* = 1;
}

pub fn main() void {
    var x: u32 = 0;
    const mmio: *volatile u32 = &x;
    take(mmio);
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
