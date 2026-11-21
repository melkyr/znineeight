// D3 fix regression probe: switch over a KNOWN selector with a RANGE case
// label. A range is not evaluable by the shared comptime evaluator, so the
// resolver must not fall through to the `else` prong: it treats the whole
// switch as undecidable and keeps EVERY prong live (over-load allowed; live
// under-load and wrong-arm selection are not). Pre-fix only `range_else.zig`
// was opened and `range_live.zig` was never loaded.
//
// Not an import-alias binding use: the analyzer declines to type a
// non-decisive selection, so this probe exercises resolver file-open behavior.
const std = @import("std");

const impl = switch (2) {
    1...3 => @import("range_live.zig"),
    else => @import("range_else.zig"),
};

pub fn main() void {
    _ = impl;
    std.io.write("switch range ok\n");
}
