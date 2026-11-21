// switch_enum_u40_ok_xmod — a legal Z98 `switch` on an `enum(u40)` must lower
// to an if/else chain: the enum's declared backing width is 40 (below 64) but
// its C carrier is `u64`, which OpenWatcom 1.9 rejects in a controlling
// expression (E1078). `B = 3000000000` stays below 2^32 deliberately, so this
// repro isolates the carrier-width defect from the separate enum_value_table
// u32 truncation path.
//
// Contract: `x` is `E.B`, so the `E.B` prong sets `r = 2`; stdout `2\n`, rc 0.
const std = @import("std");

const E = enum(u40) { A = 0, B = 3000000000 };

pub fn main() void {
    var x: E = E.B;
    var r: i32 = 0;
    switch (x) {
        E.A => { r = 0; },
        E.B => { r = 2; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
