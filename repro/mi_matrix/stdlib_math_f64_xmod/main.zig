// stdlib_math_f64_xmod — STDLIB std_math f64 `sqrt` GREEN fixture (M2 Task 1).
//
// std_math.zig is a PURE (no externs, no libm) Z98 module re-exported from
// std.zig as `math`. `sqrt` is implemented with a bit-twiddling seed + an
// exact integer square root on the significand, so it is correctly rounded to
// full f64 precision (NOT a plain Newton loop, which is off by 1 ulp on ~25%
// of inputs, e.g. sqrt(2)).
//
// CONTRACT (deterministic byte-exact stdout, RUNRC=0), one result per line,
// printed with the `{x}` hex-float formatter (exact bit-for-bit):
//   sqrt(0.0)       = 0x0.0p0
//   sqrt(1.0)       = 0x1p0
//   sqrt(4.0)       = 0x1p1
//   sqrt(2.0)       = 0x1.6a09e667f3bcdp0   (irrational, full f64 precision)
//   sqrt(1000000.0) = 0x1.f4p9              (== 1000.0 exact)
//   sqrt(0.25)      = 0x1p-1
//   sqrt(2.25)      = 0x1.8p0
//
// ORACLE: the committed expected.txt is derived independently with `python3`
// (math.sqrt + the Z98 `{x}` printer's format: 14-nibble mantissa, trailing
// zero nibbles stripped, exponent printed with no `+`), NOT by running this
// fixture. The irrational row (sqrt(2)) discriminates a correctly rounded
// result (…f3bcd) from a 1-ulp-off Newton result (…f3bcc).
const std = @import("std");

pub fn main() void {
    std.io.print("{x}\n", .{std.math.sqrt(0.0)});
    std.io.print("{x}\n", .{std.math.sqrt(1.0)});
    std.io.print("{x}\n", .{std.math.sqrt(4.0)});
    std.io.print("{x}\n", .{std.math.sqrt(2.0)});
    std.io.print("{x}\n", .{std.math.sqrt(1000000.0)});
    std.io.print("{x}\n", .{std.math.sqrt(0.25)});
    std.io.print("{x}\n", .{std.math.sqrt(2.25)});
}
