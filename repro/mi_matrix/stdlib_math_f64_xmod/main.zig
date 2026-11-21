// stdlib_math_f64_xmod — STDLIB std_math f64 `sqrt`/`sin`/`cos` GREEN fixture
// (M2 Task 1 + Task 2).
//
// std_math.zig is a PURE (no externs, no libm) Z98 module re-exported from
// std.zig as `math`. `sqrt` is implemented with a bit-twiddling seed + an
// exact integer square root on the significand, so it is correctly rounded to
// full f64 precision (NOT a plain Newton loop, which is off by 1 ulp on ~25%
// of inputs, e.g. sqrt(2)). `sin`/`cos` use a Cody-Waite argument reduction
// (`2/pi` split constant) plus fdlibm `__kernel_sin`/`__kernel_cos` minimax
// polynomials, each evaluated with one operation per statement so the C89
// emitter's stores force f64 rounding on every step (x87 excess precision
// cannot leak into the result).
//
// CONTRACT (deterministic byte-exact stdout, RUNRC=0), one result per line,
// printed with the `{x}` hex-float formatter (exact bit-for-bit). The sin/cos
// inputs are supplied as f64 bit patterns so each argument is exactly the
// nearest f64 of {0, pi/6, pi/4, pi/3, pi/2, pi, 3pi/2, 2pi, -pi/4, 100pi}.
//
// ORACLE: the committed expected.txt is derived independently with `python3`
// (math.sqrt / math.sin / math.cos + the Z98 `{x}` printer's format: 14-nibble
// mantissa, trailing zero nibbles stripped, exponent printed with no `+`), NOT
// by running this fixture. The irrational sqrt row (sqrt(2)) discriminates a
// correctly rounded result (…f3bcd) from a 1-ulp-off Newton result (…f3bcc).
// Accuracy: `sqrt` is correct to 0 ULP; `sin`/`cos` are within 1 ULP of the
// python (glibc) oracle over |x| <= 2^20*(pi/2) ~ 1.65e6 (the Vorbis decoder's
// range and far beyond); these 10 sample points are bit-exact (0 ULP). Outside
// that domain `sin`/`cos` return NaN (no libm, no Payne-Hanek).
const std = @import("std");

fn b2d(b: u64) f64 {
    var p: *f64 = @ptrCast(*f64, &b);
    return p.*;
}

pub fn main() void {
    std.io.print("{x}\n", .{std.math.sqrt(0.0)});
    std.io.print("{x}\n", .{std.math.sqrt(1.0)});
    std.io.print("{x}\n", .{std.math.sqrt(4.0)});
    std.io.print("{x}\n", .{std.math.sqrt(2.0)});
    std.io.print("{x}\n", .{std.math.sqrt(1000000.0)});
    std.io.print("{x}\n", .{std.math.sqrt(0.25)});
    std.io.print("{x}\n", .{std.math.sqrt(2.25)});

    var x: f64 = b2d(0x0000000000000000); // 0
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x3FE0C152382D7365); // pi/6
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x3FE921FB54442D18); // pi/4
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x3FF0C152382D7365); // pi/3
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x3FF921FB54442D18); // pi/2
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x400921FB54442D18); // pi
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x4012D97C7F3321D2); // 3pi/2
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x401921FB54442D18); // 2pi
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0xBFE921FB54442D18); // -pi/4
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
    x = b2d(0x4073A28C59D5433B); // 100pi
    std.io.print("{x}\n", .{std.math.sin(x)});
    std.io.print("{x}\n", .{std.math.cos(x)});
}

