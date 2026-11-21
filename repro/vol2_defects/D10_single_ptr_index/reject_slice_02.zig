// D10 sibling (FH conversion, 2026-09-27): an illegal comptime slice pair on
// a single-item pointer (`p[0..2]`) rejects `error[3067]` rc 2 / 0 `.c`.
const std = @import("std");

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    const s = p[0..2];
    std.io.print("len={}\n", .{s.len});
}
