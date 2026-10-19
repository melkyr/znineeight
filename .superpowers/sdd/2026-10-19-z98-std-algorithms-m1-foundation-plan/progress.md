# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m1-foundation-plan.md

BASE at dispatch: 15ad012e448fd4628adad57bc57e21a711124a6e

## M1 Task 1 — testing substrate
- implementer 5d4bdde4 (feat scripts) + 17d34b97 (report)
- gates: verify_stdlib 287/287 fixtures + smoke crosscheck 3/3, STDLIB GATE OK; non-vacuity mutated .out fails then restored; bash -n clean
- review: spec PASS; 0 Critical / 2 Important (forward-risk) / 4 Minor
- Important I1: vector `.out` files remain matched by `.gitignore:37 *.out`; committed via `git add -f` only — future milestones can silently omit them on a clean checkout. Fix requires `.gitignore` negation (file not in plan touch set).
- Important I2: ref built `gcc -std=c89 -O0` (host 64-bit) while Z98 driver is `-m32`; FP refs (noise M2, RK45 M4) risk x87-vs-SSE rounding divergence. Plan/spec text vs AGENTS.md §9.4 flag-set rule (`-m32` mandatory for every gcc).
- Minors deferred: no ref-module-set pin (partial ref-dir deletion shrinks coverage silently); verify_stdlib always runs full crosscheck even on targeted fixture args; orphan .out without .in ignored; expected_dirs.txt not in brief Files list (required by steps).
- STATUS: STOP-present to operator for I1/I2 ruling before Task 2.
- Task 1: fix round 1 (aab2ddef refactor scripts/spec/plans + 78dd69fb report): both Important findings ADDRESSED (vectors .expected; refs gcc -m32) — scoped re-review PASS, no new breakage. Minor deferred: verify_stdlib.sh:27 comment still says `.out` (comment-only, pre-existing).
- Task 1: complete (commits 5d4bdde4..78dd69fb, review clean).
