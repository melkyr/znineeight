// enum_u63_max_ok_xmod — a single `enum(u63)` member at the u63 maximum
// (2^63 - 1, value 9223372036854775807) is a legal Zig enum declaration. The
// shared member walk stores member values in an i64 slot whose own maximum is
// the same value, so the successor increment must be guarded here too; the
// `-fsafe` compiler trapped on this shape before the guard.
//
// Contract: `x` is `E.A`, so the `E.A` prong sets `r = 7`; stdout `7\n`, rc 0.
// Must stay rc 0 under both the fast and the `-fsafe` compiler.
const std = @import("std");

const E = enum(u63) { A = 9223372036854775807 };

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
