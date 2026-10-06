# Task 0 — Preflight baseline (READ-ONLY) report

Plan: `docs/superpowers/plans/2026-10-06-zig1-diag-read-retention-reduction-plan.md`
Spec: `docs/superpowers/specs/2026-10-06-zig1-diag-read-retention-reduction-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no seed rotation**,
and **no dump-MD5 re-baseline** — it only *records* the pre-fix baseline. All self-compiles ran with
CWD `/workspace/znineeight` and the RELATIVE source arg `sf/src/main.zig`.

## Step 1 — Seed build (v92)

Command (verbatim per Global Constraints):

```
FIXED_POINT_MD5=d40e875a7ba3aa55d441af56006f6023 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/retention_seed
```

- **rc = 0** (the pinned gate passes now — no mismatch).
- Archive: `release/seed/zig1-seed.tgz`, md5 **`3cacdd44df75c0ce96abfd51af93f928`** (matches spec v92).
- `[seed] hop1 binary md5: d40e875a7ba3aa55d441af56006f6023`
- `[seed] hop2 binary md5: d40e875a7ba3aa55d441af56006f6023`
- `[seed] two-hop closure OK: hop1 == hop2 == d40e875a7ba3aa55d441af56006f6023`
- `[seed] recorded fixed point OK: d40e875a7ba3aa55d441af56006f6023`
- `=== [seed] Done: /tmp/retention_seed ===`

**Measurement binary:** `/tmp/retention_seed/zig1_5_clean`
- md5 **`d40e875a7ba3aa55d441af56006f6023`** (== the v92 fixed point), ELF 32-bit LSB pie (i386),
  size 3,094,216 B.

## Step 2 — `-s0` self-compile (pool + carve)

Command (per Global Constraints):

```
timeout 120 /usr/bin/time -v /tmp/retention_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/retention_s0 sf/src/main.zig
```

- **rc = 0**; stdout empty (0 B); markers on **stderr**.
- `--track-memory` line (stderr, verbatim):
  `track-memory: perm=982K mod=1020K scr=1020K pool=19274K type_db=346K total=3022K`
- `/usr/bin/time -v`: **Maximum resident set size = 20,216 kbytes**; Elapsed (wall) = **0:04.22**.
- Dump output (`/tmp/retention_s0`): **48 `.c`**, **48 `.h`** (plus `build_target.sh`; 97 entries total).

> Operational note: `-o <dir>` requires the output directory to **already exist**. The command as
> written fails `rc=1` with `error: output directory does not exist: /tmp/retention_s0` unless
> `mkdir -p /tmp/retention_s0` is run first (see Concerns #1). The measurement below was taken after
> pre-creating the dir; the compiler invocation is otherwise verbatim.

### Per-arena carve table (`-s0`)

Carve = Σ of the `new` value over every `arena <name>: grew <old> -> <new>` line
(`arenaGrew`, `sf/src/allocator.zig:193`; fires only on a genuine new carve from the backing pool).

| arena | Σ new (bytes) | Σ new (K) | grew lines |
|---|---:|---:|---:|
| module | 5,382,144 | 5,256.0 | 7 |
| scratch | 4,679,906 | 4,570.2 | 13 |
| diag_read | 4,654,398 | 4,545.3 | 7 |
| perm | 2,557,240 | 2,497.3 | 3 |
| import_scratch | 1,385,155 | 1,352.7 | 6 |
| type_db | 1,032,192 | 1,008.0 | 6 |
| source | 0 | 0 | 0 |
| **Σ** | **19,691,035** | **19,229.5** | **42** |
| pool (`track-memory`) | 19,736,576 | 19,274 | — |
| untracked remainder (pool − Σ) | 45,541 | 44.5 | — |

Matches the plan's expected figures exactly: `module ≈ 5,256 K`, `diag_read ≈ 4,545 K`,
`scratch ≈ 4,570 K`, `import_scratch ≈ 1,353 K`, `perm ≈ 2,497 K`, `type_db ≈ 1,008 K`,
`source = 0`; Σ 19,691,035 B ≈ pool 19,274 K (residual 44.5 K = initial embedded segments +
`SandSegment` headers + 4-byte alignment, not reported by `arenaGrew`).

### Bonus anchor — `--markers` stderr (for later-task byte-identity comparison)

`-s0 --markers --track-memory` stderr (markers only, no `/usr/bin/time`):
- md5 **`295de244d1e1509f8cf1df3b84fdbde9`**, 48,715 lines, 582,546 bytes.
- Verified **deterministic** (two independent runs byte-identical, same md5).

## Step 3 — Pre-fix dump-MD5 baseline (the value the spike never recorded)

### 3a. Prior-spike method (authoritative, stdout single-stream)

Method replicated from the logic-dedup plan Task-0 Step 3e
(`.superpowers/sdd/2026-10-05-compiler-logic-dedup-and-reuse-plan/task-0-report.md:194-205`) and the
QUICK_REF byte-identity gate (`docs/sf/QUICK_REF.md:198-232`):

```
timeout 120 /tmp/retention_seed/zig1_5_clean [-fsafe|-ffast] --dump-c89 examples/z98/<prog>/main.zig | md5sum
```

`-fsafe` is the default and authoritative; `-ffast` is the byte-anchor.

| Program (entry) | `-fsafe` (default) | `-ffast` | dump rc |
|---|---|---|---|
| `examples/z98/game_of_life/main.zig` (**gol**) | `6df1e4d2e9afa0f4163a7053f67384be` | `98e934f3e15be355d47e26ded595dc8a` | 0 / 0 |
| `examples/z98/lisp_interpreter_curr/main.zig` (**lisp**) | `e27b7c35678974deb130cfc77cb08686` | `2514f8b5ddceacba67203af37a7346c3` | 0 / 0 |
| `examples/z98/json_parser/main.zig` (**json**) | `d51f17aebdabcd009e453adb2e286d4e` | `e1cc386e9d09e322a068731cb2061621` | 0 / 0 |
| `examples/z98/mud_server/main.zig` (**mud**) | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | `66d547d4a076fc2ce44d6d3aa3092c1d` | 0 / 0 |

**All 8 values reproduce the current QUICK_REF pins exactly (8/8).** These four are the programs the
prior spike used (the brief's `gol/lisp/json/mud`; the actual directory names are
`game_of_life` / `lisp_interpreter_curr` / `json_parser` / `mud_server`).

### 3b. Directory-level file counts + sorted-concat hash (secondary anchor)

Parenthetical method from the brief: `-fsafe`/`-ffast` `--dump-c89 --output-dir` per program, then
sort the emitted `.c`/`.h` names and concatenate their contents to a hash:

```
cd <dumpdir> && ls *.c *.h | sort | xargs cat | md5sum
```

| mode | program | `.c` | `.h` | sorted-concat md5 |
|---|---|---:|---:|---|
| `-fsafe` | gol | 7 | 8 | `5494aa70182b3dc9171e3aed1dad61e7` |
| `-fsafe` | lisp | 15 | 16 | `89e439abb71ef86a42cf10efcfd59eef` |
| `-fsafe` | json | 9 | 10 | `cab84343e4bc432d3401ae98d5ba53bc` |
| `-fsafe` | mud | 9 | 10 | `e36ebdcd771a2baaae31728aed4c090c` |
| `-ffast` | gol | 7 | 8 | `a379790d2d03945631d4c19e5fe9f764` |
| `-ffast` | lisp | 15 | 16 | `0d52a9736aa200a454811859fc112c47` |
| `-ffast` | json | 9 | 10 | `20a5b0723a57f30815efb83e9e148c2c` |
| `-ffast` | mud | 9 | 10 | `01b15a3cdfdc50d480af68c17789aa2c` |

All 8 `--output-dir` dumps rc=0. The two methods are **not interchangeable** (see Concerns #2); the
stdout-stream values in 3a are the ones directly comparable to the QUICK_REF pins.

## Step 4 — Corpus / goldens / stdlib

### 4a. Corpus classify tally

```
timeout 600 bash scripts/corpus/classify /tmp/retention_seed/zig1_5_clean /tmp/retention_corpus.txt
```

- rc = 0; `wrote /tmp/retention_corpus.txt: 1097 dirs`; wall **2m49.9s**.
- **Tally: 1097 = 923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH.**
- Matches the recorded A9-F (v296) corpus state exactly.

### 4b. Runtime goldens (gol / lisp / json / mud)

Per-program `-fsafe --dump-c89 --output-dir` → gcc `-m32 -std=c89 -O0 -Wall … -I .` per `.c` →
`gcc -m32 -O0 *.o -o prog`; then run and md5 stdout (harness `/tmp/run_ret_goldens.sh`).

| Program | Run | Observed stdout md5 | Golden | Match |
|---|---|---|---|---|
| gol (`game_of_life`) | `./gol/prog` (100 gens, rc 0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | ✅ |
| lisp (`lisp_interpreter_curr`) | `printf '(+ 1 2)\n' \| ./lisp/prog` (rc 0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | ✅ |
| json (`json_parser`) | `(cd examples/z98/json_parser && ./json/prog)` (rc 0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | ✅ |
| mud (`mud_server`) | `(cd examples/z98/mud_server && bash demo/session.sh …)` (rc 0) | server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7` | `66c8f0ab…` / `93147d0f…` | ✅ |

