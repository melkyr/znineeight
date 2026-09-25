// tuple_fwd_global_reject_xmod — Task 9 (z98-print-formatting Amendment 1, B5;
// fix round 1 narrowed by operator ruling) reject fixture: the module-level
// tuple-literal element list that changes across module-var resolution passes
// for a FORWARD-REFERENCED global, minus the one benign class.
//
// Pass 1 of the module-var loop resolves the tuple before the later global has
// a type, so the element freezes at the `TYPE_VOID -> TYPE_I32` fallback; the
// Task-4 idempotent tuple then keeps that stale slot. The single benign class
// (a module `const` with a bare int/char literal init whose value fits i32) is
// accepted and covered by `stdlib_print_tuple_fwd_ok_xmod`; every other final
// element type is a broken shape that must not emit C:
//
//   1. composite   `fwd_pair = Pair{...}`  -> gcc `incompatible types`
//   2. out-of-i32  `fwd_big = 3000000000`  -> silently printed -1294967296
//   3. arithmetic  `fwd_arith = 5 + 7`     -> silently printed 0 (global load
//                                              before `__module_init` stores it)
//   4. negate      `fwd_neg = -5`          -> silently printed 0 (same)
//   5. bool        `fwd_bool = true`       -> silently printed 0 (same)
//   6. float       `fwd_float = 1.5`       -> silently printed 1 (same)
//
// CENSUS: dump rc=2, 0 `.c`, exactly 6 x error[3064]
// (`cannot infer tuple element type: a forward-referenced global is not
// resolved on the first pass`), one per broken tuple; the stable control
// `g_ok = .{ 11, 22 }` emits no diagnostic.
//
// ORACLE NOTE: official Zig 0.15.2 accepts all six rows (container-level
// declarations are order-independent) and prints the nested values. A correct
// Z98 fix needs dependency-ordered `__module_init` emission (out of this
// round); the rejects are a documented bounded residual (Language_Spec §4).
const std = @import("std");

const Pair = struct { a: i32, b: i32 };

// 1. Composite forward reference (the reported RED: rc=0 then gcc
//    `incompatible types when assigning to type 'int' from type 'Pair'`).
var g_pair = .{ fwd_pair, 7 };
const fwd_pair = Pair{ .a = 1, .b = 2 };

// 2. Out-of-i32 scalar literal forward reference (was accepted rc=0 / gcc clean
//    and silently truncated the value).
var g_big = .{ fwd_big, 7 };
const fwd_big = 3000000000;

// 3. Non-literal scalar forward reference (was accepted and printed 0, because
//    the tuple owner initialises before the referenced global).
var g_arith = .{ fwd_arith, 7 };
const fwd_arith = 5 + 7;

// 4. Negate-initialised scalar forward reference (was accepted, printed 0).
var g_neg = .{ fwd_neg, 7 };
const fwd_neg = -5;

// 5. Bool forward reference (was accepted, printed 0).
var g_bool = .{ fwd_bool, 7 };
const fwd_bool = true;

// 6. Float forward reference (was accepted, printed 1).
var g_float = .{ fwd_float, 7 };
const fwd_float = 1.5;

// Stable control: no forward reference; the element list is identical on every
// pass, so the Task-4 idempotent fast path returns the recorded type.
var g_ok = .{ 11, 22 };

pub fn main() void {
    std.io.print("ok={}\n", .{g_ok});
}
