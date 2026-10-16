# iswindows_deadarm_prune_xmod — D2 emission-pruning fixture with pre-fix golden (T0)

## What it tests
Same dead-arm error-union reference shape as `iswindows_deadarm_errunion_xmod`
(error-union `open` in each arm of `if (@isWindows())`), but the two dependency
modules are host-neutral (no `@cInclude`), so the current compiler BUILDS AND
RUNS the program. The red defect is purely the EMISSION of the comptime-dead
module; the runtime behavior the fix must preserve is frozen in
`expected.txt`/`expected.rc`.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`)
- `zig1 -ffast -o <out> main.zig`: dump rc=0, 8 `.c` — **BOTH**
  `windep_F4B0B95D.c` (wrong-platform; must be pruned after T3) and
  `linuxdep_C8F2DBE9.c` (live) present.
- `sh <out>/build_target.sh linux <out>/prog`: rc 0.
- run: stdout `iswindows prune ok\n` (19 bytes), rc 0 — 3x byte-identical via
  `scripts/stdlib/run_fixtures.sh --capture` (CAPTURED; goldens written).

## Expected classification
- Pre-fix: **OK** (class-stable by design — the corpus classifier compares
  CLASS files, not emitted C; this is exactly why gate 2 carries that note).
- After T3: **OK** + goldens still match (behavior preserved) + emission
  contract: `windep_*.c` ABSENT from a linux-build output dir /
  `linuxdep_*.c` ABSENT from an `-osw` output dir. No class mover either way.

## Goldens
`expected.txt` = `iswindows prune ok\n` (exact stdout bytes);
`expected.rc` = `0`. Measured from the CURRENT (pre-fix) compiler via
`scripts/stdlib/run_fixtures.sh --capture` (harness: `-ffast -o` + gcc
binding flag-set + `build_target.sh linux` + 3x run, byte-identical asserted).
This fixture therefore matches the mi_matrix runtime-anchor SET definition
(non-stdlib ∧ non-empty `expected.txt` ∧ `expected.rc==0`) but is a T0
addition — the frozen 25-anchor set is enumerated by name in
`.superpowers/sdd/2026-10-16-compiler-d1-d2-parity-plan/task-0-report.md`
(§1.8-style list); later tasks run that explicit list, not a re-enumeration.
