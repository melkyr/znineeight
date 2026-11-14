# Task 5 report — M1 closeout (z9torr core plan)

**Status:** DONE
**Branch:** `zig1_improvements` (no push)
**Base:** `83881722` (Task 4) — this closeout is **docs only** + the example gate.
**Compiler:** UNTOUCHED. `/tmp/z9_m0_seed/zig1_5_clean` (seed v94) used only as the
example build/dump compiler. No compiler-only gates run (fixed point, 8 dump-MD5
pins, corpus classify).

## Step 1 — Docs

### `examples/z98/z9torr/NOTES.md`
- `Working commit` `01dd8843` → **`83881722`**.
- `MD5 (--dump-c89)` `TBD` → **`b0e8496d741aa130b7252bd7ebefe985`** (seed
  `zig1_5_clean`, verified 3×; the `sf/build/out_release/zig1` recipe was stale —
  no such binary — replaced by the seed dump command).
- `Expected Output` obsolete `z9torr` → the t1 metadata summary; noted the
  no-arg/`--help` usage behavior. Removed the trailing "MD5 not baselined" line.
- Added a short M1-complete note (Tasks 1–4 artifacts; `piece_hashes` stated as
  flat `[]const u8`, 20 B/piece per the Task-2 amendment — **not** `[][20]u8`).

### `examples/z98/z9torr/README.md`
- Task-0 "prints `z9torr`"/"skeleton only" text → M1 core description; Files list
  updated; Build/Run uses the t1 fixture with the real metadata expected output;
  Status → M1 complete (`15 passed, 0 failed / TIER1 PASS`).

### `examples/z98/z9torr/demo/README.md:39`
- `--dump-c89` section's `command` bullet was the build command; now the actual
  dump command (`… --dump-c89 examples/z98/z9torr/main.zig | md5sum`).

### Root `README.md` + `docs/sf/QUICK_REF.md` example counts
- Root `README.md`: `21/21` → `25/25` (4 spots: :39, :118, :259, :304) and
  `21 examples/z98 programs` → `25 …`.
- `docs/sf/QUICK_REF.md`: the example-baseline counts `24/24` → `25/25` (11
  occurrences: 9 "example matrix 24/24" + 2 "matrix 24/24").
