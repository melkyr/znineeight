// stdlib_comptime_floatcast_fold_xmod — Task 11D regression: comptime-known
// `@floatCast` / `@intToFloat` constant-fold to a `float_const`.
//
// DEFECT (before the fix): `comptime_eval.zig` interned exactly seven foldable
// builtins and had no `@floatCast`/`@intToFloat` branch (and no float-valued
// sub-evaluator), so a comptime-known conversion never entered the
// `comptime_values` map; the lowerer's only fold consumer emitted `int_const`
// and could not represent a float. The conversion was lowered to a RUNTIME
// `int_to_float`/`float_cast` in `__module_init` instead of a `float_const`.
//
// FIX (Task 11D): `sf/src/comptime_eval.zig` interns `@floatCast`/`@intToFloat`,
// adds the two fold branches plus a private float sub-evaluator (negative
// literals via `negate`), and tags float folds with a `WIDTH_FLOAT` sentinel so
// they can never enter the integer binop/negate/bit_not/int_cast paths.
// `sf/src/lower.zig`'s `comptime_values` HIT path emits the existing
// `float_const` op with the resolved `f32`/`f64` target for these two callees.
//
// Fold visibility: this fixture's stdout proves RUNTIME correctness (the folded
// values are the values real Zig folds to). The FOLD itself is invisible to
// stdout, so the emitted-C gate inspects `__module_init`:
//
//   awk '/^void zF_.*__module_init\(void\) \{/{f=1} f{print} f&&/^\}/{exit}' \
//       <dump>/*.c
//
// and asserts (a) zero `int_to_float`/`float_cast` for the folded constants and
// (b) the folded values appear as float literals. The runtime-operand control
// `widen()` must still emit a runtime `float_cast` in its own function body.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   inttofloat-f64-3-ok
//   inttofloat-f32-7-ok
//   floatcast-f32-1.5-ok
//   floatcast-f64-widen-ok
//   floatcast-neg-literal-ok
//   floatcast-narrow-round-ok
//   inttofloat-constchain-ok
//   inttofloat-neg-int-ok
//   nested-cast-ok
//   runtime-operand-ok
//   done
const std = @import("std");

// Comptime-known folds (the values this fixture pins).
const A: f64 = @intToFloat(f64, 3);
const B: f32 = @intToFloat(f32, 7);
const C: f32 = @floatCast(f32, 1.5);
const SRC: f32 = 2.5;
const WIDE: f64 = @floatCast(f64, SRC);
const NEG: f32 = @floatCast(f32, -1.25);
const BIG: f64 = 16777217.0;
const ROUNDED: f32 = @floatCast(f32, BIG);
const WIDTH: usize = 80;
const CHAIN: f64 = @intToFloat(f64, WIDTH);
const NEGI: f64 = @intToFloat(f64, -7);
const NEST: f64 = @floatCast(f64, @intToFloat(f32, 5));

// Runtime-operand control: must NOT fold (its body emits a runtime float_cast).
fn widen(x: f32) f64 { return @floatCast(f64, x); }

pub fn main() void {
    if (A == 3.0) { std.io.print("inttofloat-f64-3-ok\n"); } else { std.io.print("inttofloat-f64-3-bad\n"); }
    if (B == 7.0) { std.io.print("inttofloat-f32-7-ok\n"); } else { std.io.print("inttofloat-f32-7-bad\n"); }
    if (C == 1.5) { std.io.print("floatcast-f32-1.5-ok\n"); } else { std.io.print("floatcast-f32-1.5-bad\n"); }
    if (WIDE == 2.5) { std.io.print("floatcast-f64-widen-ok\n"); } else { std.io.print("floatcast-f64-widen-bad\n"); }
    if (NEG == -1.25) { std.io.print("floatcast-neg-literal-ok\n"); } else { std.io.print("floatcast-neg-literal-bad\n"); }
    if (ROUNDED == 16777216.0) { std.io.print("floatcast-narrow-round-ok\n"); } else { std.io.print("floatcast-narrow-round-bad\n"); }
    if (CHAIN == 80.0) { std.io.print("inttofloat-constchain-ok\n"); } else { std.io.print("inttofloat-constchain-bad\n"); }
    if (NEGI == -7.0) { std.io.print("inttofloat-neg-int-ok\n"); } else { std.io.print("inttofloat-neg-int-bad\n"); }
    if (NEST == 5.0) { std.io.print("nested-cast-ok\n"); } else { std.io.print("nested-cast-bad\n"); }

    var rt: f32 = @floatCast(f32, 2.5);
    var w: f64 = widen(rt);
    if (w == 2.5) { std.io.print("runtime-operand-ok\n"); } else { std.io.print("runtime-operand-bad\n"); }

    std.io.print("done\n");
}
