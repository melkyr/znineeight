// enum_i64_max_ok_xmod — a single `enum(i64)` member at the i64 maximum is a
// legal Zig enum declaration. The shared member walk must not overflow its
// i64 `auto_val = mval + 1` successor increment after the last member: a
// `-fsafe` compiler trapped here (Trace/breakpoint trap) before the guard.
//
// Contract: `x` is `E.A`, so the `E.A` prong sets `r = 7`; stdout `7\n`, rc 0.
// Must stay rc 0 under both the fast and the `-fsafe` compiler.
const std = @import("std");

const E = enum(i64) { A = 9223372036854775807 };

pub fn main() void {
    var x: E = E.A;
    var r: i32 = 0;
    switch (x) {
        E.A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
