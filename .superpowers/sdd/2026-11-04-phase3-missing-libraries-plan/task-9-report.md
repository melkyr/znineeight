# Task 9 report — Milestone 2 closeout (full battery + docs + seed decision)

- **Status:** DONE_WITH_CONCERNS (all required local gates PASS; the opt-in
  `git/git` real-network clone is a recorded SKIP after a 30-minute timeout).
- **Repo / HEAD at start:** `/workspace/znineeight`, HEAD `ddea82f8`.
- **Seed:** committed v141 (`release/seed/zig1-seed.tgz`), fixed point
  `cf68f192900e7f6618c11e1712b74b3a`.
- **No compiler or `std` source changes; no seed rotation (see §5).**

## 1. Seed build closure

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t9_seed
```

Result: PASS.

```text
[seed] hop1 binary md5: cf68f192900e7f6618c11e1712b74b3a
[seed] hop2 binary md5: cf68f192900e7f6618c11e1712b74b3a
[seed] two-hop closure OK: hop1 == hop2 == cf68f192900e7f6618c11e1712b74b3a
=== [seed] Done: /tmp/t9_seed ===
```

Compiler under test: `/tmp/t9_seed/zig1_5_clean` (v141 `lib/`, 52 std files).

## 2. Full battery

All commands run sequentially; long jobs used explicit timeouts. `Z98_NET` was
unset for the two full `tier_git` runs (the opt-in remotes are recorded
separately in §2.6).

### 2.1 Corpus and goldens

| Check | Command | Result |
|---|---|---|
| Live corpus | `bash scripts/corpus/classify /tmp/t9_seed/zig1_5_clean /tmp/t9_corpus_live.txt` | **1256 dirs = 1069 OK / 63 GREEN / 124 FAIL / 0 ICE / 0 CRASH**; class md5 `a2dd8b02023d49b1dff7ad47139b9a9e` |
| Frozen-1124 subset | filter the same classification rows through `scripts/corpus/frozen_1124.txt` | **1124 lines**, md5 `518eca1a9b5d3e1cc5a48abce214abd8`, tally **950 OK / 58 GREEN / 116 FAIL**, **0 movers** |
| Goldens | built programs below, compared to the documented md5s | **5/5** (plus the single-line lisp probe) |

Live growth is additive and matches the plan: +16 dirs vs the v135 baseline
(1240) = the 14 Task 1–3 stdlib fixture dirs plus the `z9git` and
`z9zstddecomp` example dirs. The frozen-1124 subset is byte-identical to the
anchor.

Golden runtime evidence (seed-built compilers, repo-root CWD where required):

```text
game_of_life (100 gens)      stdout fcbf7e7cead5082f0a8caadd5a8f0ff9  (2100 lines / 83490 B)
lisp_interpreter_curr        stdout b3d9f8974da24ddbf9d389f3d7d97322  ((+ 1 2))
lisp_interpreter_curr        stdout 96654b3910a54d8bb7ec3ddfc0f26c6a  (12-line canonical_feed.txt)
json_parser (test.json)      stdout 8bda3d5a1ec07d14a301bc343df32bf8
mud_server session.sh        server 66c8f0abb926cca7baf9a0d1692ab318
mud_server session.sh        client 93147d0f0bbd983a9d844fea8b7a6fa7
```

### 2.2 Pins, markers, stdlib, emit support, Windows gate

| Check | Command | Result |
|---|---|---|
| 8 dump pins | `bash scripts/compiler/gate_lower_depth.sh /tmp/t9_seed/zig1_5_clean` | `LOWER_DEPTH GATE OK`; case 5 **8/8** (mud/gol/lisp/json both `-fsafe` and `-ffast`) |
| Markers | `zig1 --markers --dump-c89 --output-dir /tmp/t9_markers examples/z98/mud_server/main.zig 2> /tmp/t9_markers.bin` | **3397 lines / 39012 B** (`wc -l -c`) |
| Full stdlib | `bash scripts/stdlib/verify_stdlib.sh /tmp/t9_seed/zig1_5_clean` | **356 PASS / 0 FAIL over 356 dirs**; **10 PASS / 0 FAIL over 10 modules**; `STDLIB GATE OK` |
| Emit support | `bash scripts/check_emit_support.sh /tmp/t9_seed/zig1_5_clean` | **8/8** byte-identical (`OK: 8/8 support files ...`) |
| Win compat | `bash scripts/compiler/gate_win_compat.sh /tmp/t9_seed/zig1_5_clean` | `WIN_COMPAT GATE OK` (self-emission, 97 module files scanned, 8 `.bat` lints, MinGW 52 TUs, no-CRT `-O2` Wine smoke); import gate SKIP by design (VM-only, no `--exe`) |

`gate_lower_depth` md5 sub-cases 6/8/9/10–12 SKIP without
`GATE_BASELINE_ZIG1`, as permitted; no baseline env was set. The pin cases (5)
and all runtime/guard cases passed.

### 2.3 Example matrix (28/28)

Matrix definition (the historical maintained set): all immediate
`examples/z98/` entries present at v98 (`566589b9`) plus the two Phase 3 app
dirs `z9git` and `z9zstddecomp`; `demo`, `gfx_demo`, `z9dbg`, and `z9edit` are
outside the matrix, as in prior closeouts. Each entry was emitted with
`zig1_5_clean -fsafe -o <fresh-dir> <entry>` and linked with the emitted
`build_target.sh linux prog`.

Result: **28 PASS / 0 FAIL**. The 28 entries: `days_in_month fibonacci
func_ptr_return game_of_life heapsort hello json_parser json_parser_upgraded
json_parser_workaround lisp_interpreter lisp_interpreter_adv
lisp_interpreter_curr lisp_interpreter_upgraded lzw mandelbrot mud_server prime
quicksort rogue_mud rogue_mud_upgraded sort_strings tco_defer tco_factorial
tco_return_try z9git z9play z9torr z9zstddecomp`.

### 2.4 `tier_zstddecomp`

```bash
ZIG=/tmp/t9_seed/zig1_5_clean OUT=/tmp/t9_tier_zstd \
  sh examples/z98/z9zstddecomp/tests/tier_zstddecomp.sh
