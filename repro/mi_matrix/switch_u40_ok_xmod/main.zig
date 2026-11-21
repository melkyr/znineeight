// switch_u40_ok_xmod — a legal Z98 `switch` on a `u40` must lower to an
// if/else chain: its declared width is 40 (below 64) but its C carrier is
// `u64`, which OpenWatcom 1.9 rejects in a controlling expression (E1078).
// The case label above 2^32 also needs a carrier-legal C89 literal.
//
// Contract: `x` is 4294967297, so that prong sets `r = 2`; stdout `2\n`, rc 0.
const std = @import("std");

pub fn main() void {
    var x: u40 = 4294967297;
    var r: i32 = 0;
    switch (x) {
        0 => { r = 0; },
        4294967297 => { r = 2; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
