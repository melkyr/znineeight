// switch_neg_enum_min_ok_xmod — minimum-value discriminants on signed enum
// backings. The i32 minimum must emit as the portable C89 constant expression
// `(-2147483647 - 1)` (not `-2147483648`), and the i64 minimum must use
// `Z98_I64_MIN` in both the member macro and the 64-bit switch chain.
//
// Contract: both switches match `.A` (values i32-min and i64-min), so both
// print `7`; stdout `7\n7\n`, rc 0.
const std = @import("std");

const E32 = enum(i32) { A = -2147483648, B = 2 };
const E64 = enum(i64) { A = -9223372036854775808, B = 2 };

fn pick32(x: E32) i32 {
    return switch (x) {
        .A => 7,
        else => 9,
    };
}

fn pick64(x: E64) i32 {
    return switch (x) {
        .A => 7,
        else => 9,
    };
}

pub fn main() void {
    std.io.printInt(@intCast(i32, pick32(.A)));
    std.io.writeByte('\n');
    std.io.printInt(@intCast(i32, pick64(.A)));
    std.io.writeByte('\n');
}
