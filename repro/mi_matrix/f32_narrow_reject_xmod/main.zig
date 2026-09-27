// f32_narrow_reject_xmod — FX3 (Volume II D6 extras) reject fixture: the
// value-aware f32 narrowing REFUSES every shape Zig 0.15.2 refuses.
//
//   * a runtime f64 or i32 source (parameters, returns, declarations,
//     assignments, struct fields, tagged-union payloads, cross-module);
//   * a typed comptime-known f64 that is NOT exactly representable in f32
//     (`const d: f64 = 0.1`, `@as(f64, 0.1)`, a cross-module const);
//   * a comptime-known integer that is NOT exactly representable in f32
//     (`16777217` = 2^24 + 1: typed const, untyped const and literal forms).
//
// The int-literal shape (`take(16777217)`) is the Zig int-exactness reject the
// operator ruling added: it was a silent round before FX3.
//
// Contract: rc 2, no `.c` emitted, the `error[3000]` census pinned in
// `expected_error.txt`; no ICE, no signal.
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

pub fn main() void {
    var d: f64 = 0.1;
    d = d;
    var i: i32 = 1;
    i = i;
    var x: f32 = 0.0;

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
    _ = x;
}
