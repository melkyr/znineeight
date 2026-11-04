// switch_i64_ok_xmod — Task TA regression reproducer (defect A, fixed): a legal
// Z98 `switch` on an `i64` now lowers to an if/else chain instead of a C
// `switch` whose controlling expression was 64-bit, which OpenWatcom 1.9
// rejected (E1078: Invalid type for switch expression). The emitted C must
// stay portable across GCC, OpenWatcom 1.9, and MSVC 6.
//
// Negative case literals now resolve (including parenthesized forms); this
// repro keeps positive values because it is the 64-bit carrier/if-else pin.
// `x` is 2^32, so the `0x100000000` prong sets `r = 2`; stdout `2\n`, rc 0.
const std = @import("std");

pub fn main() void {
    var x: i64 = 0x100000000;
    var r: i32 = 0;
    switch (x) {
        0 => { r = 0; },
        0x100000000 => { r = 2; },
        0x100000001 => { r = 3; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
