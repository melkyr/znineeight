// D10 sibling (FH conversion, 2026-09-27): `p[1..0]` on a single-item pointer
// rejects `error[3067]` rc 2 / 0 `.c` (seed v88 produced len 4294967295).
const std = @import("std");

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    const s = p[1..0];
    std.io.print("len={}\n", .{s.len});
}
