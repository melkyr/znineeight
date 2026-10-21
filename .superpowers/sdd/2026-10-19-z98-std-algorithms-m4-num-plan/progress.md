# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m4-num-plan.md

Base: 33c43c9a (M4 plan amendment)
Seed under test: v107, binary/fixed point 21c957730d268f1e7883176fa5413b65

Ruling (operator option 1): Task 2 Files expanded to authorize `scripts/seed/archive_seed.sh`, `scripts/seed/build_from_seed.sh`, `docs/sf/QUICK_REF.md`, root `README.md`, and `STD_README.MD` truth-ups to 37 std files / `std_num`.
Task 1: STOP-present (dt semantics conflict) — implementation `0231ddc9` + report `cd841917` exist but not reviewed/accepted. Plan Review Focus 4 says `dt` reports the step ACTUALLY taken; Step 3 says accept grow `dt *= 1.5`, which requires `dt` to be the next-step suggestion. Implementer set `dt` to next suggested step and `state.t` to actual accepted step. Awaiting operator ruling: accept next-step semantics + amend plan wording, or require actual-step semantics and revise implementation/fixtures.
Ruling (operator option 1): accept `dt` = next-step suggestion; `state.t` = actual accepted step. Plan Review Focus 4 amended (commit c4b44ae7). Task 1 may be reviewed.
Task 1: complete (commits 0231ddc9 feat + cd841917 report) — std_num DP5(4), FSAL, RMS norm, dt next-step (operator ruling), C89 ref + vectors + basic/cross fixtures. Gate 301/301 fixtures, 6/6 crosscheck, 3× determinism. Review Approved 0 Critical / 0 Important / 5 Minor (64-dim cap docs; accept-growth threshold unstated; RMS fixture non-discriminating; VdP oracle provenance; hex-bit crosscheck format).

