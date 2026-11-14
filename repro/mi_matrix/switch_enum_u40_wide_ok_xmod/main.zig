// switch_enum_u40_wide_ok_xmod — an `enum(u40)` member with a discriminant
// above u32 (B = 4294967297) must resolve exactly through the shorthand enum
// literal path. The `enum_value_table` only carries the low 32 bits, so
// lowering the `.B` value and the `.A`/`.B` case labels from that table
// truncated both to 0/1. After the fix the member is resolved by name for any
// enum-typed context (not just signed enums).
//
// Contract: `x` is `.B`, so the `.B` prong sets `r = 8`; stdout `8\n`, rc 0.
const std = @import("std");

const E = enum(u40) { A = 0, B = 4294967297 };

pub fn main() void {
    var x: E = .B;
    var r: i32 = 0;
    switch (x) {
        .A => { r = 0; },
        .B => { r = 8; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
