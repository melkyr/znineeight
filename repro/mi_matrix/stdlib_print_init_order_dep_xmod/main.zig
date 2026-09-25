// stdlib_print_init_order_dep_xmod — final-review Critical fix-wave fixture
// (the shared `dep_buf` in `lowerInitOrderVisit` dropped dependency edges).
//
// DEFECT (v87 compiler): `lowerInitOrderVisit` shared one `dep_buf` across
// recursive calls. A nested visit overwrote it, so after the first dependency
// subtree the outer loop read stale name ids and dropped every remaining edge.
// `var g = a + b;` with `const a = c + d; const b: i32 = 5 + 7;` emitted
// `a; g; b`, so `g` ran as `3` where Zig 0.15.2 prints `15` (silent wrong
// value, rc 0). The `c: i32 = 1 + 0` runtime-init variant was equally wrong.
//
// FIX (final-review Critical fix wave, 2026-09-25): each candidate's
// same-module edge list is precomputed once into a flat adjacency
// (`dep_off`/`dep_all`) and the ordering walk is ITERATIVE with an explicit
// stack, so no visit can clobber another's edges (and the walk no longer
// recurses — review Minor 5).
//
// Contract: stdout (6 lines), rc 0, byte-exact 3x, Zig-0.15.2 twin
// (`std.debug.print`) byte-compared 2026-09-25:
//   g=15
//   a=3
//   b=12
//   g2=15
//   a2=3
//   b2=12
const std = @import("std");

// Variant 1: the exact final-review repro (literal consts).
var g = a + b;
const a = c + d;
const b: i32 = 5 + 7;
const c = 1;
const d = 2;

// Variant 2: the same shape with runtime-initialized consts (module-init
// stores instead of folded literals).
var g2 = a2 + b2;
const a2 = c2 + d2;
const b2: i32 = 5 + 7;
const c2: i32 = 1 + 0;
const d2: i32 = 2 + 0;

pub fn main() void {
    std.io.print("g={}\n", .{g});
    std.io.print("a={}\n", .{a});
    std.io.print("b={}\n", .{b});
    std.io.print("g2={}\n", .{g2});
    std.io.print("a2={}\n", .{a2});
    std.io.print("b2={}\n", .{b2});
}
