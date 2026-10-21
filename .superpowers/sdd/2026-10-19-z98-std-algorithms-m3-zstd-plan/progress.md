# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m3-zstd-plan.md

Base: 453d2ebb (M2 complete)
Seed under test: v106, binary/fixed point 21c957730d268f1e7883176fa5413b65

Task 1: STOP-present (plan/harness conflict) — plan Task 1 Step 5 requires `stdlib_zstd_cross_xmod --crosscheck` with no `ref/` directory ("three-way compare degrades to Z98 == .expected"), but `scripts/stdlib/run_crosscheck.sh` hard-requires `scripts/stdlib/ref/<module>/ref.c` (`MISSING-REF`) and builds/executes it. Task 1 Files do not authorize modifying `run_crosscheck.sh`. No implementation started; awaiting operator ruling.
