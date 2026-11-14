# Self-Compilation Correctness (Determinism + Memory) Design

> **Date:** 2026-08-20. **Status:** design (pre-implementation). Branch `zig1_start`.

## Goal

Verify that zig1 (self-hosted, zig0-bootstrapped) self-compiles correctly and **deterministically** into a second-generation compiler `zig1_5`, that both generations emit matching C and runtime-identical programs for all 21 examples, and measure compiler memory (in-use arena + process RSS) against the 16 MB target. This is a **read-only verification plan**: it produces scripts + a findings report; it makes **zero `sf/src` source changes**, and STOPs on any finding (no auto-fix).

## Background

### Build chain

```
zig0 (C++, src/bootstrap/bootstrap_all.cpp)
  --header-priority-include -o zig1.c sf/src/main.zig
  → gcc -m32 -std=c89 -O0 -fsanitize=address + sf/src/include/zig_pal.c
  → /tmp/fx_subfolder/zig1
zig1 (self-hosted)
  --dump-c89 --output-dir <dir> sf/src/main.zig   (40 .c files)
  → gcc -m32 ... → zig1_5
```

`zig0` emits a **legacy single-file** format; `zig1`/`zig1_5` emit the **40-file multi-module** format. These two are byte-level incompatible — determinism is therefore compared **only between zig1 and zig1_5** (both multi-module), never against zig0 output.

### Memory scheme (in `sf/src/allocator.zig`)

- A 256 MB **static** `memory_pool_buf` backs a monotonic bump `pool`. Three growable tier arenas — `permanent`, `module`, `scratch` — carve segments (4→8→16→32 KB…) out of it.
- `Sand.peak` tracks actual `pos` (bytes **in use**); `pool.peak` tracks total bytes **carved/reserved** (keeps freed segments for reuse). The "arena as a whole vs in-use" distinction the operator flagged is exactly `pool.peak` (reserved) vs `perm/mod/scr.peak` (in-use).
- `--track-memory` prints `perm=`/`mod=`/`scr=`/`pool=`/`type_db=`/`total=` in KB. **Gotcha:** the report is emitted via `pal.markerWrite`, so it is only visible when `--markers` is also passed.
- `RELEASE_MAX_MEM = 16 * 1024 * 1024` (16 MB) is the target budget. The `--max-mem` flag is **currently unwired** (`TrackingAllocator` is "KEPT (unwired)"); the only enforced limit today is the 256 MB pool. This is a finding to record, not fix.

### Existing tooling

- `sf/scripts/differential_test.sh` — normalizes temp names/hashes/comments for C comparison (zig0 vs zig1; reusable normalization logic).
- `sf/scripts/memory_profile.sh` — `/usr/bin/time -v` peak RSS.
- `docs/zig1_memory_profile.md` — Phase 1: zig0 compiling `main.zig` = 4.51 MB internal / 5.73 MB heap peak (the 16 MB budget reference).

## Determinism definition (tiered)

For each target (self-source `sf/src/main.zig` + each of 21 examples), compare `zig1 --dump-c89` output (A) against `zig1_5_clean --dump-c89` output (B):

1. **Byte tier** — `md5sum` each `.c` (or `diff -r`). Identical = deterministic at byte level.
2. **Normalized tier** — if bytes differ, normalize (temp names `zT_N`, mangled hashes `z[FT]_<8hex>_`, block labels `z_bb_N`, comments, `#include` lines) and re-diff. This isolates *real* codegen differences from temp/hash/comment noise.
3. **Runtime tier** — compile+run each program from A and B and require identical stdout + exit code.

Determinism verdict is recorded per target and per tier. **Byte-tier non-determinism on `sf/src/main.zig` itself is a major finding** (STOP).

## Memory measurement

Four compiler runs, each captured two ways:

| # | Compiler | Input | In-use (internal) | RSS (external) |
|---|---|---|---|---|
| 1 | zig0 | `sf/src/main.zig` | n/a (C++, no tracker) | `/usr/bin/time -v` peak RSS |
| 2 | zig1 | `sf/src/main.zig` | `--markers --track-memory` | `/usr/bin/time -v` |
| 3 | zig1 | all 21 examples | `--markers --track-memory` | `/usr/bin/time -v` |
| 4 | zig1_5 (asan + clean) | all 21 examples | `--markers --track-memory` | `/usr/bin/time -v` |

**Primary metric = in-use total** (`perm+mod+scr`, plus `type_db`), compared against the 16 MB target. `pool` is reported separately as the reserved/carved number. RSS is a secondary sanity number (note: zig1/zig1_5_asan are ASAN-inflated; the internal arena numbers are ASAN-independent because the pool is a static buffer). STOP if in-use > 16 MB.

## Scope

- **Targets:** `sf/src/main.zig` + all 21 `examples/z98/*` dirs (`days_in_month`, `fibonacci`, `func_ptr_return`, `game_of_life`, `heapsort`, `hello`, `json_parser`, `json_parser_workaround`, `lisp_interpreter`, `lisp_interpreter_adv`, `lisp_interpreter_curr`, `lzw`, `mandelbrot`, `mud_server`, `prime`, `quicksort`, `rogue_mud`, `sort_strings`, `tco_defer`, `tco_factorial`, `tco_return_try`).
- **Runtime comparison** covers the 19 non-interactive examples; `mud_server` and `rogue_mud` are C-diff + memory only (interactive; no runtime stdin scripting).
- **zig1_5 is built both ways** (`-fsanitize=address`, matching zig1, and clean) and both reported.

## Constraints

- Read-only: **no `sf/src` edits**. Scripts live under `scripts/` (or `sf/scripts/`); findings in a report doc. STOP on any finding — do not auto-fix non-determinism or memory overshoot.
- Determinism compares zig1 vs zig1_5 only — never zig0 (legacy incompatible format).
- `--track-memory` requires `--markers`.
- std modules must be installed per binary: `mkdir -p <exe_dir>/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig <exe_dir>/lib/` (search path: importer dir → `-I`/`--lib-dir` → `<exe_dir>/lib`).
- Never touch/ls `sf/build/out_release/` (WEDGED); all runs `timeout 120`.
- lisp MD5 measured from repo root; json_parser from its own dir; matrix interactive examples (game_of_life/mud_server/rogue_mud) are timeout-gated rc=124 with correct output = PASS.
- Branch `zig1_start` (continue; widthbits fix at HEAD `6dd11b24` is the self-compile prerequisite).

## Success criteria

1. `zig1_5` (asan + clean) builds from zig1's C output and runs.
2. Determinism verdict recorded per target per tier (byte / normalized / runtime), with `sf/src/main.zig` at byte tier as the headline result.
3. Runtime behavior of all 19 non-interactive examples is identical across zig1 and zig1_5.
4. Memory table for all 4 runs with in-use vs 16 MB margin; `pool` (reserved) reported separately.
5. Findings report committed; any non-determinism / memory overshoot surfaced to the operator as a STOP, not silently fixed.
