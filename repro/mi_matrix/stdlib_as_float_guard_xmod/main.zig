// stdlib_as_float_guard_xmod — Task 11U float-arithmetic guard control.
//
// The general `@as` fold arm shared with `@intCast` yields an INTEGER
// `ComptimeVal`. If it folded an `@as` with a NON-integer target, the value
// would enter the integer binop evaluator and silently miscompile float
// arithmetic: `@as(f64, 3) / 2` would fold as integer `3 / 2` = `1`, not `1.5`.
// The mandatory guard `if (node.child_0 == self.as_id and !is_int_t) return
// null;` keeps non-integer `@as` unfolded, so the runtime float path is used.
//
// This fixture FAILS (runtime `@panic` trap, nonzero rc) on an unguarded arm
// and PASSES on the guarded one. The values below are ordinary decimals (the
// pre-existing lexer-precision quirk on some literals such as `0.75` is
// unrelated and deliberately avoided).
//
// Contract: deterministic byte-exact stdout below, RUNRC=0.
//
//   as-float-div-ok
//   as-float-add-ok
//   as-float-mul-ok
//   done
const std = @import("std");

const A: f64 = @as(f64, 3) / 2;
const B: f64 = @as(f64, 3) + 2;
const C: f64 = @as(f64, 10) * @as(f64, 2);

pub fn main() void {
    if (A != 1.5) { @panic("as-float-div"); }
    std.io.print("as-float-div-ok\n");

    if (B != 5.0) { @panic("as-float-add"); }
    std.io.print("as-float-add-ok\n");

    if (C != 20.0) { @panic("as-float-mul"); }
    std.io.print("as-float-mul-ok\n");

    std.io.print("done\n");
}
