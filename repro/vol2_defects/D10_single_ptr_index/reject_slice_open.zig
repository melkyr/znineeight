// D10 sibling (FH conversion, 2026-09-27): the open-ended `p[0..]` on a
// single-item pointer ICEd (`error[3043]`, rc 3) on seed v88; it is now a
// clean `error[3067]` (`slice of single-item pointer must be bounded`),
// rc 2 / 0 `.c`.
const std = @import("std");

pub fn main() void {
    var n: i32 = 42;
    const p: *i32 = &n;
    const s = p[0..];
    std.io.print("len={}\n", .{s.len});
}
