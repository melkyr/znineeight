# Task 1 report — runtime-gate harness + smoke run (Plan A test hardening)

## What was built

`scripts/stdlib/run_fixtures.sh` — the opt-in runtime gate for the std-lib
fixtures (spec `2026-09-18-std-lib-test-hardening-design.md` §2). It builds,
links, runs, and golden-diffs each discovered `stdlib_*`/`stdlib_test/*`
fixture. No `sf/src` change.

## Harness CLI + behavior

```
run_fixtures.sh <zig1> [<dir>...]
```

- **Discovery** (no `<dir>` args): the corpus universe from
  `scripts/corpus/list_corpus_dirs.sh`, filtered to
  `^repro/mi_matrix/stdlib_*_xmod/$` and `^stdlib_test/*/$` (61 dirs today).
  Explicit `<dir>` args restrict the run (repo-relative or absolute, trailing
  slash tolerated). Entry resolution mirrors the `emit_dir` rule
  (`main.zig` → `<basename>.zig` → first `*.zig`).
- **Per fixture**: `timeout 120 zig1 -ffast -o <tmp> <entry>` → compile every
  emitted `.c` with the binding flag-set (`gcc -m32 -std=c89 -O0 -Wall
  -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I .`,
  run inside the self-contained dump dir) → `sh <tmp>/build_target.sh linux
  <tmp>/prog` → run 3× under `timeout 120` from a scratch CWD.
- **Comparison**: stdout bytes must be identical across the 3 runs and
  `cmp`-equal to `<dir>/expected.txt`; the exit code must equal
  `<dir>/expected.rc` (whitespace-trimmed).
- **Fail closed**: a missing `expected.txt`/`expected.rc` is a `MISSING-GOLDEN`
  FAIL (no silent skip); missing entry, dump rc≠0, 0 `.c`, gcc fail, build
  fail, nondeterminism, stdout mismatch, and rc mismatch are all FAILs.
- **Output**: one `PASS <dir>` / `FAIL <dir> (<reason>)` line per fixture plus
  a `N PASS / M FAIL over K dirs` summary; exits nonzero on any failure.
- `-ffast` and the binding gcc flags are used; the compiler is seed-built.

## Baseline recorded (Step 1)

- HEAD at start: `343c10f5d0a287bc159a02af9b42c605f4572401`.
- Seed: `release/seed/zig1-seed.tgz`, md5 `910a4d673f0fa95f8473c08e143ceb54`.
- Corpus: `scripts/corpus/list_corpus_dirs.sh` → **763 dirs**;
  `EXPECTED_FAIL.md` header **v137**; manifest table **710 OK / 28 GREEN /
  25 FAIL / 0 ICE / 0 CRASH**.
- Fixed point via a fresh seed build:
  `FIXED_POINT_MD5=414cccee639bdb61c7a9f1f2ddddb166
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
  /tmp/planA_hard_t1_seed` → hop1 == hop2 ==
  `414cccee639bdb61c7a9f1f2ddddb166` (two-hop closure OK, recorded fixed point
  OK). zig0 was never invoked.

All authoring-time values matched (only HEAD differed from the plan's
authoring note `8cc04678`, as the brief anticipated: `343c10f5` is the actual
pre-task HEAD and the fixed point is the gate).

## Smoke result (Step 3)

Goldens hand-captured after confirming each fixture's observed stdout matches
its documented GREEN contract (checked against the `GREEN (contract)` comment
in each `main.zig`):

| fixture | expected.txt | expected.rc |
|---|---|---|
| `repro/mi_matrix/stdlib_bits_table_xmod` | `bits ok\n` | `0` |
| `repro/mi_matrix/stdlib_str_split_alias_xmod` | `str split alias ok\n` | `0` |
| `repro/mi_matrix/stdlib_debug_trap_xmod` | `assertion failed\ndebug trap ok\n` | `0` |

