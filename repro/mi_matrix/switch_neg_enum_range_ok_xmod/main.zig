// switch_neg_enum_range_ok_xmod — negative enum members as range endpoints.
// Zig 0.17.1 does not support enum ranges, but Z98's D2 enum-range extension
// resolves endpoints by member value; signed enum backings must keep that
// resolution and the range must contain the negative values.
//
// Contract: `x` is `.B` (value -1), so `.A... .B` (values -5..-1) sets
// `r = 7`; stdout `7\n`, rc 0.
const std = @import("std");

const E = enum(i32) { A = -5, B = -1, C = 2 };

pub fn main() void {
    const x: E = .B;
    var r: i32 = 0;
    switch (x) {
        E.A...E.B => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
