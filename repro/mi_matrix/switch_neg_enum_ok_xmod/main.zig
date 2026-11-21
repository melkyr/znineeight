// switch_neg_enum_ok_xmod — a signed enum backing with a negative discriminant
// used as an exact switch case item. Zig 0.17.1 accepts `enum(i32) { A = -1 }`
// and matches `.A`; Z98 must accept the signed backing, compare the member by
// its signed value, and emit a signed case label.
//
// Contract: `x` is `.A` (value -1), so the `.A` prong sets `r = 7`;
// stdout `7\n`, rc 0.
const std = @import("std");

const E = enum(i32) { A = -1, B = 2 };

pub fn main() void {
    const x: E = .A;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 7; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