All four dump rc=0, gcc/link OK, run rc=0, runtime outputs **byte-exact** to the QUICK_REF goldens.

### 4c. `verify_stdlib`

```
timeout 600 bash scripts/stdlib/verify_stdlib.sh /tmp/retention_seed/zig1_5_clean
```

- rc = 0; wall **1m52.0s**.
- `run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → **`STDLIB GATE OK`**.

## Step 5 — Commit

Report committed with `git add -f` and the exact message `docs: diag_read retention plan — Task 0 baseline`.
Commit contains **only this report file** (no source, no seed, no strays; `.superpowers/sdd/` is gitignored).

## Concerns

1. **`-o <dir>` requires the output directory to pre-exist.** The brief's literal self-compile command
   (`… -o /tmp/retention_s0 sf/src/main.zig`) exits `rc=1` with
   `error: output directory does not exist: /tmp/retention_s0` until `mkdir -p /tmp/retention_s0` is
   run. The baseline was measured after pre-creating the dir (compiler flags/args otherwise verbatim).
   Later tasks/quotes should pre-create their `-o` dirs. This is an operational prerequisite, not a
   measurement deviation.
2. **Two dump-MD5 methods exist and are not interchangeable.** The prior spike (and the QUICK_REF
   pins) use the stdout single-stream md5 (`--dump-c89 … | md5sum`); the brief's parenthetical
   describes a directory `--output-dir` + sorted-concat hash. Both are recorded above. Later tasks
   should fix one as authoritative — **recommend the 3a stdout-stream values** (8/8 reproducible
   against QUICK_REF).
3. **`source` arena carve = 0 at `-s0`** (as in the prior spike). `source` still holds up to ~583 K
   live per module but satisfies it from `seg_free_head` reuse, so `arenaGrew` never fires. Do not
   hunt a `-s0` `source` carve.
4. **`mod=` / `scr=` are `Sand.peak` per-segment high-water, not footprints** (carried from the prior
   spike Task 2). The carve table (Σ `new`) is the pool-footprint attribution; `total=` is
   `perm+mod+scr` single-segment peaks, not a live total.
5. **`L nodes=` marker is compiled out** (`g_markers_debug = 0`, `sf/src/pal.zig:210-216`); only
   `IRN:n`/`IRE:x`/`INT:newN` scale markers are observable under `--markers`.
6. **Untracked root strays** (`anytype_pos.z98`, `*.err`, `for_*.z98`, `name_u65.z98`,
   `num_member.z98`, `sz_u0.z98`) pre-existed and were deliberately **not** staged; only this report
   is committed.
7. **No `--track-memory`/`-s1`/`-s2` levels measured here** — Task 0's scope is the `-s0` self-compile
   + the four gate programs. `-s1`/`-s2` are available from the prior spike if needed.

## Commands used (evidence)

```
# Step 1
FIXED_POINT_MD5=d40e875a7ba3aa55d441af56006f6023 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/retention_seed
# Step 2
mkdir -p /tmp/retention_s0
timeout 120 /usr/bin/time -v /tmp/retention_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/retention_s0 sf/src/main.zig
grep -a "^arena " /tmp/retention_s0.err | awk '{name=$2; sub(/:$/,"",name); sum[name]+=$6} END{for(n in sum) print n, sum[n]}'
# Step 3  (repeat for -ffast; repeat for --output-dir file counts)
for p in game_of_life lisp_interpreter_curr json_parser mud_server; do
  timeout 120 /tmp/retention_seed/zig1_5_clean -fsafe --dump-c89 examples/z98/$p/main.zig | md5sum
done
# Step 4
timeout 600 bash scripts/corpus/classify /tmp/retention_seed/zig1_5_clean /tmp/retention_corpus.txt
bash /tmp/run_ret_goldens.sh /tmp/retention_seed/zig1_5_clean
timeout 600 bash scripts/stdlib/verify_stdlib.sh /tmp/retention_seed/zig1_5_clean
```