```

Result: **44 passed, 0 failed, 0 skipped**; `TIER_ZSTDDECOMP PASS`. This
includes Linux decode goldens, the full exit-code contract, bare `-osw` emit,
MinGW no-CRT build, `check_win9x_imports.sh … 9x` PASS, and the two Wine cases
(plain + magic dictionary) with byte-equal output.

### 2.5 `tier_git` (two full runs, Wine included)

```bash
ZIG=/tmp/t9_seed/zig1_5_clean OUT=/tmp/t9_git_run1 \
  timeout 2400 bash examples/z98/z9git/tests/tier_git.sh
ZIG=/tmp/t9_seed/zig1_5_clean OUT=/tmp/t9_git_run2 \
  timeout 2400 bash examples/z98/z9git/tests/tier_git.sh
```

Both runs: **205 passed, 0 failed**; `TIER_GIT PASS`. The default tier includes
the Win9x no-CRT / 9x import gate, Wine clone/log and mocked-HTTP runs, the
Task 8b **100,000-object synthetic large pack** (default 32 MiB and
`--arena-mb 16`, `git verify-pack`/`fsck`/worktree), the Task 8c **abort/retry
prefix resume**, **shallow/deepen**, **partial per-directory blob** cases, and
the >4096 shallow-boundary growth case.

### 2.6 Opt-in real remotes

GitHub/GitLab (manual, same commands the tier uses under `Z98_NET=1`, run from
a fresh `/tmp/t9_git_opt` CWD with `ca_store.bin` copied beside it):

```text
z9git clone https://github.com/octocat/Hello-World /tmp/t9_git_opt/gh --depth 1
  GH=0; .git/shallow written; git verify-pack OK
z9git clone https://gitlab.com/gitlab-org/gitlab-test.git /tmp/t9_git_opt/gl --depth 1
  GL=0; .git/shallow written; git verify-pack OK
```

`git/git` opt-in — **SKIP (external network/timeout), not claimed PASS**:

```bash
z9git clone https://github.com/git/git.git /tmp/t9_git_opt/gitgit \
  --depth 1 --arena-mb 32