```
$ bash scripts/stdlib/run_fixtures.sh /tmp/planA_hard_t1_seed/zig1_5_clean \
    repro/mi_matrix/stdlib_bits_table_xmod \
    repro/mi_matrix/stdlib_str_split_alias_xmod \
    repro/mi_matrix/stdlib_debug_trap_xmod
PASS repro/mi_matrix/stdlib_bits_table_xmod
PASS repro/mi_matrix/stdlib_str_split_alias_xmod
PASS repro/mi_matrix/stdlib_debug_trap_xmod
----------------------------------------
run_fixtures: 3 PASS / 0 FAIL over 3 dirs
HARNESS EXIT=0
```

Discovery-mode sanity (all 61 dirs, before Task 2 goldens): 3 PASS / 58
`MISSING-GOLDEN` FAIL, exit 1 — proves the no-silent-skip rule fires.

## Negative control (Step 4)

Copied `stdlib_bits_table_xmod` to `/tmp/negctl`, overwrote its
`expected.txt` with `BITS WRONG\n`:

```
FAIL /tmp/negctl/stdlib_bits_table_xmod (STDOUT-MISMATCH)
run_fixtures: 0 PASS / 1 FAIL over 1 dirs
HARNESS EXIT=1
```

Gate fails correctly (FAIL + nonzero rc).

## Goldens captured in this task

The 3 `expected.txt` + 3 `expected.rc` files above (Task 2 covers the rest of
the Plan A set). `.gitignore` gained `!expected.txt` after its `*.txt` rule so
the stdout goldens are committable source rather than ignored "app output";
`expected.rc` was never ignored.

## Fixed point measured (Step 5)

`414cccee639bdb61c7a9f1f2ddddb166` — **UNMOVED**. No `sf/src` file changed
(`git diff --stat -- sf/src` empty), so the pre-task fresh seed build remains
authoritative. Seed not rotated.

## Files changed

- `scripts/stdlib/run_fixtures.sh` (new, executable)
- `repro/mi_matrix/stdlib_bits_table_xmod/expected.{txt,rc}` (new)
- `repro/mi_matrix/stdlib_str_split_alias_xmod/expected.{txt,rc}` (new)
- `repro/mi_matrix/stdlib_debug_trap_xmod/expected.{txt,rc}` (new)
- `.gitignore` (`!expected.txt` golden exception)

## Commit

- `0c1dde3bb1a10cbfab4e5936012e8cdad082dbdc` —
  `feat(stdlib): add the runtime-gate harness (Plan A hardening Task 1)`

## Self-review

- Harness CLI matches the plan's interface verbatim; the 3 smoke fixtures match
  their documented contracts; negative control + missing-golden both fail
  closed; fixed point unmoved.
- `bash -n` clean. `set -u` safe (arrays non-empty before indexing).
- Followed the brief exactly: discovery via the `emit_dir` rule, `-ffast -o`,
  binding gcc flag-set, `build_target.sh linux`, 3× determinism,
  stdout+rc goldens, per-dir summary, nonzero exit on failure, seed build only.

## Concerns

- **Discovery scope vs Task 2's golden list.** Discovery yields **61** dirs
  (59 `repro/mi_matrix/stdlib_*_xmod` including `async_*`/`fileio`/`math`/`mem`/
  `arena`, plus 2 `stdlib_test/*`), but the plan's Task 2 file list names only
  the Plan A module fixtures (`bits`/`os`/`time`/`debug`/`buf`/`str`). Under the
  binding "no silent skips" rule, Task 2 must either capture goldens for **all
  61** discovered dirs or the discovery scope must be narrowed. Flagging so the
  controller resolves it before Task 2.
- **T1/T2 golden overlap.** The ledger already notes Task 2 must skip or
  re-verify the 3 fixtures whose goldens Task 1 committed, to avoid a
  double-capture drift.
- **Scratch CWD.** Runs execute from a fresh `mktemp` CWD (the `stdlib_fileio`
  contract expects a scratch CWD so the repo tree is not polluted). Fixtures
  that ever print the raw cwd would be nondeterministic; the current Plan A set
  prints fixed lines (R6-clean).
