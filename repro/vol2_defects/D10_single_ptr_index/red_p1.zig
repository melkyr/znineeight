// D10 sibling: `p[1]` on a single-item pointer (FH conversion, 2026-09-27).
// Seed v88 accepted it and printed `p[1]=8`; now `error[3066]`, rc 2 / 0 `.c`.
const std = @import("std");

pub fn main() void {
    var arr = [2]i32{ 7, 8 };
    const p: *i32 = &arr[0];
    std.io.print("p[1]={}\n", .{p[1]});
}
