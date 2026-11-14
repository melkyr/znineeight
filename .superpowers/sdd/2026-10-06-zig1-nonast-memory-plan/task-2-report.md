# Task 2 — Attribute `import_scratch` + `source` + `scratch`/`module` carve (READ-ONLY) report

Branch: `zig1_improvements` (NO push). Spike: no `sf/src` edits, no seed rotation, no dump-MD5
re-baseline. All probes were throwaway gdb command files / Python simulators under `/tmp` (nothing in
the repo). CWD for the self-compile: `/workspace/znineeight`, source arg RELATIVE `sf/src/main.zig`.

Reference compiler (not rebuilt): `/tmp/nonast_seed/zig1_5_clean`, md5
`d40e875a7ba3aa55d441af56006f6023`.

Method (reused/refined from Task 1): the `arena <name>: grew <old> -> <new>` markers
(`allocator.zig:155,193`) fire **only on a genuine new carve** (`arenaGrew` is not called on a
`seg_free_head` reuse, `allocator.zig:132-144`). To recover the *live* side I ran the compiler under
`gdb` with throwaway breakpoints on `growableSandGrow` (log `view.start/pos/end/req` on every growth
attempt) and `sandReset` (log per-arena `pos/end` before reset), then replayed the event stream in a
`/tmp` simulator that maintains each arena's owned-segment set across resets. The simulator is
validated by `diag_read`: it reproduces Task 1 exactly (live **2,983,362 B**, capacity **4,658,494 B**,
waste **1,675,132 B**). No `sf/src` file was touched.

## The two calibration facts (why the carve and `mod=`/`scr=` are different quantities)

1. **Carve** = Σ of the `new` value over an arena's `arenaGrew` lines = capacity that arena *first*
   pulled from the pool. Because `sandReset` returns segments 2…N to the shared `seg_free_head`
   (`allocator.zig:78-97`) and `growableSandGrow` pops a best-fit reuse from it without logging
   (`allocator.zig:132-144,159-191`), a segment can be carved once and then owned/re-used by a
   different arena. So carve is a *first-allocation attribution*, not a live set.
2. **`mod=` / `scr=`** in the `track-memory` line (`main.zig:408-435`) are `Sand.peak`
   (`main.zig:410-411`; `Sand.peak` @ `allocator.zig:5`). `peak` is only ever set to the active
   segment's `pos` (`allocator.zig:52,227`); on every segment switch the new segment's `pos` is reset
   to 0 (`allocator.zig:124,142,154`) while `peak` is carried forward. So `peak` is the **maximum
   offset reached inside any one segment** — it does not sum segments, and it is not the arena's
   footprint. It can be < 1 MiB (all segments ≤ the 1 MiB doubling cap, `allocator.zig:128-130`) or
   > 1 MiB (an oversized request gets an exact-fit segment, `allocator.zig:131`). Example: at `-s1`
   `module` allocates an 8 MiB exact-fit segment (`arena module: grew 1048576 -> 8388608`) and
   `mod=8192K` is exactly that one segment's high-water; at `-s0` no module request exceeds 1 MiB so
   `mod=1020K`.

Consequence: `mod=`/`scr=` **cannot** be reconciled against the carve as "live vs over-allocation".
The carve is closer to the arena's pool footprint; the meaningful live-vs-quantization split has to be
reconstructed from the grow/reset events (below).

## Step 1 — `import_scratch` and `source` decomposition

### `import_scratch` (Task 0 carve 1,353 K)

- **Object / init.** Local `GrowableSand` in `moduleRegistryResolveImports`
  (`import_resolver.zig:59-61`), first segment **256 B**, pool-backed (`allocator.zig:262`). One per
  call; the function is called twice (`main.zig:480` root, `main.zig:495` std_fmt auto-import).
- **What it holds.** Passed to `parserSetImportScratch` (`import_resolver.zig:22`) and used at
  `parser.zig:780-782`: on **every `@import(...)` expression** `sandReset(is)` then
  `moduleRegistryResolveImport(reg, path_id, current_module_id, is)`. For a *newly resolved* path that
  function does `pal_mod.readFile(resolved_path_s, scratch)` (`module_registry.zig:384`) purely to
  compute an FNV-1a content hash for the content-dedup guard (`module_registry.zig:394-404`). So
  `import_scratch` transiently holds **the entire text of the resolved file**, and its growth requests
  are exactly the resolved file sizes.
