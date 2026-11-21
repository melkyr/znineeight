// D10 cross-module reject (FH conversion, 2026-09-27): the single-item
// pointer is indexed inside helper.zig. Seed v88 printed `helper=8`; now the
// module site rejects `error[3066]`, rc 2 / 0 `.c`.
const std = @import("std");
const helper = @import("helper.zig");

pub fn main() void {
    var arr = [2]i32{ 7, 8 };
    const p: *i32 = &arr[0];
    std.io.print("helper={}\n", .{helper.atOne(p)});
}
