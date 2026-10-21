# SDD ledger — plan: docs/superpowers/plans/2026-10-19-z98-std-algorithms-m3-zstd-plan.md

Base: 453d2ebb (M2 complete)
Seed under test: v106, binary/fixed point 21c957730d268f1e7883176fa5413b65

Task 1: STOP-present (plan/harness conflict) — plan Task 1 Step 5 requires `stdlib_zstd_cross_xmod --crosscheck` with no `ref/` directory ("three-way compare degrades to Z98 == .expected"), but `scripts/stdlib/run_crosscheck.sh` hard-requires `scripts/stdlib/ref/<module>/ref.c` (`MISSING-REF`) and builds/executes it. Task 1 Files do not authorize modifying `run_crosscheck.sh`. No implementation started; awaiting operator ruling.
Ruling (operator option 1): amend plan Task 1 to modify `scripts/stdlib/run_crosscheck.sh` so ref-less modules are allowed; when `ref/<module>/ref.c` is absent, skip ref build/compare and require Z98 == committed `.expected` plus Z98 exit 0. Plan commit 3605ea87. Task 1 may proceed.
Task 1: complete (commits c9af1fa8 feat + 523c3289 report) — std_zstd RFC 8878 subset decoder, ref-less crosscheck support, get_zstd_tools.sh, 30 committed vectors, basic/cross fixtures. Gate STDLIB GATE OK 299/299 fixtures, 5/5 crosscheck; std_zstd 30/30 vectors. Review Approved 0 Critical / 0 Important / 3 Minor (basic embeds 4 representative vectors vs Step 2 wording; limited bit-flip coverage; dead code nits).

