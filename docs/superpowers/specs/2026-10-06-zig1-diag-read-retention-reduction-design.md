# zig1 `diag_read` Retention Reduction — Design

> Status: draft (2026-10-06). Fix plan paired. Measurement authority: the read-only spike
> `docs/superpowers/plans/2026-10-06-zig1-nonast-memory-plan.md` (reports under
> `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/`).

## Problem

Self-compile `-s0` `pool = 19,274 K` vs the 16,384 K (`-mm16`) accountability → gap **2,890 K**.
The largest previously-untargeted consumer is the `diag_read` fault arena:
carve **4,545 K** = live **2,913 K** (file text 2,711 K + per-line `u32` index 202 K + headers 0.7 K)
+ **~1,632 K segment-tail over-allocation**. 43 of 47 parsed modules are faulted once and held from
semantic analysis through the pool peak; the arena is reset only at end-of-run
(`sourceManagerResetFaults`, `sf/src/source_manager.zig:194-202`), then the process exits.

## Root cause of the tail

`sourceManagerFaultIn` (`sf/src/source_manager.zig:148-192`) reads the whole file first (`:161`) —
which exact-fits a fresh segment when it exceeds `2×last` — then allocates a 16-byte header (`:163`)
and grows the `U32ArrayList` index (`:174-178`). After a ~600 K text segment, that tiny request hits
the growth policy `new = max(2×last, request)` capped at 1 MiB (`sf/src/allocator.zig:118-157`):
it carves a **1 MiB segment for a ~37 K index**. That ~1 MB/file tail is the prize, and it is *not*
removed by exact-fitting (the index size is unknown until after the scan).

## Goal

Lower the `-s0` pool toward/below 16,384 K by bounding the `diag_read` footprint, with **no runtime
behavior change and no emitted-C change** beyond operator-ruled recording.

## Levers

### L3 — reset `diag_read` per module (primary)

`sourceManagerResetFaults` already realizes the target behavior (returns segments 2…N to
`seg_free_head`, clears `loaded` on transient files). Today its only caller is end-of-run
`diagnosticCollectorPrintAll`; add a per-module call after `az_mod.runAllAnalyzers`
(`sf/src/main.zig:775`) inside `phase_StaticAnalyzers` (`sf/src/main.zig:739-778`), using the context
handle `ctx.source_man` (`sf/src/main.zig:103`). Retention then never exceeds one module's file.

- Bound: ≤ 4,545 K; capacity-aware realistic ≈ 2,900–2,950 K (one file's *capacity*, worst case
  ~1.6 MiB due to the tail above) — already ≈ the 2,890 K gap.
- Precondition/assumption: every SourceManager file is added **transient**
  (`sourceManagerAddFileTransient`, `sf/src/import_resolver.zig:16`; the non-transient
  `sourceManagerAddFile` is test-only). The fix must note/assert this.

### L6 — growth **rule** to bound the small-request tail (secondary)

Not exact-fit (fragile: re-tunes every source change). Choose a stable rule and select it **by
measurement** in the design/implement task from:

- **R-a** multiplier 2.0 → 1.6/1.7, global (`sf/src/allocator.zig:127-131`). Precedent (M3/F-2);
  from a 600 K base 1.6× ≈ 950 K — alone insufficient for this tail.
- **R-b** lower the 1 MiB cap (→512 K/256 K). Bounds every tail; multiplies segment count and
  perturbs `module`/`scratch` reuse.
- **R-c** small-request branch: if `request ≤ last/4`, size the new segment to
  `request × 1.6` (+ minimum) instead of doubling from `last`; otherwise grow as today. Targeted at
  the header/index-after-file case; leaves incremental growth (module/scratch) untouched.
- **R-d** bounded 1.6× bucket ladder. Stable, caps per-segment waste at 60 %.
- **R-e** move the line index out of the fault arena (separate arena) or shrink it (L1).

R-c (targeted) is the primary candidate; R-a/R-b are global fallbacks; R-d if R-c's branch is not
clean. The chosen rule must be justified by measured per-arena carve + pool, byte-identical battery.

### L1 — line-index representation `u32` → `u16`/delta (optional)

≤ 103 K live, ~0 pool-peak benefit; does not remove the growth tail. **Defer** unless requested.

## Success criteria

1. `repro/mi_matrix` corpus classify byte-identical; runtime goldens exact; `verify_stdlib` 266/0;
   examples 24/24; `--markers` stderr identical; dump-MD5 recorded (no unexplained delta).
2. `-s0` `pool` falls; target as close to / below 16,384 K as measurably feasible; RSS reported.

## Risks / constraints

- L3 reset timing: any analysis-time consumer retaining a prior module's `content` slice across a
  reset would break; the corpus/goldens gate must catch it. Print-time re-fault is already exercised
  (`diagnostics.zig:721` → `source_manager.zig:219/243`).
- L6 global-rule blast radius: `growableSandGrow` is shared by perm/module/scratch/emission; measure
  **per-arena**, do not assume.
- Data-dependent fault set: the prize shifts with source; re-measure after any source change.
- Seed model; runtime equivalence is the oracle; `edit`/`fastedit` only; compression forbidden during
  build; no push; `timeout 120` per step (aggregates 600).

## Non-goals

- L2/L4/L5 (disconfirmed NO-GO by the spike); the exhausted allocator free-list levers (F-1/I-F1),
  M5 Token packing, I-COMPACT, S-INTERNER; the C89 back-end toolchain; the deferred logic-dedup
  Tasks 11–31 (not memory levers).
