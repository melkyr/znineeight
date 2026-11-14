// volatile_drop_optional_xmod — GREEN guard (A10F qualifier safety). An
// implicit `*volatile u32 -> ?*u32` drop must be rejected (optional wrapping
// may not discard the source pointer's volatile qualifier).
//
// RED baseline: `*volatile` does not parse (`error[2000]`).
// GREEN contract: exactly ONE `error[3000]` (implicit volatile discard),
// dump rc=2, 0 `.c` emitted.
const std = @import("std");

pub fn main() void {
    var x: u32 = 0;
    const mmio: *volatile u32 = &x;
    const bad: ?*u32 = mmio;
    if (bad) |p| {
        p.* = 1;
    }
    std.io.printInt(@intCast(i32, x));
    std.io.writeByte('\n');
}
