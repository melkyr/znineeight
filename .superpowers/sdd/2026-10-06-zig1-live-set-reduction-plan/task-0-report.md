# Task 0 — Baseline + metric freeze (READ-ONLY) report

Plan: `docs/superpowers/plans/2026-10-06-zig1-live-set-reduction-plan.md`
Spec: `docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md`
Branch: `zig1_improvements` (NO push). This task made **no `sf/src` edit**, **no seed rotation**, and
**no dump-MD5 re-baseline** — it only *records* the frozen baseline. All self-compiles ran with CWD
`/workspace/znineeight` and the RELATIVE source arg `sf/src/main.zig`.

Binding metric = peak **RSS** (`/usr/bin/time -v` "Maximum resident set size"), median of ≥3
interleaved self-compile runs. `pool`/`total`/per-arena carve are context only.

---

## Step 1 — Seed build (v92 seed → current HEAD)

`sf/src` already includes the L3 fix (`2d713a9a`), so the build is made **without** a
`FIXED_POINT_MD5` pin (the pinned v92 fixed point `d40e875a…` predates L3); the gate is the two-hop
closure `hop1 == hop2` at the current HEAD's fixed point.

Command (verbatim):

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/liveset_seed
```

Evidence:

- Archive: `release/seed/zig1-seed.tgz`, md5 **`3cacdd44df75c0ce96abfd51af93f928`** (matches seed v92).
- Archived v92 binary fixed point (from `release/seed/CHANGELOG.md`): **`d40e875a7ba3aa55d441af56006f6023`**.
- `[seed] hop1 binary md5: 2293f756a8250351740cf6acde194d17`
- `[seed] hop2 binary md5: 2293f756a8250351740cf6acde194d17`
- `[seed] two-hop closure OK: hop1 == hop2 == 2293f756a8250351740cf6acde194d17`
- `=== [seed] Done: /tmp/liveset_seed ===`, rc = 0.

**Measurement binary:** `/tmp/liveset_seed/zig1_5_clean`
- md5 **`2293f756a8250351740cf6acde194d17`** (== the current-HEAD two-hop fixed point), size 3,094,216 B.

The v92 archived binary (`d40e875a…`) differs from the current-HEAD fixed point (`2293f756…`) exactly
because `sf/src` now carries the L3 per-module `diag_read` reset (`2d713a9a`); the closure itself is
an exact fixed point, which is the required gate for a post-L3 tree.

## Step 2 — `-s0` self-compile (RSS / pool / total)

Command (per Global Constraints; the `-o` dir MUST pre-exist):

```
mkdir -p <fresh-dir>
/usr/bin/time -v /tmp/liveset_seed/zig1_5_clean -s0 --markers --track-memory -o <fresh-dir> sf/src/main.zig
```

Three interleaved samples (each rc = 0, stdout empty, markers on stderr):

| # | Maximum RSS (kbytes) | Elapsed (wall) | output `.c` / `.h` |
|---|---:|---|---|
| 1 | 17,296 | 0:04.14 | 48 / 48 |
| 2 | 17,424 | 0:04.13 | 48 / 48 |
| 3 | 17,564 | 0:04.07 | 48 / 48 |
| **median** | **17,424** | ≈0:04.1 | **48 / 48** |

`--track-memory` line (stderr, byte-identical across all three samples):

```
track-memory: perm=982K mod=1020K scr=965K pool=14924K type_db=346K total=2967K
```

- `pool = 14,924 K` — exactly the post-L3 figure the spec/plan quote.
- `total = 2,967 K` (live perm+mod+scr single-segment peaks; context only).
- Dump output: **48 `.c` + 48 `.h`** (+ `build_target.sh`). 0 `error[` / 0 `PANIC` in the markers.

## Step 3 — Per-arena carve table (`-s0`)

Carve = Σ of the `new` value over every `arena <name>: grew <old> -> <new>` line
(`arenaGrew`, `sf/src/allocator.zig:193`; 34 events total at `-s0`).

| arena | Σ new (bytes) | Σ new (K) | grew events |
|---|---:|---:|---:|
| module | 5,382,144 | 5,256.0 | 7 |
| diag_read | 4,655,313 | 4,546.2 | 7 |
| perm | 2,558,152 | 2,498.2 | 3 |
| import_scratch | 1,385,155 | 1,352.7 | 6 |
| type_db | 1,032,192 | 1,008.0 | 6 |
| scratch | 223,519 | 218.3 | 5 |
| source | 0 | 0 | 0 |
| **Σ** | **15,236,475** | **14,879.4** | **34** |
| pool (`track-memory`) | 15,282,176 | 14,924 | — |
| residual (pool − Σ) | 45,701 | 44.6 | — |

Matches the spec's post-L3 carve exactly: `module ≈ 5,256 K`, `diag_read ≈ 4,545 K`,
`perm ≈ 2,497 K`, `import_scratch ≈ 1,353 K`, `type_db ≈ 1,008 K`, `scratch ≈ 218 K`,
`source = 0`; Σ ≈ pool (residual 44.6 K = initial embedded segments + `SandSegment` headers +
alignment, not reported by `arenaGrew`). `source` satisfies from `seg_free_head` reuse, so no carve
event fires (do not hunt a `-s0` `source` carve).

Raw `arena grew` lines (sample 1) for reproducibility:

```
arena scratch: grew 4096 -> 100639
arena perm: grew 4096 -> 503192
arena perm: grew 503192 -> 1006384
arena perm: grew 1006384 -> 1048576
arena module: grew 4096 -> 8192
arena import_scratch: grew 256 -> 12050
arena import_scratch: grew 256 -> 45121
arena import_scratch: grew 256 -> 98582
arena import_scratch: grew 256 -> 531960
arena import_scratch: grew 256 -> 596656
arena import_scratch: grew 256 -> 100786
arena module: grew 196608 -> 393216
arena scratch: grew 4096 -> 8192
arena scratch: grew 8192 -> 16384
arena module: grew 393216 -> 786432
arena type_db: grew 8192 -> 16384
arena type_db: grew 16384 -> 32768
arena type_db: grew 32768 -> 65536
arena type_db: grew 65536 -> 131072
arena type_db: grew 131072 -> 262144
arena scratch: grew 16384 -> 32768
arena scratch: grew 32768 -> 65536
arena module: grew 786432 -> 1048576
arena module: grew 1048576 -> 1048576
arena diag_read: grew 4096 -> 100639
arena diag_read: grew 100639 -> 201278
arena diag_read: grew 201278 -> 402556
arena module: grew 1048576 -> 1048576
arena type_db: grew 262144 -> 524288
arena diag_read: grew 402556 -> 805112
arena diag_read: grew 805112 -> 1048576
arena diag_read: grew 1048576 -> 1048576
arena module: grew 1048576 -> 1048576
arena diag_read: grew 1048576 -> 1048576
```

## Step 4 — Frozen equivalence baseline

### 4a. Dump-MD5 pins — 8/8 (stdout stream)

Method: `timeout 120 /tmp/liveset_seed/zig1_5_clean [-fsafe|-ffast] --dump-c89 examples/z98/<prog>/main.zig | md5sum`.
`-fsafe` is the default and authoritative; `-ffast` is the byte-anchor.

| Program (entry) | `-fsafe` (default) | `-ffast` | dump rc |
|---|---|---|---|
| `examples/z98/game_of_life/main.zig` (gol) | `6df1e4d2e9afa0f4163a7053f67384be` | `98e934f3e15be355d47e26ded595dc8a` | 0 / 0 |
| `examples/z98/lisp_interpreter_curr/main.zig` (lisp) | `e27b7c35678974deb130cfc77cb08686` | `2514f8b5ddceacba67203af37a7346c3` | 0 / 0 |
| `examples/z98/json_parser/main.zig` (json) | `d51f17aebdabcd009e453adb2e286d4e` | `e1cc386e9d09e322a068731cb2061621` | 0 / 0 |
| `examples/z98/mud_server/main.zig` (mud) | `f3be9bb9ebc0c1c9799da2181e2fa7e8` | `66d547d4a076fc2ce44d6d3aa3092c1d` | 0 / 0 |

**All 8 values reproduce the current `docs/sf/QUICK_REF.md` pins exactly (8/8).**

### 4b. Corpus classify tally

```
timeout 600 bash scripts/corpus/classify /tmp/liveset_seed/zig1_5_clean /tmp/ls_corpus.txt
```

- rc = 0; `wrote /tmp/ls_corpus.txt: 1097 dirs`.
- **Tally: 1097 = 923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH.**
- Matches the recorded A9-F corpus state exactly.

### 4c. `verify_stdlib`

```
timeout 600 bash scripts/stdlib/verify_stdlib.sh /tmp/liveset_seed/zig1_5_clean
```

- rc = 0; `run_fixtures: 266 PASS / 0 FAIL over 266 dirs` → **`STDLIB GATE OK`**.

### 4d. Examples matrix — 24/24

Every resolvable `examples/z98/<dir>/` entry (`main.zig` → `<name>.zig` → first `*.zig`):
dump + gcc + link each.

- **`MATRIX total=24 ok=24 dumpfail=0 gccfail=0 linkfail=0`** — 20 `main.zig` dirs + 4 single-file
  entries (`func_ptr_return`, `mandelbrot`, `quicksort`, `sort_strings`).

### 4e. Runtime goldens — gol / lisp / json / mud

Per-program `-fsafe --dump-c89 --output-dir` → gcc `-m32 -std=c89 -O0 -Wall … -I .` per `.c` →
`gcc -m32 -O0 *.o -o prog`; then run and md5 stdout.

| Program | Run | Observed stdout md5 | Golden | Match |
|---|---|---|---|---|
| gol (`game_of_life`) | `./gol/prog` (100 gens, rc 0) | `fcbf7e7cead5082f0a8caadd5a8f0ff9` | `fcbf7e7c…` | ✅ |
| lisp (`lisp_interpreter_curr`) | `printf '(+ 1 2)\n' \| ./lisp/prog` (rc 0) | `b3d9f8974da24ddbf9d389f3d7d97322` | `b3d9f897…` | ✅ |
| json (`json_parser`) | `(cd examples/z98/json_parser && ./json/prog)` (rc 0) | `8bda3d5a1ec07d14a301bc343df32bf8` | `8bda3d5a…` | ✅ |
| mud (`mud_server`) | `(cd examples/z98/mud_server && bash demo/session.sh ./mud/prog srv cli)` (rc 0) | server `66c8f0abb926cca7baf9a0d1692ab318` / client `93147d0f0bbd983a9d844fea8b7a6fa7` | `66c8f0ab…` / `93147d0f…` | ✅ |

All four dump rc=0, gcc/link OK, run rc=0, runtime output **byte-exact** to the QUICK_REF goldens.

## Step 5 — Win98 idle floor (documented; target deferred)

The design spec (`docs/superpowers/specs/2026-10-06-zig1-live-set-reduction-design.md`, §Metric)
records the documented context: a vanilla **Windows 98** boot has a floor of **min 16 MB**, with a
clean-boot range of **~12–18 MB** depending on drivers, leaving roughly **14–20 MB** on a 32 MB
machine.

**No concrete target is fixed by this plan.** The exact OS floor is a deferred out-of-scope
measurement (an 86Box/PCem Win98 idle measurement), and the concrete RSS target is deferred to the
**operator's ruling on Task 3's ranked savings table**. This task only freezes the baseline
(§Steps 1–4) the ruling will be measured against.

## Concerns

1. **`-o <dir>` requires the output directory to pre-exist.** The literal self-compile command fails
   `rc=1` with `error: output directory does not exist: <dir>` unless `mkdir -p <dir>` runs first.
   The baseline was measured after pre-creating the dir (compiler flags/args otherwise verbatim);
   latter tasks must pre-create their `-o` dirs.
2. **Seed v92 archived binary ≠ current-HEAD fixed point.** `d40e875a…` (v92) vs `2293f756…`
   (current HEAD), caused by the post-v92 L3 fix now in `sf/src`. This is expected and is exactly why
   the pin is omitted; the required `hop1 == hop2` closure holds.
3. **RSS median (17,424 K ≈ 17.0 MB) is slightly below the spec's expected ≈17.5–17.6 MB** — within
   host noise across the three samples (range 17,296–17,564 K); `pool` is rock-stable at 14,924 K.
4. **`source` arena carve = 0 at `-s0`** (satisfied from `seg_free_head` reuse) — do not expect a
   `source` carve event.
5. **`mod=`/`scr=` are per-segment high-water peaks, not footprints** (carried from the prior spike);
   the carve table (Σ `new`) is the pool-footprint attribution and `total=` is `perm+mod+scr`
   single-segment peaks, not a live total.
6. **Untracked root strays** (`anytype_pos.z98`, `fi.err`, `q.err`, `sh.err`, `for_*.z98`,
   `name_u65.z98`, `num_member.z98`, `sz_u0.z98`) pre-existed and were deliberately **not** staged;
   only this report is committed.
7. **Throwaway measurement scripts** live in `/tmp` (`/tmp/ls_examples_matrix.sh`,
   `/tmp/ls_run_goldens.sh`) and are **not** committed.

## Commands used (evidence)

```
# Step 1
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/liveset_seed
md5sum /tmp/liveset_seed/zig1_5_clean   # 2293f756a8250351740cf6acde194d17

# Step 2 (repeat x3 interleaved; fresh dir each)
mkdir -p /tmp/ls_runN/out
/usr/bin/time -v -o /tmp/ls_runN/time.txt /tmp/liveset_seed/zig1_5_clean \
    -s0 --markers --track-memory -o /tmp/ls_runN/out sf/src/main.zig

# Step 3
awk '/arena .*: grew/ {name=$2; sub(/:$/,"",name); sum[name]+=$6} \
     END{for(n in sum) print n, sum[n]}' /tmp/ls_run1/markers.txt

# Step 4a (repeat with -ffast)
for e in game_of_life lisp_interpreter_curr json_parser mud_server; do
  /tmp/liveset_seed/zig1_5_clean --dump-c89 examples/z98/$e/main.zig | md5sum
done

# Step 4b/4c
timeout 600 bash scripts/corpus/classify /tmp/liveset_seed/zig1_5_clean /tmp/ls_corpus.txt
timeout 600 bash scripts/stdlib/verify_stdlib.sh /tmp/liveset_seed/zig1_5_clean

# Step 4d/4e
bash /tmp/ls_examples_matrix.sh
bash /tmp/ls_run_goldens.sh /tmp/liveset_seed/zig1_5_clean    # + mud rebuilt after mkdir-first fix
```
