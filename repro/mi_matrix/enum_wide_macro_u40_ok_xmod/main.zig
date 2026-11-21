// enum_wide_macro_u40_ok_xmod — an unsigned `enum(u40)` with a member above
// 2^32. Its `#define` body must be `Z98_U64_C(4294967297)`; a raw unsuffixed
// decimal has no C89 type on a 32-bit target.
//
// Contract: both members are used; the wide `B` member is initialized through
// its macro (the separate enum-value-table case-label truncation is not in
// scope here), so stdout `3\n`, rc 0.
const std = @import("std");

const E = enum(u40) { A = 0, B = 4294967297 };

pub fn main() void {
    const a: E = E.A;
    const b: E = E.B;
    var r: i32 = 0;
    if (@enumToInt(a) == 0) {
        r = r + 1;
    }
    if (@enumToInt(b) == 4294967297) {
        r = r + 2;
    }
    std.io.printInt(@intCast(i32, r));
    std.io.writeByte('\n');
}
