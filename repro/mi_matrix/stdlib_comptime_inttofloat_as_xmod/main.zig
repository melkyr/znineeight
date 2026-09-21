// stdlib_comptime_inttofloat_as_xmod — Task 11U regression: `@as` folds at
// comptime (integer targets only), so an `@intToFloat`/`@floatCast` whose
// operand is an `@as`-wrapped comptime value now constant-folds.
//
// DEFECT (before the fix): `comptime_eval.zig` interned `@intCast` but not
// `@as`, and `comptimeEvalBuiltin`'s fold arm was gated on `int_cast_id` only,
// so `@as` never folded. For a typed `u64` const above `i64` max, the const was
// elided from the emitted C while the runtime `int_to_float` still referenced
// it, so a valid Z98 program failed to build (`'zG_..._X' undeclared`). For
// literal operands the fold was simply skipped (a runtime op was emitted).
//
// FIX (Task 11U, AMENDMENT 15 general fix): intern `@as` and share the
// `@intCast` fold/range-check arm in `comptimeEvalBuiltin`, with a mandatory
// integer-target guard (`@as` with a non-integer target must NOT fold — see
// `stdlib_as_float_guard_xmod`). The redundant `@as` arm in
// `comptimeEvalOperandSigned` mirrors the existing `@intCast` precedent.
//
// Contract: deterministic byte-exact stdout below, RUNRC=0. The folded values
// are the values real Zig folds to; the FOLD itself is additionally visible in
// the emitted `__module_init` (the four constants appear as float literals with
// ZERO `int_to_float`/`float_cast` ops for them). Every comparison is
// `@panic`-guarded so a wrong value traps instead of printing a `-bad` line.
//
//   u64-as-ok
//   i64-neg-ok
//   lit-ok
//   f32-ok
//   done
const std = @import("std");

// Comptime-known `@as` folds. `U` is above i64 max, so the pre-fix elided-const
// bug made this program un-buildable (gcc `'zG_..._U' undeclared`).
const U: u64 = 18446744073709551615;
const UF: f64 = @intToFloat(f64, @as(u64, U));
const NI: f64 = @intToFloat(f64, @as(i64, -1));
const L: f64 = @intToFloat(f64, @as(u64, 5));
const AF32: f32 = @intToFloat(f32, @as(u32, 7));

// Runtime-operand oracles: classify the operand's declared signedness at
// runtime so the fold must match the runtime conversion (unsigned for the u64
// above i64 max, signed for the i64 -1).
fn tof_u(x: u64) f64 { return @intToFloat(f64, x); }
fn tof_i(x: i64) f64 { return @intToFloat(f64, x); }

pub fn main() void {
    var uu: u64 = U;
    if (UF != tof_u(uu)) { @panic("u64-as-fold"); }
    std.io.print("u64-as-ok\n");

    var ni: i64 = -1;
    if (NI != tof_i(ni)) { @panic("i64-neg-fold"); }
    std.io.print("i64-neg-ok\n");

    if (L != 5.0) { @panic("literal-fold"); }
    std.io.print("lit-ok\n");

    if (AF32 != 7.0) { @panic("f32-fold"); }
    std.io.print("f32-ok\n");

    std.io.print("done\n");
}
