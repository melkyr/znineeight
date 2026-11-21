// const_rodata_xmod_xmod (entry) — see leaf.zig for the contract.
//
// Contract: stdout one line (see expected.txt), rc 0, byte-exact 3x; every
// observation `@panic`-guarded.
const std = @import("std");
const leaf = @import("leaf.zig");

var r: u32 = 0;

pub fn main() void {
    if (leaf.K != 42) @panic("xmod K");
    if (leaf.TBL[1] != 20) @panic("xmod TBL");
    if (leaf.ARR[2] != 9) @panic("xmod ARR");
    if (!leaf.TAG) @panic("xmod TAG");
    const p: *const i32 = &leaf.ARR[0];
    if (p.* != 7) @panic("xmod &ARR");
    r = leaf.K + leaf.TBL[2] + @intCast(u32, leaf.ARR[0]);
    std.io.print("{d}\n", .{r});
}
