// switch_enum_u40_wide_qualified_ok_xmod — the qualified form of the wide
// `enum(u40)` discriminant. The condition `const x: E = E.B;` already lowers
// to the exact member value 4294967297, but the `E.A`/`E.B` case labels were
// taken from the u32 `enum_value_table` (0/1) because the enum is unsigned.
// The switch then fell to `else`. After the fix the labels resolve by name
// for any enum-typed context.
//
// Contract: `x` is `E.B`, so the `E.B` prong sets `r = 8`; stdout `8\n`, rc 0.
const std = @import("std");

const E = enum(u40) { A = 0, B = 4294967297 };

pub fn main() void {
    var x: E = E.B;
    var r: i32 = 0;
    switch (x) {
        E.A => { r = 0; },
        E.B => { r = 8; },
        else => { r = 9; },
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
