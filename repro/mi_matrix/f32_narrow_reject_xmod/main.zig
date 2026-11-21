// f32_narrow_reject_xmod — FX3 (Volume II D6 extras) reject fixture: the
// value-aware f32 narrowing REFUSES every shape Zig 0.15.2 refuses.
//
//   * a runtime f64 or i32 source (parameters, returns, declarations,
//     assignments, struct fields, tagged-union payloads, cross-module);
//   * a typed comptime-known f64 that is NOT exactly representable in f32
//     (`const d: f64 = 0.1`, `@as(f64, 0.1)`, a cross-module const);
//   * a comptime-known integer that is NOT exactly representable in f32
//     (`16777217` = 2^24 + 1: typed const, untyped const and literal forms);
//   * FX9: an `if`/`switch` VALUE expression at an f32 site with a runtime
//     non-float arm (`if (c > 0) n else 2.5` with `n: i32`; the `switch`
//     form; `i64`/`u32`/`bool` arms; both root and nested sites: return,
//     declaration, assignment, struct field, tagged-union payload, call
//     argument). Pre-FX9 these were accepted and miscompiled (`r=0`,
//     gcc-invalid C) or ICEd; Zig rejects `expected type 'f32', found
//     'i32'`. A comptime-true condition makes the bad arm the taken one and
//     still rejects (`if (true) n else 2.5`).
//   * FX10: a `switch` VALUE expression at an f32 site whose prong is not
//     value-aware narrowable — a runtime non-float prong (`retSwArm`), the
//     int-inexact literal (`retSwInexact`) and typed-const (`retSwBadI`)
//     prongs, and a runtime f64 prong (`retSwF64`), at return/assignment/
//     field/argument sites. FX10's retyping only changes the ACCEPT side; the
//     prong classification (and therefore this reject census) is unchanged
//     from FX9 except that the reported `source:` is the offending prong's
//     type.
//
// The int-literal shape (`take(16777217)`) is the Zig int-exactness reject the
// operator ruling added: it was a silent round before FX3.
//
// Contract: rc 2, no `.c` emitted, the `error[3000]` census pinned in the
// header (18 FX3 rows + 15 FX9 runtime-arm rows + 6 FX10 switch rows = 39);
// no ICE, no signal, no warning.
const std = @import("std");
const helper = @import("helper.zig");

const BadF: f64 = 0.1;
const BadI: i32 = 16777217;
const BadN = 16777217;

const S = struct { x: f32 };
const U = union(enum) { a: f32, empty };

fn take(x: f32) f32 { return x; }
fn retRuntime(d: f64) f32 { return d; }
fn retInexact() f32 { return BadF; }
fn retInexactI() f32 { return BadI; }
fn retIfArm(c: i32, n: i32) f32 { return if (c > 0) n else 2.5; }
fn retSwArm(c: i32, n: i32) f32 { return switch (c) { 1 => n, else => 2.5 }; }
fn retSwInexact(c: i32) f32 { return switch (c) { 1 => 16777217, else => 2.5 }; }
fn retSwBadI(c: i32) f32 { return switch (c) { 1 => BadI, else => 2.5 }; }
fn retSwF64(c: i32, d: f64) f32 { return switch (c) { 1 => d, else => 2.5 }; }
fn retIfArmI64(c: i32, n: i64) f32 { return if (c > 0) n else 2.5; }
fn retIfArmU(c: i32, n: u32) f32 { return if (c > 0) n else 2.5; }
fn retIfArmB(c: i32, b: bool) f32 { return if (c > 0) b else 2.5; }
fn retIfTrueBad(n: i32) f32 { return if (true) n else 2.5; }
fn retIfMixRt(c: i32, x: f32, d: f64) f32 { return if (c > 0) x else d; }

pub fn main() void {
    var d: f64 = 0.1;
    d = d;
    var i: i32 = 1;
    i = i;
    var x: f32 = 0.0;
    var n: i32 = 1;
    n = n;
    var c: i32 = 1;
    c = c;
    var bf: bool = true;
    bf = bf;

    _ = take(d);
    _ = take(i);
    _ = take(16777217);
    _ = take(BadF);
    _ = take(@as(f64, 0.1));
    _ = take(BadI);
    _ = take(BadN);

    x = d;
    var y: f32 = d;
    _ = y;
    var z: f32 = 16777217;
    _ = z;
    var s: S = S{ .x = d };
    _ = s;
    var ua: U = U{ .a = d };
    _ = ua;
    var ub: U = U{ .a = 16777217 };
    _ = ub;

    _ = helper.take(d);
    var hx: f32 = helper.BadF;
    _ = hx;

    _ = retRuntime(0.1);
    _ = retInexact();
    _ = retInexactI();

    // FX9 runtime non-float arms through an `if`/`switch` value expression.
    _ = retIfArm(c, n);
    _ = retSwArm(c, n);
    _ = retIfArmI64(c, 2);
    _ = retIfArmU(c, 2);
    _ = retIfArmB(c, bf);
    _ = retIfTrueBad(n);
    _ = retIfMixRt(c, x, d);
    var xa: f32 = if (c > 0) n else 2.5;
    _ = xa;
    x = if (c > 0) n else 2.5;
    const xb: f32 = switch (c) { 1 => n, else => 2.5 };
    _ = xb;
    // FX10: switch reject rows (runtime non-float prong, int-inexact literal
    // and typed-const prong, runtime f64 prong) across the sites.
    x = switch (c) { 1 => n, else => 2.5 };
    var sb: S = S{ .x = switch (c) { 1 => n, else => 2.5 } };
    _ = sb;
    _ = take(switch (c) { 1 => 16777217, else => 2.5 });
    _ = retSwInexact(c);
    _ = retSwBadI(c);
    _ = retSwF64(c, d);
    var sa: S = S{ .x = if (c > 0) n else 2.5 };
    _ = sa;
    var uax: U = U{ .a = if (c > 0) n else 2.5 };
    _ = uax;
    _ = take(if (c > 0) n else 2.5);
    _ = take(if (c > 0) bf else 2.5);
    _ = take(switch (c) { 1 => n, else => 2.5 });
    _ = x;
}

