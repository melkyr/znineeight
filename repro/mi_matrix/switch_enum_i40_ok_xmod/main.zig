// switch_enum_i40_ok_xmod — legal Z98 switches on an `enum(i40)` must lower to
// if/else chains: the enum's declared backing width is 40 (below 64) but its
// C carrier is `i64`, which OpenWatcom 1.9 rejects in a controlling expression
// (E1078). This pins the signed enum carrier plus wide positive and negative
// discriminants.
//
// Contract: `x` is `E.B`, so the `E.B` prong sets `r = 2`; `y` is `E.N`, so
// the `E.N` prong sets `r = 3`; stdout `2\n3\n`, rc 0.
const std = @import("std");

const E = enum(i40) { N = -1, B = 3000000000 };

pub fn main() void {
    var x: E = E.B;
    var r: i32 = 0;
    switch (x) {
        E.N => { r = 1; },
        E.B => { r = 2; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');

    var y: E = E.N;
    switch (y) {
        E.B => { r = 4; },
        E.N => { r = 3; },
        else => { r = 4; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