```

Timed out at the 30-minute bound: `Exit status: 124`, `Elapsed 30:00.00`, peak
RSS 49,708 kB. No local `git/git` mirror remained from Task 8b (the previous
mirror path no longer exists), so a local re-run was not possible. Task 8b's
earlier local-mirror attempt had failed rc4 `object-store` at the default
32 MiB arena (~34,628 kB peak RSS, 3:59.81) before the fix wave; the blockers
recorded then were the whole-idx/checkout retention plus git/git's three
symlinks (`RelNotes`, `subprojects/git-gui`, `subprojects/gitk`) and the
`sha1collisiondetection` gitlink/submodule. That measurement is historical
context, not a re-run here. The current round could therefore only retry over
the network, where the same throughput limitation recorded by Task 8b (HTTPS
~80 KB/s) prevented completion; the correctness path was not re-profiled.

### 2.7 Scope notes

`tier_gfx` / `tier_edit` were not run (untouched areas, not required by the
brief). No measured git performance profile was re-run.

## 3. Docs truth-up

Changed:

- **`README.md`**
  - Current Status: committed seed v141 (fixed point unchanged since v135),
    example matrix **28/28**, live corpus **1256 = 1069 OK / 63 GREEN / 124
    FAIL**, stdlib **356/0** + crosscheck 10/10.
  - Determinism: committed seed v141 with archive md5
    `3e99af1b8117b982c26b074a1ccd35f7`, Win9x zip md5
    `c45c26f72b6a81b153a9238550456b37`, manifest md5
    `4c979389dceb2d12442e557aaeabf44d`, 52 std files; notes the fixed point is
    unchanged across v136–v141.
  - Emission-gate / corpus summary: live v141 numbers and class md5
    `a2dd8b02…`, matrix 28/28, stdlib 356/0.
  - 52-file `lib/` in Minimum Requirements, Getting Started, and Minimal
    Distribution; Standard Library counts updated to 52 files / 51
    `std_*.zig` / 37 by-path / 32 public and `std_deflate` added.
  - Example Showcase: 28/28 plus explicit `z9git` and `z9zstddecomp` entries.
- **`docs/sf/QUICK_REF.md`**
  - Top battery paragraph: 28 examples, current v141 live corpus
    (1256 = 1069/63/124, class md5 `a2dd8b02…`), frozen-1124 unchanged,
    stdlib 356/0, markers/pins/goldens.
  - Added a concise “Phase 3 app entries (matrix 28/28)” note for
    `z9git`/`z9zstddecomp` and their gates.

Verified, no change needed:

- `STD_README.MD` already carried the v141 seed, archive/zip/manifest md5s, 52
  std files, and the `std_deflate` layer/domain entries.
- `sf/docs/tech_docs/` does not quote std-module counts.
- `examples/z98/z9git/README.md` and `examples/z98/z9zstddecomp/README.md`
  match the shipped CLIs: commands, `--arena-mb`/`--depth`/`--deepen`/
  `--partial`/`--max-down`/`--dict`/`--max-window-log`/`--max-output`, exit
  codes 0–5, local/`file://`/smart HTTP(S) transports, GitHub/GitLab
  normalization, resume/state, shallow/partial, disk/pack/object limits,
  trust store, public-only/no-LFS, and `-h` usage.

`git diff --check`: clean (rc 0).

## 4. Seed decision

Reference: the v141 rotation commit is `4f9ad455` (there is no
`v141-rotation` tag in this repo):

```bash
git diff --stat 4f9ad455..HEAD -- sf/src lib
```

Result: **empty**. `git status --porcelain -- sf/src lib release/seed` is also
empty. Therefore: **no lib change, no rotation.** The only `release/seed`
change since the rotation is the documentation/provenance correction at
`9e6b9038`, which does not change the payload or fixed point.

## 5. Files changed

- `README.md`
- `docs/sf/QUICK_REF.md`
- `.superpowers/sdd/2026-11-04-phase3-missing-libraries-plan/task-9-report.md`
  (this report)

No compiler, std, `examples/z98/z9git`, or seed payload changes.

## 6. Skipped / failed items

- **`git/git` opt-in remote clone: SKIP**, network timeout (rc 124 at 30:00),
  no local mirror. Task 8b's historical local-mirror attempt was rc4
  `object-store` (retained idx/checkout data plus symlink/gitlink blockers);
  the mirror was not retained, so this round could only retry the network.
  Not claimed PASS.
- **`gate_win_compat` PE import gate: SKIP**, VM-only (no operator-built PE
  supplied); all local text/emit/cross-compile checks passed.
- **`gate_lower_depth` md5 sub-cases 6/8/9/10–12: SKIP**, no
  `GATE_BASELINE_ZIG1` baseline supplied (allowed).
- `tier_gfx` / `tier_edit`: intentionally not run (untouched areas).
- No measured git performance profile was re-run.

No required local battery check failed.

## 7. Fix round 1 — README truth-up and accuracy notes (docs only)

Review finding: the README truth-up left contradictory 51-file/v135 references.

Changes:

- `README.md` Minimum Requirements: the 52-file `lib/` is now tied to the
  current v141 seed; the ~20 MB RSS figures remain explicitly labelled as v135
  measurements with the fixed point unchanged at v141.
- `README.md` Getting Started / install guidance: the current repo seed is
  v141 with 52 std files; the historical 0.21.2 source archive's 51-file
  payload is called out separately.
- `README.md` release artifacts: relabelled **Historical release artifacts
  (0.21.2, seed v135; separate from the current v141/52-file repo seed)**. The
  historical 51-file `lib/` and manifest `62008632…` are retained only under
  that label, so they no longer contradict the current v141/52-file state.
- `task-9-report.md`: §2 pointer corrected from §2.3 to §2.6; `gfx_demo` added
  to the example-matrix exclusions; the `git/git` SKIP now records the Task 8b
  historical local-mirror rc4 `object-store` result and the symlink/gitlink
  blocker context, not only the 30-minute network timeout.

Verification: `git diff --check` clean (rc 0); grep confirms every remaining
51-file / seed-v135 statement is either a clearly labelled historical release
artifact or a v135 measurement label, with no contradictory current count.
Docs only — no code/compiler/std/seed change and no battery re-run.
