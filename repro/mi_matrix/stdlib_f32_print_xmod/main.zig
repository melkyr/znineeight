// stdlib_f32_print_xmod — Task 7F regression: printing an `f32` value shows its
// decimal value (Zig-matching), instead of being truncated to an integer.
//
// DEFECT (before the fix): `getPrintFnName` (`sf/src/c89_emit.zig`) had explicit
// arms only for u32/i32/i64/u64/f64/bool/u8/slice; every other TypeKind fell
// through to the `std_print_i32` default. An `f32` argument (C `float`) was
// therefore passed to a C function taking `int`, and C converts `float` to
// `int` by truncation toward zero — so `1.5` printed as `1`. The program was
// legal Z98/Zig, built cleanly, and produced no diagnostic: a silent miscompile.
//
// FIX (Task 7F, approach (a)): one arm next to the f64 arm routes `f32_type` to
// the existing `std_print_f64`. No runtime change: the in-scope prototype
// `void std_print_f64(double val)` makes C widen `float` -> `double`
// automatically, so the existing decimal printer runs on the widened value.
//
// Residuals NOT fixed here (documented, out of scope): `{x}` on a float prints
// decimal (Zig prints hex-float `0x1.8p0`) and `{c}`/`{s}` on a float print
// decimal where Zig rejects them — both are pre-existing f64-arm limitations
// shared by f32, not regressions.
//
// Task 2 (z98-print-formatting) update: the integral float `f32-calc` now
// prints `7` (Zig's form), not `7.0` — `pal_f64_to_str` omits the `'.'` +
// fraction for an integral value. The non-integral rows are unchanged (the
// 6-digit truncation of `f32-round = 0.1` is a documented Task-2 residual).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   f32-default = 1.5
//   f32-decimal = 1.5
//   f32-neg = -2.25
//   f32-round = 0.1
//   f32-calc = 7
//   f32-wide = 123456.75
//   done
const std = @import("std");

pub fn main() void {
    const a: f32 = @floatCast(f32, 1.5);
    const b: f32 = @floatCast(f32, -2.25);
    const c: f32 = @floatCast(f32, 0.1);
    const d: f32 = @intToFloat(f32, 7);
    const e: f32 = @floatCast(f32, 123456.75);

    std.io.print("f32-default = {}\n", .{a});
    std.io.print("f32-decimal = {d}\n", .{a});
    std.io.print("f32-neg = {}\n", .{b});
    std.io.print("f32-round = {}\n", .{c});
    std.io.print("f32-calc = {}\n", .{d});
    std.io.print("f32-wide = {}\n", .{e});

    std.io.print("done\n");
}