- **Measured carve.** `-s0`: six `arenaGrew` lines, all `256 -> <size>` (probe confirms every growth
  attempt starts from the reset 256 B first segment):
  `12,050 / 45,121 / 98,582 / 531,960 / 596,656 / 100,786` = **1,385,155 B = 1,353 K**.
  `-s1`: five lines (no `100,786`) = **1,284,369 B = 1,254 K**.
- **Lifetime / live split.** Reset before each `@import` (`parser.zig:781`), so the live high-water is
  **one file at a time**: simulator reports **596,672 B = 582.7 K** (the largest resolved file,
  `lower.zig` = 596,656 B, + 16 B bookkeeping). Capacity at that moment was 596,912 B → waste **240 B**:
  because each new segment is **exact-fit** to the request (`allocator.zig:131`), there is essentially
  **zero per-segment tail quantization**. The 1,353 K carve is a *cumulative sum of transient
  peaks* — six separate imports whose segments were newly carved because no free segment of that size
  was on `seg_free_head` at the time. Most of that capacity is later returned to the free list and
  re-used (the module arena below re-uses exactly this ladder), so only ~583 K is ever live at once.
  **Verdict: real bytes at the instant of each read, but not simultaneously live; carve overstates
  live by ~2.3× and the excess is transient (not tail waste).**

### `source` (the `src_arena` inside `moduleRegistryResolveImports`)

- **Object / init.** Local `GrowableSand` (`import_resolver.zig:63-65`), first segment **4096 B**,
  pool-backed. N.B. this is **not** the `SourceManager.fault` arena from Task 1 —
  `source_manager.zig:158` initialises the *`diag_read`* fault-in arena. The name collision is the
  most likely source of the plan's confusion.
- **What it holds.** Reset per module (`import_resolver.zig:75`) then
  `pal_mod.readFile(path_s, &src_arena.view)` (`import_resolver.zig:81`) reads the **whole source of
  the module currently being parsed**; `content` is passed to the parser. Reset before the next module,
  so live high-water = the largest module source.
- **Measured carve (C3 reconciliation).**
  - `-s0`: **0** — there are **39 growth attempts** (`GROW name=source`) but **zero `arenaGrew`
    lines**: every read was served by `popFreeBestFit` from `seg_free_head` (reuse, no log). The probe
    shows the historical `peak` climbing `100,578 → 134,978 → 425,201 → 596,656` while all calls
    report the 4096 B first segment — i.e. each read swapped in a recycled segment and the next
    `sandReset` put it back.
  - `-s1`: **1,129 K** = three `arenaGrew` lines `4096 -> 134,978`, `4096 -> 425,201`,
    `4096 -> 596,656` (sum **1,156,835 B**). At `-s1` the free list no longer held those three sizes,
    so they had to be carved fresh.
- **Live split.** Identical at both levels: simulator reports max live **596,656 B = 582.7 K**
  (exactly `lower.zig`), capacity 600,752 B (the big segment + the 4096 first segment), waste 4,096 B.
- **Reconciliation of C3 (explicit).** The plan's Task 2 expected `source = 583 K`; that number is
  `source`'s **live high-water** (596,656 B ÷ 1024 = 582.7 K), *not* a carve. The carve metric
  (`Σ new` over `arenaGrew`) is **0 at `-s0`** because the reads were satisfied by recycled segments,
  and **1,129 K at `-s1`** because the same three reads each needed a fresh exact-fit segment. Both
  are correct for what they measure; do **not** hunt a `-s0` `source` carve of 583 K. `source` never
  "disappears" at `-s0` — it still holds up to 583 K live per module; it just never *carves*.

## Step 2 — `module` and `scratch` carve vs live/quantization

Per-arena numbers from the `arenaGrew` markers (carve) and the grow/reset simulator (live = Σ used
prefixes of all owned segments at the arena's high-water; capacity = Σ owned segment capacities
then; waste = capacity − live), all bytes:

| arena | level | carve (Σ new) | max live (Σ used) | capacity at max live | waste (tail) | reported peak |
|---|---|---:|---:|---:|---:|---:|
| **module** | `-s0` | 5,382,144 (5,256 K) | **5,548,760 (5,419 K)** | 6,658,559 (6,502 K) | **1,109,799 (1,084 K, 16.7%)** | `mod=1020K` |
| **module** | `-s1` | 25,174,016 (24,584 K) | **22,194,904 (21,674 K)** | 26,450,431 (25,830 K) | **4,255,527 (4,155 K, 16.1%)** | `mod=8192K` |
| **scratch** | `-s0` | 4,679,906 (4,570 K) | **3,478,204 (3,397 K)** | 4,509,696 (4,404 K) | **1,031,492 (1,007 K, 22.9%)** | `scr=1020K` |
| **scratch** | `-s1` | 4,679,906 (4,570 K) | **3,478,204 (3,397 K)** | 4,509,696 (4,404 K) | **1,031,492 (1,007 K, 22.9%)** | `scr=1020K` |

