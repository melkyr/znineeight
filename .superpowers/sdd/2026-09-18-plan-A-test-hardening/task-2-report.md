# Task 2 report — capture the runtime goldens + wire the gate into closeout (Plan A hardening)

## Scope

Operator ruling m1353 (binding, broadens the plan): capture goldens for **all
61 discovered std fixtures** (the whole existing std surface), not just the Plan
A module fixtures. Discovery via `scripts/corpus/list_corpus_dirs.sh` filtered
to `^repro/mi_matrix/stdlib_*_xmod/$` + `^stdlib_test/*/$` = **61** dirs
(59 `stdlib_*_xmod` + 2 `stdlib_test/*`).

## Goldens captured

- **58 new** `expected.txt` + `expected.rc` pairs (116 files) captured from the
  fresh seed-built compiler `/tmp/planA_hard_t2_seed/zig1_5_clean`.
- **3 Task 1 goldens re-verified, not re-captured**
  (`stdlib_bits_table_xmod`, `stdlib_str_split_alias_xmod`,
  `stdlib_debug_trap_xmod`) — each existing `expected.txt`/`expected.rc`
  byte-matched the observed output, so they were left untouched.
- **Total golden-covered: 61/61 discovered dirs** (no missing golden).

Each observed stdout was manually compared to the fixture's documented GREEN
contract in its `main.zig` header before freezing. **No STOP case** — every
observed output matched its documented contract. In particular the async
fixtures whose headers record a RED at fixed point `18e0de5c`
(`addtask_restart_cancel`, `addtask_reuse`, `removetask`,
`removetask_noop`, `waitfor_*`) now emit exactly their documented GREEN stdout
at `414cccee`, i.e. the 5a-F/4c-F fixes are present and pinned.

**Declared probes** (expected-failure, empty stdout unless noted):

| fixture | expected.rc | expected.txt |
|---|---|---|
| `stdlib_async_await_nonctx_xmod` | 133 (SIGTRAP) | `10\n20\n` + panic on stderr |
| `stdlib_async_waitfor_unregistered_xmod` | 133 (SIGTRAP) | empty |
| `stdlib_debug_defaulttrap_xmod` | 134 (SIGABRT) | empty |

## Closeout wiring

- New `scripts/stdlib/verify_stdlib.sh <zig1> [<dir>...]` — thin closeout
  wrapper over `scripts/stdlib/run_fixtures.sh`: runs the harness over the full
  discovered set, prints `STDLIB GATE OK`, or `STDLIB GATE FAILED (run_fixtures
  rc=N)` + exit 1.
- `scripts/closeout/verify_upgraded.sh` gains **phase C**: it calls
  `verify_stdlib.sh "$ZIG1"` and `phase_fail "C(stdlib-runtime-gate)"` on any
  failure; the verdict table gains `C1 stdlib runtime gate ....... PASS`. So
  `CLOSEOUT OK` now requires the runtime gate to pass.
- `docs/sf/QUICK_REF.md` gains the "Std-lib Runtime Gate (Plan A hardening)"
  section: harness/verify CLI, per-fixture build/link/run recipe, and the
  binding golden convention (incl. probes + `!expected.txt`).

## Full-gate result

- Harness alone: `run_fixtures: 61 PASS / 0 FAIL over 61 dirs`, exit 0.
- Full closeout end-to-end with the seed compiler:
  `bash scripts/closeout/verify_upgraded.sh /tmp/planA_hard_t2_seed/zig1_5_clean`
  → A1-A5 PASS, B1-B7 PASS, `C1 stdlib runtime gate PASS`, **`CLOSEOUT OK`**,
  exit 0.

## Fixed point

Seed build `FIXED_POINT_MD5=414cccee639bdb61c7a9f1f2ddddb166
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
/tmp/planA_hard_t2_seed` → hop1 == hop2 ==
`414cccee639bdb61c7a9f1f2ddddb166` (recorded fixed point OK). `git diff --stat
-- sf/src` empty. Fixed point **UNMOVED**; no seed rotation; zig0 never invoked.

## Files changed (commit `57c1ba4e`, 119 files, +378)

- 116 new golden files: `repro/mi_matrix/stdlib_*/expected.{txt,rc}` (56 dirs) +
  `stdlib_test/{bits_buf_str_usage,os_time_usage}/expected.{txt,rc}` (2 dirs)
  = 58 dirs × 2.
- `scripts/stdlib/verify_stdlib.sh` (new, executable).
- `scripts/closeout/verify_upgraded.sh` (phase C + verdict line + header).
- `docs/sf/QUICK_REF.md` (harness CLI + golden convention).

## Commit

- `57c1ba4e9e72432a21c128c16cd3a5fbce0aa4d3` —
  `test(stdlib): capture Plan A runtime goldens + wire the gate (Plan A hardening Task 2)`

## Self-review

- Followed the brief steps 1-5 verbatim, with scope broadened to all 61 per
  operator ruling m1353.
- Every golden was captured only after an explicit observed-vs-documented
  contract comparison; the 3 T1 goldens were re-verified and skipped.
- Harness-only and full-closeout runs both green; `CLOSEOUT OK` now depends on
  phase C. Probe fixtures carry signal-code `expected.rc`.
- `bash -n` clean on both new/modified scripts. No `sf/src` change. No zig0.

## Concerns

- **Probe shell noise.** The harness prints `Trace/breakpoint trap` / `Aborted`
  job-control notices to the terminal for the 3 probe fixtures (expected
  rc=133/134); they do not affect PASS/FAIL. Cosmetic only.
- **Fixed ports.** `stdlib_async_blocking_tick{,_two}_xmod` bind 4137/4138; the
  gate runs them serially and passed 3× here, but a foreign listener on those
  ports would fail the gate (same class as B6's port-4000 discipline).
- **Task 1 deferred minors still open** (not in Task 2 scope): GCCFAIL/BUILD-RC
  print no compiler diagnostic; discovery hardcodes the `_xmod` suffix;
  `.gitignore` un-ignore is global.
- Goldens are runtime-only and will need re-capture only on an intentional
  behavior change (per spec §6).
