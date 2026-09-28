// stdlib_f32_narrow_ok_xmod — FX3 (Volume II D6 extras) positive runtime
// fixture: value-aware narrowing to f32.
//
// Every accepted source materialises at an f32 expectation site and round-
// trips exactly like Zig 0.15.2: an untyped float literal or literal-only
// float arithmetic (even inexact: 0.1 rounds to f32(0.1)), a typed
// comptime-known f64 (const / @as(f64, ...)) that is exactly representable,
// and a comptime-known integer that is exactly representable. Sites:
// parameters, returns, struct fields, tagged-union payloads, local
// declarations, assignments and cross-module calls. FX3 fix round 1 adds
// `if`/`switch` VALUE expressions (runtime conditions): the narrowing probe
// classifies every arm value-aware instead of rejecting the joined f64, so
// `return if (c > 0) 1.5 else 2.5;`/`switch` return and an `if`-initialized
// declaration stay accepted exactly like Zig 0.15.2. FX9 adds the mixed-arm
// controls: a runtime `f32` arm beside a float literal / an exact typed
// `i32`/`f64` arm (`if (c > 0) x else 2.5`), a nested mixed `if`, and
// comptime-known conditions whose untaken arm is never analyzed
// (`if (false) n else 2.5`); all are red→green against the PRE-FX9 compiler.
// FX9 fix round 1 adds the `undefined`-arm controls: `undefined` coerces to
// every type, so an `undefined` arm is neutral and does not trigger the
// runtime-arm reject (`if (c > 0) undefined else 2.5` stays accepted like the
// seed and Zig 0.15.2); the `und=` row pins only taken-literal values (a
// taken `undefined` arm is unspecified and is never pinned).
//
// Contract: stdout below, rc 0, byte-exact 3x; every printed value is
// byte-identical to the Zig-0.15.2 `std.debug.print` twin (the values chosen
// are all representable in f32, so no printer-precision residual applies).
const std = @import("std");
const helper = @import("helper.zig");

const D: f64 = 2.5;
const C: i32 = 6;
const NL = 7;

const S = struct { x: f32 };
const U = union(enum) { a: f32, empty };

fn take(x: f32) f32 { return x; }
fn retLit() f32 { return 1.5; }
fn retD() f32 { return D; }
fn retC() f32 { return C; }
fn retIf(c: i32) f32 { return if (c > 0) 1.5 else 2.5; }
fn retSwitch(c: i32) f32 { return switch (c) { 1 => 1.5, else => 2.5 }; }
fn retIfX(c: i32, x: f32) f32 { return if (c > 0) x else 2.5; }
fn retIfI(c: i32, x: f32) f32 { return if (c > 0) x else C; }
fn retIfF(c: i32, x: f32) f32 { return if (c > 0) x else D; }
fn retIfN(c: i32, e: i32, x: f32) f32 { return if (c > 0) (if (e > 0) x else 2.5) else 3.5; }
fn retIfFalse(n: i32) f32 { return if (false) n else 2.5; }
fn retIfTrue(n: i32) f32 { return if (true) 2.5 else n; }
fn retUnd(c: i32) f32 { return if (c > 0) undefined else 2.5; }
fn retUndR(c: i32) f32 { return if (c > 0) 6.5 else undefined; }

pub fn main() void {
    var v1: f32 = 0.1;
    v1 = 1.5;
    var v2: f32 = D;
    var v3: f32 = C;
    var v4: f32 = NL;
    var c: i32 = 1;
    c = c + 1;
    const vi: f32 = if (c > 0) 1.5 else 2.5;

    var s1: S = S{ .x = 2.0 };
    var s2: S = S{ .x = D };

    var cu: i32 = -1;
    cu = cu;
    const xu: f32 = if (cu > 0) undefined else 3.5;
    var yu: f32 = 0.0;
    yu = if (cu > 0) undefined else 4.5;
    var su: S = S{ .x = if (cu > 0) undefined else 5.5 };

    var ua: U = U{ .a = 2.0 };
    var ub: U = U{ .a = @as(f64, 3.0) };
    var uc: U = U{ .a = C };

    std.io.print("param={} {} {} {} {} {}\n", .{ take(1.5), take(2), take(1.0 + 0.5), take(D), take(@as(f64, 4.0)), take(C) });
    std.io.print("param2={} {} {}\n", .{ take(0.1), take(NL), helper.take(3.5) });
    std.io.print("ret={} {} {}\n", .{ retLit(), retD(), retC() });
    std.io.print("ifs={} {} {} {}\n", .{ retIf(1), retIf(-1), retSwitch(1), vi });
    std.io.print("mix={} {} {} {} {} {} {} {} {}\n", .{ retIfX(1, 3.5), retIfX(-1, 3.5), retIfI(-1, 3.5), retIfF(-1, 3.5), retIfN(1, 1, 4.5), retIfN(1, -1, 4.5), retIfN(-1, 1, 4.5), retIfFalse(7), retIfTrue(7) });
    std.io.print("und={} {} {} {} {} {}\n", .{ retUnd(-1), retUndR(1), xu, yu, su.x, take(if (cu > 0) undefined else 7.5) });
    std.io.print("decl={} {} {} {}\n", .{ v1, v2, v3, v4 });
    std.io.print("field={} {}\n", .{ s1.x, s2.x });
    std.io.print("union={} {} {}\n", .{ ua.a, ub.a, uc.a });
    var xs = helper.S{ .x = 4.5 };
    std.io.print("xmod={}\n", .{xs.x});
    std.io.print("done\n", .{});
}