Cross-check / validation (not in scope but proves the method): `diag_read` simulator gives live
2,983,362 B, capacity 4,658,494 B, waste 1,675,132 B — bit-identical to Task 1.

### `module`

- **What it holds.** The pool-backed `mod_gs` tier (`allocator.zig:251,273`), handed to consumers as
  `ctx.alloc.module`. It owns the AST store (`astStoreInit(&compiler_alloc.module)`, `main.zig:203`),
  the resolved-type table (`main.zig:280`), coercion table, dep graph, and dozens of analysis hash
  maps (`main.zig:296-315,351-356`) and async analysis (`main.zig:782`). It is reset exactly once, at
  the lowering→emission boundary (`main.zig:401`), so everything it owns is live through semantic
  analysis and LIR lowering. At `-s0` the AST node payloads are spilled to disk, so the module
  footprint is ~5.4 M; at `-s1` the AST is RAM-resident and the footprint jumps to ~22.2 M
  (carve +19.8 M), matching Task 0's `mod 1020 K → 8192 K` jump.
- **Carve vs live vs `mod=`.** At `-s0` `module` performs **11 growth events / 1 reset**, ending with
  12 owned segments. Because `arenaGrew` fires only 7 times (sizes
  `8,192 / 393,216 / 786,432 / 1 MiB ×4` = 5,382,144 B), **five of the 12 owned segments were reused
  from `seg_free_head`** — and they are exactly the file-sized segments `import_scratch`/`source`
  carved and released: `4,096 + 45,121 + 98,582 + 531,960 + 596,656 = 1,276,415 B`. That is why
  max live (5,419 K) slightly exceeds `module`'s own carve (5,256 K).
- **Segment-quantization vs live.** The per-segment `(capacity, used, tail)` at `-s0` is:

  | cap | used | tail |
  |---:|---:|---:|
  | 4,096 | 1,984 | 2,112 |
  | 8,192 | 8,192 | 0 |
  | 45,121 | 33,312 | 11,809 |
  | 98,582 | 86,336 | 12,246 |
  | 531,960 | 471,808 | 60,152 |
  | 596,656 | 573,440 | 23,216 |
  | 393,216 | 388,912 | 4,304 |
  | 786,432 | 777,344 | 9,088 |
  | 1,048,576 | 614,400 | 434,176 |
  | 1,048,576 | 1,045,424 | 3,152 |
  | 1,048,576 | 947,648 | 100,928 |
  | 1,048,576 | 599,960 | 448,616 |
  | **Σ** | **5,548,760** | **1,109,799** |

  Note `module`'s own carve (5,256 K) sits *below* its live high-water (5,419 K) only because of the
  1,276 K of reused segments above; the pure capacity overhead is the **1,084 K tail waste
  (16.7% of owned capacity)**, driven by the four 1 MiB capped segments (two of them abandon
  434 K / 449 K tails). The growth policy is `new = max(2*last, request)` capped at 1 MiB
  (`allocator.zig:127-131`) with best-fit `seg_free_head` reuse (`allocator.zig:132-144,159-191`).
