# zig0 vs zig1 vs zig1_5 — Memory + Wall-Clock Comparison — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure and compare peak memory (RSS + allocator/pool peaks) and wall-clock time of zig0 vs zig1 vs zig1_5 at HEAD `cfb2f54a`, quantify the cost of producing zig1 (self-compile), detect zig1↔zig1_5 inconsistency, and recommend the correct size to replace the 256 MiB measurement pool. Investigation only — no `sf/src` source changes.

**Architecture:** Four measurement runs in the T5 shape: (A) zig0→zig1, (B) zig1→zig1_5 (both self-compiles), (C) zig1_clean→examples, (D) zig1_5_clean→examples. Metrics: `/usr/bin/time -v` (RSS + wall/user), `--track-memory --markers` (pool + arena peaks for zig1/zig1_5), valgrind massif (zig0 heap, one run). Compare A vs B (cost to produce zig1), C vs D (consistency), then derive `POOL_SIZE` = max measured pool.peak + ≥25% margin.

**Tech Stack:** Zig compiler (`sf/src/*.zig`), C++98 bootstrap (`src/bootstrap/*.cpp`), gcc -m32, valgrind massif, `/usr/bin/time -v`, bash (build/measure scripts).

## Global Constraints

- **No `sf/src` source changes anywhere in this plan** (measurement only). Reports are the deliverable. The 4 MD5 byte-identity gates (gol `eed963e0…`, lisp `c3c58477…`, json `089e4f04…`, mud `a1d0dd55…`) must remain unchanged — trivially true with no source edits; sanity-check at GATE.
- Compilers under test: zig0 `build/zig0`, zig1 `/tmp/fx_subfolder/zig1` (ASan, producer), `zig1_clean` (no-ASan, built this plan), zig1_5 `/tmp/zig1_5/zig1_5_clean` (no-ASan).
- Builds: `timeout 900 bash sf/scripts/build_release.sh` from REPO ROOT (gate `=== [release] Done ===`), WIPES `/tmp/fx_subfolder` → reinstall std lib `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`. Self-compile build: `timeout 900 bash scripts/self_compile/build_zig1_5.sh`.
- zig0 build: `mkdir -p build && g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0` (repo root).
- `timeout 120` on every compiler/binary invocation; on timeout STOP.
- Never touch/ls `sf/build/out_release/` (WEDGED). Editing: `edit`/`fastedit` only (no `sf/src` edits expected at all).
- `--track-memory` requires `--markers` to print (markerWrite is gated). On self-compile, `--markers` floods stderr (~4.8M lines) — redirect `2> file`, then `grep "track-memory:" file`.
- `--output-dir` must pre-exist before each `--dump-c89` run (else rc=1 "cannot open output file").
- Z98 example ladder: `examples/z98/{hello,game_of_life,lisp_interpreter_curr,json_parser,rogue_mud}` (entry = `main.zig`).
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent memcmp-session --type <discovery|decision|problem|pattern>` per task.
- Reports: `.superpowers/sdd/task-<N>-report.md` (gitignored). WARNING: `.superpowers/sdd/task-1-report.md` is TRACKED with unrelated content — never reuse that name; use `task-MEMCMP-report.md` etc.
- Prior reference numbers (report context, NOT gates): 2026-08-25 partial self-compile `perm=1978K mod=16197K scr=2037K pool=83194K type_db=247K total=20212K`, RSS ≈ 49 MB (ASan), wall 3.4 s; MEM2 zig0 self-compile 40,996 KB RSS / 40.1 MB heap.

---

### Task 1: Build the compiler matrix

**Files:**
- No repo source changes. Build artifacts only (`build/zig0`, `/tmp/fx_subfolder/zig1`, `/tmp/fx_subfolder/zig1_clean`, `/tmp/zig1_5/zig1_5_clean`).
- Report: `.superpowers/sdd/task-MEMCMP-report.md` (append per task)

**Interfaces:**
- Consumes: build scripts (`build_release.sh`, `build_zig1_5.sh`), zig0 bootstrap source.
- Produces: all 4 binaries available + identity (md5, size, `file`) recorded for the measurement tasks.

- [ ] **Step 1: Build zig0**

```bash
cd /workspace/znineeight && mkdir -p build && timeout 900 g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0
```
Record rc; expect 0. (Also produced by build_release.sh, but build it explicitly so it exists independently.)

- [ ] **Step 2: Build zig1 (ASan) + zig1_clean (no-ASan)**

```bash
cd /workspace/znineeight && timeout 900 bash sf/scripts/build_release.sh   # gate: === [release] Done ===
mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```
Then emit `zig1_clean` from the SAME emitted C (no ASan), replicating build_release.sh's gcc line minus `-fsanitize=address`:
```bash
cd /workspace/znineeight && gcc -m32 -std=c89 -O0 -Wall \
  -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration \
  -Iinclude /tmp/fx_subfolder/*.c src/include/zig_pal.c -o /tmp/fx_subfolder/zig1_clean
```
Run from repo root with the same `-Iinclude`/relative paths build_release.sh uses. Record rc; expect 0. Record `md5sum`, `size` (text/data/bss via `size`), `file` for both zig1 and zig1_clean. The 256 MiB BSS must appear in both.

- [ ] **Step 3: Build zig1_5 (clean + asan)**

```bash
cd /workspace/znineeight && timeout 900 bash scripts/self_compile/build_zig1_5.sh   # gate: === [zig1_5] Done: /tmp/zig1_5 ===
```
Confirm 40 `.c` in `/tmp/zig1_5/gen`, 0 gcc `error[` lines, both binaries produced. Record `md5sum` + `size` for `zig1_5_clean`.

- [ ] **Step 4: Identity table + report + ledger**

Report `.superpowers/sdd/task-MEMCMP-report.md`: build matrix table (binary, md5, text/data/bss, file, build cmd, rc). Ledger + mnemoria (discovery). Confirm no repo files modified (`git status --short` clean apart from pre-existing uncommitted files).

---

### Task 2: Self-compile memory + time (Run A zig0→zig1, Run B zig1→zig1_5)

**Files:**
- Report: `.superpowers/sdd/task-MEMCMP-report.md` (append section)

**Interfaces:**
- Consumes: Task 1 binaries.
- Produces: A-vs-B comparison — memory (RSS, heap/pool peaks) + wall/user time to produce zig1 vs zig1_5.

- [ ] **Step 2.1: Run A — zig0 self-compiles sf/src → zig1**

```bash
mkdir -p /tmp/za && cd /workspace/znineeight
/usr/bin/time -v build/zig0 --header-priority-include -o /tmp/za/zig1.c sf/src/main.zig 2> /tmp/za/time.log
```
Record rc + from `/tmp/za/time.log`: Maximum resident set size (kbytes), Elapsed (wall clock), User time. Then one massif run for heap ground truth:
```bash
valgrind --tool=massif --massif-out-file=/tmp/za/massif.out --stacks=yes build/zig0 --header-priority-include -o /tmp/za/massif_zig1.c sf/src/main.zig 2>/dev/null
ms_print /tmp/za/massif.out | grep -E "mem_heap_B=" | tail -1
```
Record peak heap. Expect ≈40 MB heap / ≈41 MB RSS (MEM2 ground truth).

- [ ] **Step 2.2: Run B — zig1 self-compiles sf/src → zig1_5 (40 .c)**

```bash
mkdir -p /tmp/zb/gen
/usr/bin/time -v /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/zb/gen sf/src/main.zig --track-memory --markers 2> /tmp/zb/out.log
grep "track-memory:" /tmp/zb/out.log
```
Record rc + RSS + wall + user (`/usr/bin/time -v`) + the `track-memory: perm=… mod=… scr=… pool=… type_db=… total=…` line. The `pool=` number is the key pool.peak. Verify 40 `.c` emitted. Note: stderr is huge (markers); the redirect-to-file is required.

- [ ] **Step 2.3: Compare A vs B + ledger**

Table: Run A (zig0→zig1) vs Run B (zig1→zig1_5): RSS, heap/pool, wall, user. Note zig0 heap (massif) vs zig1 pool.peak (allocator high-water) are different metrics — report both. Report + ledger + mnemoria (discovery). STOP if either run fails/timeouts (report, do not fix).

---

### Task 3: Example ladder — zig1_clean vs zig1_5_clean (Run C vs Run D)

**Files:**
- Report: `.superpowers/sdd/task-MEMCMP-report.md` (append section)

**Interfaces:**
- Consumes: Task 1 binaries; `examples/z98/` ladder.
- Produces: per-example RSS + pool peak + time for zig1_clean and zig1_5_clean → consistency verdict.

- [ ] **Step 3.1: Per-example measurement harness**

For each ladder example E in {hello, game_of_life, lisp_interpreter_curr, json_parser, rogue_mud}, entry `examples/z98/E/main.zig`:
```bash
mkdir -p /tmp/ladder/z1_clean/E /tmp/ladder/z5_clean/E
# Run C (zig1_clean):
/usr/bin/time -v /tmp/fx_subfolder/zig1_clean --dump-c89 --output-dir /tmp/ladder/z1_clean/E examples/z98/E/main.zig --track-memory --markers 2> /tmp/ladder/z1_clean/E/out.log
grep "track-memory:" /tmp/ladder/z1_clean/E/out.log
# Run D (zig1_5_clean): same with /tmp/zig1_5/zig1_5_clean → /tmp/ladder/z5_clean/E
```
Record rc, RSS, wall, user, and the `track-memory:` line for each. (`json_parser`/`rogue_mud` may have pre-existing GCC/link failures in the emitted C — only the DUMP phase memory is being measured here; record dump rc regardless.)

- [ ] **Step 3.2: Consistency verdict**

Compare Run C vs Run D per example: RSS, perm/mod/scr/pool/type_db peaks, wall. Expect near-identical (same source, same allocator). Flag any divergence >5% as an inconsistency finding (report only — do NOT fix).

- [ ] **Step 3.3: Report + ledger**

Report tables (C vs D per example) + consistency verdict. Ledger + mnemoria (discovery/pattern).

---

### Task 4: Pool sizing recommendation + GATE + report

**Files:**
- Report: `.superpowers/sdd/task-MEMCMP-report.md` (append final section)

**Interfaces:**
- Consumes: Tasks 1-3 measurements.
- Produces: recommended `POOL_SIZE` (= max pool.peak + ≥25% margin), BSS analysis, 16 MB target verdict, wall-clock deltas, consistency verdict consolidated.

- [ ] **Step 4.1: Derive the pool size**

From all measured `pool=` values (Run B self-compile + Runs C/D examples), take `max_pool_peak`. Recommended `POOL_SIZE` = `max_pool_peak` + ≥25% margin (round up to a power of two). Also record `total=` in-use (perm+mod+scr) and type_db peak. State the verdict against the original 16 MB total-arena target (note: in-use `total=` vs 16 MB, and whether `pool` must stay above the module arena's live need).

- [ ] **Step 4.2: BSS analysis**

Report the 256 MiB static BSS (zig1/zig1_5) vs zig0's ~0 BSS: quantify the virtual-address reservation in the 32-bit binaries, the on-disk vs BSS split (`size` text/data/bss from Task 1), and what the pool resize would reclaim. No source change.

- [ ] **Step 4.3: GATE sanity**

4 MD5s unchanged (repo-root CWD, `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 <entry> | md5sum`): gol `eed963e0…`, lisp `c3c58477…`, json `089e4f04…`, mud `a1d0dd55…`. `git status --short` shows only the pre-existing uncommitted files (no new tracked changes).

- [ ] **Step 4.4: Final report + ledger + memory**

Consolidated report: the 4-run comparison tables, A-vs-B (cost to produce zig1), C-vs-D consistency verdict, `POOL_SIZE` recommendation with the exact number + margin math, BSS analysis, 16 MB verdict, wall-clock deltas, any inconsistency findings. Ledger + mnemoria (decision/pattern). No commits (measurement-only plan).