- Rationale: z9torr is the 25th `examples/z98/` dir (verified:
  `ls -d examples/z98/*/ | wc -l` = 25); the spec/plan (and the task's Step 1)
  direct the example-baseline count to `25`.

Changed files: `README.md`, `docs/sf/QUICK_REF.md`,
`examples/z98/z9torr/NOTES.md`, `examples/z98/z9torr/README.md`,
`examples/z98/z9torr/demo/README.md`.

## Step 2 — Gates (example-only)

### tier1 (binding)
```
$ bash examples/z98/z9torr/tests/tier1.sh
...
== tier1 summary: 15 passed, 0 failed ==
TIER1 PASS
```
rc=0. Covers: binding seed build + `build_target.sh` link; per fixture (t1/t2/t5)
exit 0, printed `info_hash` == committed expected == `ref_check`, 3×
byte-identical stdout; malformed inputs (truncated / bad piece count / mutated
info byte) → exit 2 + typed message.

### corpus discovery
```
$ bash scripts/corpus/list_corpus_dirs.sh | grep z9torr
examples/z98/z9torr/
```

### `--dump-c89` MD5 (reproduced)
```
$ timeout 120 /tmp/z9_m0_seed/zig1_5_clean --dump-c89 examples/z98/z9torr/main.zig | md5sum
b0e8496d741aa130b7252bd7ebefe985  -
```
(14 `warning[3037]` lines on stderr; stdout stream only for the hash.)

### std-lib gate (unchanged from M0 — the example does not touch std)
```
$ bash scripts/stdlib/verify_stdlib.sh /tmp/z9_m0_seed/zig1_5_clean
run_fixtures: 280 PASS / 0 FAIL over 280 dirs
STDLIB GATE OK
```

Compiler-only gates intentionally NOT run (fixed point / 8 dump-MD5 pins /
corpus classify) — compiler untouched, per the 2026-10-08 operator amendment.

## Step 4 — Report + commit
Docs + this report committed (report + ledger under `.superpowers/` force-added;
that dir's `.gitignore` is `*`). Check-in name:
`docs(z9torr): M1 closeout — docs golden, example-baseline 25`.

## Step 5 — Next plan
**M2** is next: `docs/superpowers/plans/2026-10-08-z9torr-m2-single-peer-download-plan.md`
(protocol modules + mock peer/tracker + tier2; single-peer download with
cross-restart resume).

## Concerns
1. **QUICK_REF historical baseline counts rewritten (24→25).** The plan/spec
   direct updating the QUICK_REF example-baseline counts to 25; I updated all 11
   occurrences, including dated compiler-plan baseline entries. This follows the
   explicit instruction but edits entries that recorded the pre-z9torr state
   (the established convention adds a new baseline entry rather than rewriting
   past ones). Flagged for reviewer adjudication; easily reverted to "add a new
   M1 entry only" if preferred.
2. **README `25/25 dump/gcc/link` not re-run as a 25-program matrix.** The docs
   now assert the maintained example matrix is 25/25. I have direct evidence
   z9torr dumps/links under the seed (`tier1.sh` builds it) and the other 24 were
   previously green, but the full 25-way matrix was not re-executed in this
   docs-only closeout (the task scoped the gate to `tier1.sh` + discovery).
3. **Deferred test minors left as-is** (out of scope, docs-only): `tier1.sh:223`
   `grep -q "z9torr:"` is weaker than the intended `"z9torr: malformed torrent"`;
   `:230` truncated case can pass vacuously if the fixture is missing; `:234`
   relies on fixture field order. No test changes were authorized.
4. Pre-existing unrelated working-tree changes (`typo: untracked *.z98/*.err`
   scratch; modified `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/progress.md`)
   were left untouched and not staged.

## Fix round 1 (review Important — historical baselines falsified)

**Finding.** The 11 `24/24`→`25/25` edits were inside **dated** changelog entries
(`docs/sf/QUICK_REF.md:292,310,329,353,377,399,422,449,484,510,535`; dates
2026-09-29 … 2026-10-05). z9torr landed 2026-10-08, so at those dates the example
matrix was genuinely 24/24 (their neighboring corpus counts `1083…1097` are
pre-z9torr). Rewriting past measurements is a doc-accuracy defect.

**1. Revert.** All 11 dated `25/25` reverted to `24/24` — those lines are now
byte-identical to the pre-closeout file (`git diff <orig> -- …` empty for them).

**2. New dated entry.** Appended at `docs/sf/QUICK_REF.md:544` (below the last
dated baseline, above the self-consistency bullet), per the QUICK_REF append
convention — history not overwritten:

> **z9torr M1 closeout (2026-10-08; example-plan, compiler UNTOUCHED).** Adds the
> 25th `examples/z98/` entry `z9torr` (single-file torrent parse + metadata
> summary; `tests/tier1.sh` `15 passed, 0 failed / TIER1 PASS`; emitted-C md5
> `b0e8496d741aa130b7252bd7ebefe985`). Full example matrix re-measured over all 25
> `examples/z98/*/` dirs with the binding seed `/tmp/z9_m0_seed/zig1_5_clean`
> (`-ffast -o <out>` + `build_target.sh linux`, dump+gcc+link): **25/25 rc=0**
> (the dated entries above keep their contemporaneous 24/24). `verify_stdlib`
> **280 PASS / 0 FAIL** (unchanged). No compiler-only gates (fixed point / 8
> dump-MD5 pins / corpus classify) — no `sf/**` change.

**3. Matrix measured before asserting (25/25).** Binding seed recipe, repo-root
CWD, entry = `main.zig` else `<basename>.zig` else first `*.zig`:
```
ZIG=/tmp/z9_m0_seed/zig1_5_clean
for dir in examples/z98/*/; do
  name=$(basename "$dir"); entry=…            # resolution above
  out=/tmp/z9_matrix/$name; mkdir -p "$out"
  timeout 120 "$ZIG" -ffast -o "$out" "$entry"
  ( cd "$out" && timeout 120 sh build_target.sh linux "$out/prog" )
done
```
Result: **25 PASS / 0 FAIL over 25 dirs** — `days_in_month fibonacci
func_ptr_return game_of_life heapsort hello json_parser json_parser_upgraded
json_parser_workaround lisp_interpreter lisp_interpreter_adv
lisp_interpreter_curr lisp_interpreter_upgraded lzw mandelbrot mud_server prime
quicksort rogue_mud rogue_mud_upgraded sort_strings tco_defer tco_factorial
tco_return_try z9torr` all dump+gcc+link rc=0 (evidence `/tmp/z9_matrix/*/`).

**Residual.** None. The root `README.md` `25/25` claim is now independently
confirmed by this measured matrix. This Fix section supersedes Concern 1 above
(Concerns 2–4 remain accurate).
