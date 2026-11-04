// switch_u64_ok_xmod — Task TA reproducer (defect A): a legal Z98 `switch` on
// a 64-bit integer is emitted as a C `switch` whose controlling expression is
// 64-bit, which OpenWatcom 1.9 rejects (E1078: Invalid type for switch
// expression). The emitted C is accepted by GCC; the defect is C portability.
//
// Contract: `x` is 2^32, so the `0x100000000` prong sets `r = 2`; stdout `2\n`,
// rc 0.
const std = @import("std");

pub fn main() void {
    var x: u64 = 0x100000000;
    var r: i32 = 0;
    switch (x) {
        0 => { r = 0; },
        0x100000000 => { r = 2; },
        0xFFFFFFFFFFFFFFFF => { r = 3; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