- **`mod=` is neither carve nor live.** At `-s0`, `mod=1020K` is the high-water of one 1 MiB segment
  (the other eleven segments' bytes are invisible to `peak`). At `-s1`, `mod=8192K` is the high-water
  of the single 8 MiB exact-fit segment (`allocator.zig:131`) and likewise ignores the other 13
  segments. `module.peak` is therefore not usable as a live-memory figure.

### `scratch`

- **What it holds.** The pool-backed `scr_gs` tier (`allocator.zig:252,274`), handed out as
  `ctx.alloc.scratch`: per-phase temporaries. It is reset at every phase start
  (`main.zig:458,518,549,558,675,696,741,798,1015`, …), once per module during analysis
  (`main.zig:747`), and even per function inside `runAllAnalyzers` (`analyzer.zig:897,901`).
- **Carve vs live vs `scr=`.** The simulator sees **~4,500 growth attempts** but only **13 genuine
  carves** (Σ 4,679,906 B) at both `-s0` and `-s1`; the rest are `seg_free_head` re-populations
  (probe shows the same segment `start` recycled hundreds of times). Max live is **3,478,204 B
  (3,397 K)** on **4,509,696 B of simultaneously-owned capacity**, i.e. **1,007 K tail waste (22.9%)**,
  and `scratch` carved **~170 K more than it ever held at once** (segments handed to `module`/others).
  The 4,570 K carve is a *high-water capacity* accumulated across phases and reset cycles, not a
  simultaneous live set.
- **`scr=`** (`scr=1020K`, identical at `-s0`/`-s1`) is only the largest single segment high-water
  (≤1 MiB); it understates scratch's multi-segment high-water (~3.4 M live) by ~3.3×.

### Note on `track-memory total=`

`total = perm_kb + mod_kb + scr_kb` (`main.zig:414`), i.e. the sum of three **single-segment peaks**
(3,022 K at `-s0`), not a footprint; it must not be read as the live total.

## Concerns

1. **`mod=`/`scr=` are not footprints.** They are `Sand.peak`, i.e. per-segment high-water, and can
   be several× below the arena's live bytes (module `-s0`: `mod=1020K` vs 5,419 K live; scratch:
   `scr=1020K` vs 3,397 K live). Any plan text that treats them as live must be corrected; only the
   `arenaGrew` carve (footprint) or the grow/reset reconstruction (live) are meaningful.
2. **Carve ≠ live either.** Reuse via `seg_free_head` means a carve can be attributed to one arena but
   later owned by another (module re-uses 1,276 K of `import_scratch`/`source` segments). Comparing
   carve to a live target over/under-counts by 0.2–1.3 M depending on the pair.
3. **`source`@`-s0` is 0 by reuse, not absence.** The plan's 583 K = `source`'s live high-water;
   `source` holds up to that per module at `-s0`, it just satisfies it from recycled capacity so
   `arenaGrew` never fires. At `-s1` the same reads carve 1,129 K of fresh exact-fit segments. The
   plan's expected `-s0` carve should be recorded as 0.
4. **Simulator caveat.** `max live` is reconstructed as Σ used prefixes of owned segments at the
   high-water moment; it is exact while an arena's final segment is finalized by a later `sandReset`.
   `module` is finalized by `main.zig:401`; `scratch` by its many resets. Arenas with no trailing
   reset (e.g. `perm`) are undercounted by their last segment, so `perm`/`type_db` are shown only as
   context. The `diag_read` bit-exact match is the method's validation.
5. `import_scratch`/`source`'s large segments are *exact-fit* (`allocator.zig:131`), so their
   quantization is ~0; the overstatement of those arenas is **temporal** (summing transient peaks),
   whereas `module`/`scratch`/`diag_read` overstatement is a mix of temporal reuse and genuine
   segment-tail waste (16–37%). Optimisation levers differ: eliminate the content-hash whole-file
   read / fault only needed ranges for `import_scratch`/`source`; right-size or stream requests for
   `module`/`diag_read` tails.
6. Throwaway artifacts only under `/tmp` (`/tmp/t2_probe*.gdb`, `/tmp/t2_sim*.py`, `/tmp/t2_gdb3_s{0,1}.txt`);
   no `sf/src` edit, no seed rotation, no dump-MD5 re-baseline.

## Commands used (evidence)

```
timeout 120 /tmp/nonast_seed/zig1_5_clean -s0 --markers --track-memory -o /tmp/nonast_t2_s0 sf/src/main.zig 2>/tmp/t2_s0.txt
timeout 120 /tmp/nonast_seed/zig1_5_clean -s1 --markers --track-memory -o /tmp/nonast_t2_s1 sf/src/main.zig 2>/tmp/t2_s1.txt
# throwaway gdb probes (set disable-randomization off; 32-bit PIE; args at ebp+8/12/16 after prologue):
#   break zF_130612FB_growableSandGrow  -> GROW name= start= pos= end= req=
#   break zF_F1B3F8C2_sandReset         -> RESET name= pos= end=
# /tmp/t2_sim2.py replays GROW/RESET -> per-arena max-live/capacity/waste (diag_read == Task 1)
```

## Step 3 — Commit

Report committed with `git add -f` and message
`docs: non-AST memory plan — Task 2 import_scratch/source attribution` (only this report;
`.superpowers/sdd/...` is gitignored). No source files staged.
