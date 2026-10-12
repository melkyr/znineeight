# anon_errset_comparison — RED/GREEN  [Defensive repros — Plan 1, 2026-08-04]

## What it tests
Error-set member comparison on a bare-`!` (anonymous) error set: `err == error.Bad`
inside a catch block. RED uses `fn f() !i32` (anonymous inferred set); GREEN is the
explicit-error-set control (`const E = error{ Bad };`).

## Measured result
Classified per QUICK_REF corpus classifier — see EXPECTED_FAIL.md row for the measured
classification and run output (RED vs GREEN).

## Deferred item
REPRO ONLY — investigation of any runtime gap (raw name_id may miscompare on anonymous
sets) is deferred to Plan 3 Task P3-3. This repro's existence here is the Plan 1
deliverable.
