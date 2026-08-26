# zig0 vs zig1 vs zig1_5 — Memory + Wall-Clock Comparison — Design

**Date:** 2026-08-26
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start

## Goal

Measure and compare peak memory (RSS + allocator/pool peaks) and wall-clock time of the three compilers — **zig0** (C++98 bootstrap), **zig1** (self-hosted reference), **zig1_5** (self-compiled zig1) — at HEAD `cfb2f54a`, to (a) quantify how much memory it takes to *produce zig1* (self-compile), (b) detect any memory/time inconsistency between zig1 and zig1_5, and (c) determine the correct size to replace the 256 MiB measurement pool. **Investigation only — no `sf/src` source changes.**

## Scope Decisions (operator-ruled 2026-08-26)

- **Measure + report only.** The plan produces measurement tables + a pool-size recommendation. Actually resizing `memory_pool_buf` (Task 12 F-RESIZE, deferred from the memory-optimization plan) is a separate future execution plan.
- **Fair RSS comparison:** build a no-ASan zig1 (`zig1_clean`) and use the existing no-ASan `zig1_5_clean`. The ASan reference zig1 is NOT used for RSS (inflated ~4-5×); it is only the self-compile producer.
- **Metrics:** peak RSS (`/usr/bin/time -v`) + allocator/pool peaks (`--track-memory --markers` for zig1/zig1_5, valgrind massif for zig0) + wall/user time.
- **The 256 MiB pool** was set up as a temporary *measurement size* for the (since-fixed) self-compile memory bloat. Its correct size must now be re-derived from freshly measured pool peaks.
- **Self-compile is the anchor measurement** (T5-shape): zig0→zig1 vs zig1→zig1_5. zig1_5 is the *product*, excluded from the self-compile comparison; it is used only for the example-ladder consistency check and pool-peak comparison.
- **Skip** the "does zig1_5 self-compile once more" (T3 determinism / T4 runtime-match) checks — the operator ruled those awkward/unnecessary at this point.

## Background — the established self-compile route (verified working)

- Canonical route `scripts/self_compile/build_zig1_5.sh`: `zig1 --dump-c89 --output-dir /tmp/zig1_5/gen sf/src/main.zig` → **40 `.c`**; `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <repo>/sf/src/include -c *.c` inside `gen/`; link `zig_runtime.c + zig_pal.c + c_exit.c` → `zig1_5_asan` + `zig1_5_clean`.
- Pipeline index `scripts/self_compile/README.md` (T1–T6): T5 memory measurement (4 runs vs 16 MB target, `memory_measure.sh`) was **never implemented** — the pipeline blocked at T2 (1195 gcc errors) and the work diverted into gap-fixing plans. `memory_measure.sh` and the T6 report do not exist.
- Self-compile verification milestones (ledger): **gcc-CLEAN** ("self-compile 12→0 gcc-CLEAN"), **LINK-GREEN** (both binaries link + run crash-free), currently 40 `.c` / 0 errors at HEAD.
- Prior partial measurement (2026-08-25, pre as-tco): `perm=1978K mod=16197K scr=2037K pool=83194K type_db=247K total=20212K` → in-use ≈ 20 MB, pool reserved ≈ 81 MB, RSS ≈ 49 MB (ASan zig1), wall 3.4 s; module arena dominant (16.2 MB in-use).

## Current memory state

- `memory_pool_buf[268435456]` (256 MiB) static BSS, `allocator.zig:184-185`; monotonic bump `pool: Sand`, never reset; `poolPeak()` at `allocator.zig:199`.
- Binary BSS (measured): zig1 bss ≈ 268,469,508 B; zig1_5_clean bss ≈ 268,470,648 B — both 256 MiB static reservation in 32-bit ELF. zig0: malloc-based, ~0 BSS.
- `--track-memory --markers` prints `track-memory: perm=…K mod=…K scr=…K pool=…K type_db=…K total=…K` (main.zig:243-268); `pool` = `alloc_mod.poolPeak()`.
- `DEV_MAX_MEM = RELEASE_MAX_MEM = 16 MiB` (allocator.zig:191-192) but `checkCombinedPeak` gates against `POOL_SIZE` (256 MiB), not `max_mem` — the 16 MB budget is NOT currently enforced.
- zig0 (C++ bootstrap, malloc) self-compile ground truth (MEM2, 2026-08-07): 40,996 KB RSS / 40.1 MB heap (massif) for 35,316 lines; scaling ≈1.1 KB/line at scale.

## Architecture — four measurement runs

1. **Run A — zig0 → zig1:** `build/zig0 --header-priority-include -o OUT/zig1.c sf/src/main.zig` (repo root). Metrics: RSS + wall/user (`/usr/bin/time -v`) + heap (valgrind massif, one run).
2. **Run B — zig1 → zig1_5:** `zig1 --dump-c89 --output-dir OUT/gen sf/src/main.zig --track-memory --markers`. Metrics: RSS + wall/user + `pool=`/arena peaks.
3. **Run C — zig1_clean → examples:** ladder {hello, game_of_life, lisp_interpreter_curr, json_parser, rogue_mud}. Metrics: RSS + pool peak + time per example.
4. **Run D — zig1_5_clean → examples:** same ladder, same metrics.

**Comparisons:** A vs B (cost to produce zig1 — zig0 vs zig1 self-compile); C vs D (zig1↔zig1_5 consistency — expect identical); BSS quantification (256 MiB static vs zig0 ~0); pool sizing = max(pool.peak across B/C/D) + margin (prior operator ruling: peak + ≥25%).

## Components / Build Matrix

| Compiler | Build |
|---|---|
| zig0 | `g++ -std=c++98 -Isrc/include src/bootstrap/bootstrap_all.cpp -o build/zig0` (repo root; also produced by build_release.sh) |
| zig1 (ASan, producer) | `/tmp/fx_subfolder/zig1` via `timeout 900 bash sf/scripts/build_release.sh` (repo root) |
| zig1_clean (no ASan) | same emitted `/tmp/fx_subfolder/*.c` re-`gcc -m32 -O0` WITHOUT `-fsanitize=address` → `/tmp/fx_subfolder/zig1_clean` |
| zig1_5_clean | `/tmp/zig1_5/zig1_5_clean` via `timeout 900 bash scripts/self_compile/build_zig1_5.sh` |

## Error Handling / Testing

- No byte-identity gate (no source changes); 4 MD5 gates must remain unchanged as a sanity check (trivially true — no `sf/src` edits).
- `timeout 120` on every compiler/binary invocation; `timeout 900` on builds; on timeout STOP.
- `--markers` on self-compile floods stderr (≈4.8M lines); redirect to a file and `grep "track-memory:"`.
- `--output-dir` must pre-exist (else rc=1 "cannot open output file").
- Cross-check `--track-memory` pool peak against `/usr/bin/time -v` RSS (they should correlate; pool is the arena high-water, RSS includes binary+libc overhead).
- Massif one-run only for zig0 (it is the slow/heavy tool); RSS+time for the rest.

## Out of Scope

- Resizing `memory_pool_buf` / BSS trim (future F-RESIZE execution plan, fed by this report's recommendation).
- Fixing any memory or correctness defect discovered during measurement (report only).
- T3 determinism / T4 runtime-match pipeline tasks (operator-ruled skipped).
- Full self-compile determinism of the 40 `.c` (established elsewhere).
