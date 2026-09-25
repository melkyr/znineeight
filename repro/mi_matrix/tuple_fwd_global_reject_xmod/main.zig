// tuple_fwd_global_reject_xmod — Task 9 (z98-print-formatting Amendment 1, B5;
// fix round 2 extended by the operator Q6.1 ruling) reject fixture: every
// module-level tuple-literal element that a later module-var pass re-resolves
// away from a value INLINED at the use site or a to-be-initialised global.
//
// Pass 1 of the module-var loop resolves the tuple before the later global has
// a value store (and often before it has a type), so the Task-4 idempotent
// tuple keeps the recorded slot. The benign classes are pinned in
// `stdlib_print_tuple_fwd_ok_xmod` (bare int/char literal consts that fit the
// slot, and globals declared before the tuple); every row below is a broken
// shape that must not emit C:
//
//   1. composite   `fwd_pair = Pair{...}`          -> gcc `incompatible types`
//   2. out-of-i32  `fwd_big = 3000000000`          -> silently printed -1294967296
//   3. arithmetic  `fwd_arith = 5 + 7`             -> silently printed 0
//   4. negate      `fwd_neg = -5`                  -> silently printed 0
//   5. bool        `fwd_bool = true`               -> silently printed 0
//   6. float       `fwd_float = 1.5`               -> silently printed 1
//   7. same-type arithmetic `fwd_ann: i32 = 5 + 7`  -> silently printed 0 (the
//      Important-1 class: the pass-1/2 type matches, so only the value-store
//      order reveals the hazard; fix round 2 walks the element expression)
//   8. same-type negate `fwd_neg_i32: i32 = -5`     -> silently printed 0
//   9. same-type `@as` `fwd_as = @as(i32, 5)`       -> silently printed 0
//  10. cross-module non-literal `colors.C2 = 5+7`   -> silently printed 0 (the
//      root module's `__module_init` runs before the imported module's)
//  11. direct `@import("colors.zig").C`             -> base emitted gcc-invalid
//      C (`'zT_1' undeclared`: the lowerer does not inline this form)
//
// CENSUS: dump rc=2, 0 `.c`, exactly 11 x error[3064]
// (`cannot infer tuple element type: a forward-referenced global is not
// resolved on the first pass`), one per broken tuple; the stable control
// `g_ok = .{ 11, 22 }` emits no diagnostic.
//
// ORACLE NOTE: official Zig 0.15.2 accepts rows 1-10 (container-level
// declarations are order-independent) and prints the nested values; a correct
// Z98 fix needs dependency-ordered `__module_init` emission (out of this
// round), so the rejects are a documented bounded residual (Language_Spec §4).
const std = @import("std");
const colors = @import("colors.zig");

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

// 7. Same-i32-type arithmetic forward reference (fix round 2: the type does not
//    change across passes, so the old delta-only detection never saw it).
var g_ann = .{ fwd_ann, 7 };
const fwd_ann: i32 = 5 + 7;

// 8. Same-i32-type negate forward reference.
var g_neg_i32 = .{ fwd_neg_i32, 7 };
const fwd_neg_i32: i32 = -5;

// 9. Same-i32-type `@as` forward reference.
var g_as = .{ fwd_as, 7 };
const fwd_as = @as(i32, 5);

// 10. Cross-module non-literal const (root `__module_init` runs first).
var g_xmod = .{ colors.C2, 7 };

// 11. Direct `@import(...)` member reference: the lowerer does not inline this
//     form (base emitted an undeclared temp), so it is never benign.
var g_imp = .{ @import("colors.zig").C, 7 };

// Stable control: no forward reference; the element list is identical on every
// pass, so the idempotent fast path returns the recorded type.
var g_ok = .{ 11, 22 };

pub fn main() void {
    std.io.print("ok={}\n", .{g_ok});
}
