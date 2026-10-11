// mathtest.zig — z9play M2 math-tier probe (tests/tier_math.sh).
//
// A tiny z9play-local Z98 program that exercises the pure-Z98 `std_math` f64
// surface added in M2 (`sqrt`/`sin`/`cos`) with EXACTLY the same identities and
// bit-pattern inputs as the std fixture
// `repro/mi_matrix/stdlib_math_f64_xmod/main.zig`, so the two oracles agree
// bit-for-bit. Build it with the binding z9play recipe (`-fsafe`) and compare
// stdout to `tests/mathtest.expected.txt`; the tier also asserts the linked
// binary imports NO libm symbol (no undefined `sqrt`/`sin`/`cos`/`pow`, no
// `libm` in DT_NEEDED) — the whole point of M2 is that z9play runs native math
// on Win9x, where there is no libm.
//
// Pure Z98: free functions, no generics/anytype, strict @intCast, string
// literals via `var s: []const u8`. The sin/cos arguments are supplied as f64
// bit patterns (built with the `@ptrCast` bit-move helper) so each is exactly
// the nearest f64 of {0, pi/6, pi/4, pi/3, pi/2, pi, 3pi/2, 2pi, -pi/4, 100pi}.
// Output is the `{x}` hex-float formatter (exact bit-for-bit), one per line.
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
