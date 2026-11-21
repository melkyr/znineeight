# comptime_if_noelse_deadarm_xmod — C5 Variant B pin (else-less dead-arm skip)

## What it tests
The else-less half of the spec §3 Zig rule (C5 Variant B, operator-ruled):
an `if` WITHOUT `else` whose condition is comptime-known also eliminates its
untaken arm before analysis — Zig langref "Compile-Time Expressions": the
compiler "skip[s] analysis of the branch not taken" (no `else`-form
qualification). Errors inside a comptime-dead else-less arm vanish (Zig
behavior). Value-form else-less `if`s are excluded on purpose: they are
always `error[3059]` and `repro/mi_matrix/if_noelse_reject_xmod` pins that
census 10/10 (Variant B keeps the 3059 value-use rejection exactly — the
Variant A `TYPE_NORETURN`-stamp transplant is forbidden because it drops
those rows).

Shapes (see the `main.zig` header): literal `false` / comptime `const` false
/ constant-fold false (`1 > 2`, the C4-wider evaluator-folded set) / clean
`@isWindows()` else-less — each statement-form, dead arms carrying
undeclared-ident/call errors. Live pins: `if (true)` (taken arm analyzed) and
a runtime `if` (untouched); runtime `x == 11` gate prints the golden.

## Measured pre-fix (2026-10-16, pin compiler `/tmp/d1d2_t3/zig1_5_clean`,
md5 `6de5b2e15d6fe81f6e9466b5e6698b22` — post-T3, pre-C5)
Linux `-ffast --dump-c89 --output-dir`: dump rc 2, **0 `.c`**; stderr census
`error[20]` ×3 (dead-arm rows at main.zig shapes 1–3) + `warning[3000]` ×3
(assignment-mismatch warnings feeding the undeclared idents). No
`error[3000]` rows → class **FAIL**.

## Expected classification
- RED pre-fix: **FAIL** (measured above, recorded before the fix).
- After C5 Variant B: the dead arms are not analyzed; dump rc 0; builds
  clean; runs deterministic 3x; stdout `comptime if noelse ok\n` rc 0
  (live-arm value pins hold: `x == 11`) → class **OK** (designed NEW-fixture
  FAIL→OK flip; frozen 1124 subset untouched). Golden captured at flip
  (`run_fixtures.sh --capture`).
