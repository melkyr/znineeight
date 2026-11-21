# Task 9f.1 report — certify the 31 value-switch emission diffs

**Status: PASS — certification complete, no source change.**
**Repo:** `/workspace/znineeight`, branch `zig1_improvements`.
**Base HEAD:** `29b9f923` (docs only; compiler source `ace04574`).
**Commit:** this report + evidence (no `sf/src`, no plan/spec/defects edit).
**Spec:** `docs/superpowers/specs/2026-10-29-phase35-31-diff-certification.md`.
**Evidence:** `repro/mi_matrix/known_excluded/d15_31_diff/`.

## Builds / clean state

| Compiler | Commit | md5 | sha256 |
|---|---|---|---|
| pre-Task-9 base | `d124055d` | `3bf7602b9b396522e17ffc978eaba38d` | `c2b2e4e4078460dafda45e7cd132caaeb26f0b810b3c17461360b4372b12538e` |
| final Task 9 | `ace04574` | `cac6716d4417c16c2f4140e76f435872` | `a314303b51680c24ee8462ab6be10992edb22a0bdef28e52e28171c82ac65dc2` |
| pre-D15 Z98 | `32473a03` | `1bdedb7419952ed10be80f1cca7b5476` | `bb4ce380c84d2cc0495ba072ed31e07091aa08ad17b0485642ba70549fedfd02` |

Existing `/tmp/t9a_base_build` and `/tmp/t9f2_final_build` were reused only
after the hashes matched the Task 9a/9f records. `git diff --stat ace04574 HEAD
-- sf/src` = 0 files; `git status --porcelain -- sf/src` = 0 lines. Untracked
`lin_bin/`, `zig1/` and pre-existing docs edits are unrelated; no compiler source
was touched.

## The exact 31

Materialized from `/tmp/t9f2_corpus_mismatch.txt` (31 EMIT lines) and split using
the Task 9f final-vs-interim comparison (`/tmp/t9f2_interim_full_mismatch.txt`):

- **12 recovered** (`RC interim=2 final=0`): `eu_err_switch`,
  `eunum_err_switch`, `euopt_err_switch`, `euopt_val_switch`,
  `euoptptr_err_switch`, `opt_null_switch`, `opteu_err_switch`,
  `opteu_null_switch`, `optnum_null_switch`, `optopt_null_switch`,
  `optopt_val_switch`, `optptr_null_switch`.
- **19 value-switch** (`EMIT interim=0 final=0`): exactly Task 9k's enumeration.
- `12 + 19 = 31`; stored in `d15_31_diff/entries.tsv`.

## Method

For every entry, from repo root with canonical `--lib-dir zig1/lib`:

```sh
BASE=... ; FINAL=... ; PRE=...
"$Z" -ffast --dump-c89 --lib-dir "$ROOT/zig1/lib" --output-dir out "$entry"
( cd out && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long \
    -Wno-pointer-sign -Wno-implicit-function-declaration -I . -c ./*.c )
( cd out && gcc -m32 -O0 ./*.o -o bin )
timeout 20 bin </dev/null >stdout 2>stderr; echo $?
```

Full loop: `repro/mi_matrix/known_excluded/d15_31_diff/run_cert.sh`.

## Results

- **31/31**: base dump rc 0, final dump rc 0, `gcc -m32 -std=c89` compile rc 0.
- **29/31**: canonical link rc 0; run rc and stdout byte-identical base vs final.
- **2/31 compile-only** (`euoptptr_val_switch`, `optptr_val_switch`): both
  declare `extern fn getp() *i32` with no definition. Compile succeeds for base
  and final; canonical link fails only on the same undefined `getp` in both. A
  supplemental `int *getp(void)` stub links and runs both: rc 0, empty stdout,
  equal. This is a fixture property present identically before/after, not a
  compiler mismatch.
- **12/12 recovered**: final dump/compile/link/run rc 0 and stdout equal to
  pre-D15 Z98 (`1bdedb74…`). Zig 0.17.1 freshly accepts all 12 adapted parity
  twins (rc 0).
- **19/19 value-switch**: `all_c_diffs.txt` shows only expected-type prong
  coercions (prong casts, optional/error-union wrap moved to the prong, outer
  peer wrap removed). `grep` over non-header diff lines for `switch`, `case `,
  `goto z_bb` = **0**.

One-line test summary: `31/31 dump+gcc-c89 compile; 29/31 direct run + 2/2 stub
run all rc/stdout equal; 12/12 recovered equal pre-D15; 0 switch/case/goto diff
lines.`

## Boundary checks

- No non-switch entry: every hunk is a value-result switch prong coercion.
- No statement-switch emission shift: zero switch/case/goto lines changed; the
  Task 9l statement-switch set has no emission-diff member. `z9play` is a mixed
  entry and is in the statement-switch repro35 set, but its only diff is the
  value-result `return switch` in `floor_*.c`; no statement-switch C changed.
- D16 remains open; no D16 work was done or claimed.

## Concerns

1. Two entries are compile-only under the canonical link because of the
   fixture-intentional undefined `getp`; runtime was still checked with a
   supplemental stub and matched (documented in
   `d15_31_diff/gcc_compile_only_getp.txt`).
2. `z9play` is mixed value+statement switch; only its value-switch emission
   moved (noted above and in the spec §8).
3. Task 9f's "31 vs 19" wording remains: this report certifies all 31 as the
   19 Task 9k shifts + 12 D15-recovered cases; nothing was waved.

**Report path:** `.superpowers/sdd/2026-10-29-phase35-defects-plan/task-9f1-report.md`
