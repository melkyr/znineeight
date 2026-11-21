// switch_i63_ok_xmod — legal Z98 switches on `i63` must lower to if/else
// chains: declared width 63 (below 64) but C carrier `i64`, which OpenWatcom
// 1.9 rejects in a controlling expression (E1078). This pins both the
// 19-digit positive case literal and the signed negative route.
//
// Contract: `x` is 2^62-1, so that prong sets `r = 2`; `y` is -1, so the
// `-1` prong sets `r = 3`; stdout `2\n3\n`, rc 0.
const std = @import("std");

pub fn main() void {
    var x: i63 = 4611686018427387903;
    var r: i32 = 0;
    switch (x) {
        0 => { r = 0; },
        4611686018427387903 => { r = 2; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');

    var y: i63 = -1;
    switch (y) {
        0 => { r = 4; },
        -1 => { r = 3; },
        else => { r = 4; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
