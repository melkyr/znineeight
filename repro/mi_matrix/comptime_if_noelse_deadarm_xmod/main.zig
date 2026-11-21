// comptime_if_noelse_deadarm_xmod — C5 Variant B pin (else-less `if`:
// comptime-dead arms are not analyzed). Plan:
// docs/superpowers/plans/2026-10-16-compiler-d1-d2-parity-plan.md (Task 3
// fix round). Spec §3 oracle: Zig langref "Compile-Time Expressions" — the
// compiler "skip[s] analysis of the branch not taken" for ANY `if` whose
// condition is compile-time known, including the else-less statement form.
//
// Four else-less statement shapes whose DEAD arm carries an error that must
// VANISH (Zig is silent), plus two live-code pins:
//   (1) literal `false`           — dead arm, undeclared ident (error[20])
//   (2) comptime `const` false    — dead arm, undeclared ident (error[20])
//   (3) constant-fold false (C4 wider set: `1 > 2`) — dead arm, undeclared
//       call (error[20])
//   (4) `@isWindows()` else-less  — target-relative; the dead arm is clean
//       here (the D2 pair pins this shape's emission side)
// Live pins: `if (true)` (taken arm analyzed — its code runs) and a runtime
// `if` (untouched). The program prints `comptime if noelse ok` only when the
// live value pins hold (x == 11), else `comptime if noelse BAD`.
//
// Value-form else-less `if`s are deliberately NOT in this fixture: they are
// always error[3059] (`if_noelse_reject_xmod` pins that census 10/10 — C5
// Variant B keeps the 3059 value-use rejection exactly).
//
// GREEN contract (post-C5, linux gate target): dump rc 0, builds clean, runs
// deterministic 3x, stdout `comptime if noelse ok\n`, rc 0, class OK
// (golden captured at flip). RED pre-fix: dump rc 2, 0 `.c`, `error[20]`×3
// (dead-arm rows — pre-C5 sema analyzes the else-less dead arms), class FAIL.
const std = @import("std");

const use_dead: bool = false;

pub fn main() void {
    var x: i32 = 0;
    if (false) {
        x = dead_arm_undeclared_ident;
    }
    if (use_dead) {
        x = another_dead_undeclared;
    }
    if (1 > 2) {
        x = dead_call_undeclared(1);
    }
    if (@isWindows()) {
        x = x + 0;
    }
    if (true) {
        x = x + 1;
    }
    if (x == 1) {
        x = x + 10;
    }
    if (x == 11) {
        std.io.write("comptime if noelse ok\n");
    } else {
        std.io.write("comptime if noelse BAD\n");
    }
}
