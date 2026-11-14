// iswindows_deadarm_cond_if_xmod — T3 sema-gate fixture (comptime-if fold:
// the untaken arm is not semantically analyzed). Plan:
// docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md (Task 3).
// Spec: docs/superpowers/specs/2026-10-16-compiler-d1-d2-parity-design.md §3
// (the Zig rule: when an if/else condition is comptime-known, the untaken arm
// is not analyzed and not lowered; the if takes the live arm's value/type).
//
// Three trigger-set shapes (spec §3, narrow fixture-pinned set), each with a
// defect INSIDE the comptime-dead arm so pre-fix sema (which analyzes BOTH
// arms) rejects, while post-fix the dead arm vanishes exactly like Zig:
//   (1) literal `false`          — dead then-arm, undeclared ident (error[20])
//   (2) comptime `const` bool    — dead then-arm, undeclared ident (error[20])
//   (3) value `if`, literal `false` — dead arm value is never typed; the `if`
//       takes the LIVE arm's value/type (`q == 42`)
//   (4) `@isWindows()`           — target-relative dead arm, both arms clean
//       (the D2 pair iswindows_deadarm_errunion_xmod / _prune_xmod pin the
//       emission side of this shape; here the value/type rule is checked)
//
// Runtime pins (linux gate target): `x` must be 2 after (1)+(2), `q` must be
// 42 after (3), and the (4) else-arm is live on a non-Windows target. The
// program prints `cond if ok` only when all pins hold, else `cond if BAD`.
//
// GREEN contract (post-T3, linux gate target — the corpus classifier's
// target): dump rc 0, builds clean, runs deterministic 3x, stdout
// `cond if ok\n`, rc 0, class OK (T3 captures the golden at flip). RED
// pre-fix: dump rc 2, 0 `.c`, census in NOTES.md / expected_error.txt
// (error[20] rows only — the fixture is class FAIL, not GREEN). The
// `-osw` target inverts the (4) polarity only (x/q pins are target-neutral);
// both targets cross-build post-T3.
const std = @import("std");

const use_windows: bool = false;

pub fn main() void {
    var x: i32 = 0;
    if (false) {
        x = dead_arm_undeclared_ident;
    } else {
        x = 1;
    }
    if (use_windows) {
        x = another_dead_undeclared;
    } else {
        x = x + 1;
    }
    var q: i32 = if (false) dead_arm_string_ident else 42;
    if (@isWindows()) {
        x = x + 0;
    } else {
        x = x + 0;
    }
    if (x == 2 and q == 42) {
        std.io.write("cond if ok\n");
    } else {
        std.io.write("cond if BAD\n");
    }
}
