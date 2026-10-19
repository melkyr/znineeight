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

## M1 Task 2 — std_rand
- implementer ea1f6b45 (feat) + 6a361148 (report)
- gates: verify_stdlib 291/291 + crosscheck (smoke, std_rand), STDLIB GATE OK; 4/4 fixtures determinism 3x; rebuilt compiler fixed point b299b4b4 unchanged; lib/ has 33 files
- review: spec PASS; 0 Critical / 2 Important / 3 Minor
- Important I1: mandated bounded-bias canary (1M draws @ bound=7) is statistically ineffective — rejection probability ~9e-10, modulo shortcut bias ~1e-11 signal; source is correct but the test cannot fail for the bug it targets. xoshiroBounded has no bias/range test.
- Important I2: stale enumerations — archive_seed.sh:35 comment + SEED_README heredoc text (:162) still say "32 std .zig" and omit std_rand; QUICK_REF:208 install recipe and README:297 module list omit std_rand. Rotation at Task 4 would ship stale text.
- Minors deferred: no committed regression for xoshiroBounded / bound==0 panics (reviewer probe only); expected_dirs global sort pre-existing-unclean (new entries placed correctly); run_crosscheck.sh touched by Task 2 (disclosed, needed for std_ prefix mapping).
- STATUS: STOP-present to operator for I1/I2 ruling before Task 3.
- Task 2: fix round 1 (08e161af bounded KAT + xoshiro range; 6f73eee5 enumerations; ab91e8d3 report): I1-A + I2-A ADDRESSED — scoped re-review PASS; modulo shortcut diverges line 1 of rejecting-bound vector; no new breakage. Minor deferred: build_from_seed.sh:24 comment still says "32 std .zig" (same class, outside enumerated I2-A list).
- Task 2: complete (commits ea1f6b45..ab91e8d3, review clean).
