// stdlib_floatcast_xmod — Task 11B regression: `@floatCast` lowers to a real
// float conversion at runtime.
//
// DEFECT (before the fix): `LirLowerer` never interned `@floatCast` and the
// cast-dispatch chain in `lowerExprImpl` had no prong for it, so control fell
// through to `return result;` with a freshly-created, never-assigned temp.
// The emitted C returned a poison-filled (or, under `-ffast`, zero-initialized)
// temp instead of the conversion — a silent miscompile: dump rc=0, zero
// diagnostics, wrong value at runtime.
//
// FIX (Task 11B): `sf/src/lower.zig` interns `@floatCast` and adds one
// `else if (node.child_0 == self.floatcast_name_id)` prong emitting the
// already-existing `float_cast` LIR op (emitted as `result = (ctype)value;`).
//
// This fixture exercises BOTH directions, a literal argument, a
// precision-losing narrowing, and positive controls (`@as`, `@intToFloat`,
// implicit `f32`->`f64` widening) so the fix cannot silently regress them.
//
// Floats have no `std.io` printer in Z98, so each conversion is pinned by an
// equality probe printing a deterministic `-ok` / `-bad` line.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   widen-2.5-ok
//   narrow-neg1.25-ok
//   literal-3.5-ok
//   computed-7-ok
//   narrow-round-ok
//   as-float-ok
//   inttofloat-ok
//   implicit-widen-ok
//   done
const std = @import("std");

// f32 -> f64 widening via @floatCast.
fn widen(x: f32) f64 { return @floatCast(f64, x); }

// f64 -> f32 narrowing via @floatCast.
fn narrow(x: f64) f32 { return @floatCast(f32, x); }

pub fn main() void {
    // f32 -> f64.
    var a: f32 = 2.5;
    var b: f64 = widen(a);
    if (b == 2.5) { std.io.print("widen-2.5-ok\n"); } else { std.io.print("widen-2.5-bad\n"); }

    // f64 -> f32 (negative value, exactly representable).
    var c: f32 = narrow(-1.25);
    if (c == -1.25) { std.io.print("narrow-neg1.25-ok\n"); } else { std.io.print("narrow-neg1.25-bad\n"); }

    // Literal argument, f64 -> f32.
    var d: f32 = @floatCast(f32, 3.5);
    if (d == 3.5) { std.io.print("literal-3.5-ok\n"); } else { std.io.print("literal-3.5-bad\n"); }

    // Computed widening: int -> f32 -> f64.
    var x: f32 = @intToFloat(f32, 7);
    var y: f64 = @floatCast(f64, x);
    if (y == 7.0) { std.io.print("computed-7-ok\n"); } else { std.io.print("computed-7-bad\n"); }

    // Narrowing rounds to nearest (2^24 + 1 is not representable in f32).
    var big: f64 = 16777217.0;
    var rounded: f32 = @floatCast(f32, big);
    if (rounded == 16777216.0) { std.io.print("narrow-round-ok\n"); } else { std.io.print("narrow-round-bad\n"); }

    // Control: @as float cast (separate lowering path).
    var e: f32 = @as(f32, @as(f64, 5.5));
    if (e == 5.5) { std.io.print("as-float-ok\n"); } else { std.io.print("as-float-bad\n"); }

    // Control: @intToFloat (separate lowering path).
    var g: f64 = @intToFloat(f64, 9);
    if (g == 9.0) { std.io.print("inttofloat-ok\n"); } else { std.io.print("inttofloat-bad\n"); }

    // Control: implicit f32 -> f64 coercion (the pre-existing float_cast path).
    var h: f64 = a;
    if (h == 2.5) { std.io.print("implicit-widen-ok\n"); } else { std.io.print("implicit-widen-bad\n"); }

    std.io.print("done\n");
}
