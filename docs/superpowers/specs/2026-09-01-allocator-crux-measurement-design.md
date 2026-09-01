# zig1 Allocator Crux Measurement → Gated Redesign — Design

**Date:** 2026-09-01
**Status:** DRAFT (awaiting operator approval)
**Branch:** zig1_start
**Baseline:** HEAD `8e5cff7d` (memory-refactor execution GATE); reference zig1 `/tmp/fx_subfolder/zig1`, self-compiled `/tmp/zig1_5/zig1_5_clean`

## Goal

Characterize exactly where `pool.peak` (25,742 K) goes — per-arena, live vs churn — so the arena/bump/alloc can be redesigned to reduce memory usage **toward live** (~5,755 K) with wise usage, and to understand the cruxes that must be thought about. Redesign is **gated on the measurement findings** (operator-ruled).

## Scope Decisions (operator-ruled 2026-09-01)

- **Measure first, redesign gated on findings** (m1135): the plan's first stage is read-only measurement (I-tasks) ending in a crux map + redesign options presented to the operator; the redesign F-tasks are added via amendment after the operator picks the direction on data.
- **Reduce toward live, no fixed target** (m1136): success is reducing `pool.peak` toward the live working set, reported as a final number; the 16,384 K figure is NOT a gate.
- This is a **new plan** for redesign/remeasure of arena usage, bump, and alloc — not a continuation of the memory-refactor execution plan (whose S-series is complete at `8e5cff7d`).
- Read-only discipline for all I-tasks: no `sf/src` edits; measurement via existing markers + instrumented `/tmp` builds (the I-4B pattern). No commits expected from I-tasks.

## Background — measured facts (2026-08-26 → 2026-09-01)

- **The pool is a single monotonic bump.** `pool: Sand` over the 256 MiB static `memory_pool_buf` (allocator.zig:189-190) is **never reset** (`pool.peak` = high-water mark of the cumulative bump).
- **Six growable arenas carve segments from that one bump:** `perm`, `module`, `scratch`, `lir_read` (allocator.zig:209-212), `type_db` (main.zig:161), `import_scratch` (M4-reused).
- **Two-level growth** (the crux structure):
  1. **Segment level** (`growableSandGrow` allocator.zig:108-133): on demand, only when `sandAlloc` can't fit the current segment (`new_pos > sand.end` :49). Chains a NEW segment, **no copy**; doubles (`last.size * 2`, capped 2 MiB by M3) with **exact-fit final** (:121); old segments are retained forever (never returned to the bump). `sandReset` (:78-87) rewinds to `first` and **reuses** the chain (`gs.last.next` :109-116) — never frees. So an arena's retained chain ≈ geometric sum ≈ 1-2× its peak live, and the only waste at this level is the **headroom** in the last segment.
  2. **Array level** (each `ensureCapacity` in ast.zig / resolved_type_table.zig / growable_array.zig / etc.): allocates a doubled buffer, copies, abandons the old buffer → the old buffer is **dead space** in the arena segment, never reclaimed. `sandTryReallocInPlace` (:161-174) avoids the copy+dead-buffer **only** when the array is the tail of its segment — and it is the segment **headroom** that makes that possible (so headroom is not pure waste; it buys in-place array growth).
- **`pool.peak` = Σ every segment ever allocated across all arenas** (cumulative; never returns bytes). Current `pool=25,742K` vs live `total=5,755K` (perm 1,661 + mod 2,047 + scr 2,047 at final checkpoint) → the ~20,000 K gap is churn: segment headroom + dead array buffers + reset-retained segments.
- **`arena grew` markers already exist** (allocator.zig:135-148): `arena <name>: grew <old> -> <new>`, fired only on a NEW segment allocation (not reuse) → summing per arena reconstructs each arena's segment chain for free.
- **Reclaim correctness** (operator insight m1127): the "what to release" question has a crisp answer for one class — **a reset arena's whole chain is provably dead** (scratch resets every phase; `sandReset` marks its data dead). That is a well-defined release signal; the open design is how the bump expresses it (e.g. a segment free-list), which the measurement quantifies the prize for.
- **Current gates** (unchanged, keep-or-re-baseline): gol `302df36b`, lisp `3591bad9`, json `76056b97`, mud `4591fef0` (4 MD5) + golden 9/9 + self-compile 41 `.c` / 0 err / 0 PANIC + ref 0-warning.

## Architecture — 3 read-only measurement tasks, then a gated redesign

- **I-MEAS-1 — Per-arena chain + live breakdown.** Instrument an `/tmp` build (read-only; do not touch `sf/src`) to log, at every `runCompiler` phase boundary, each arena's live (`view.pos`) and chain (Σ its segment sizes), plus `pool.peak`. Cross-check the chain against the existing `arena grew` marker sums. Deliverable: the exact 25,742 K map — which arena dominates, and how much is live vs headroom vs retained segments.
- **I-MEAS-2 — Array-level dead-buffer churn.** Instrument `sandTryReallocInPlace` outcomes (success / fail-and-copy) and the bytes lost to failed-in-place copies across all sites + each `ensureCapacity` doubling path. Deliverable: churn split into (a) segment headroom, (b) dead array buffers, (c) reset-retained segments — the three reclaimable classes sized.
- **I-MEAS-3 — Synthesis + crux map.** Combine 1+2 into a crux map (top levers by bytes, with expected pool drop + risk + Z98-expressibility for each) and a redesign recommendation. **STOP-present to the operator.**

## After measurement (gated, by amendment)

The operator picks the redesign direction from the crux map; the plan is amended with the F-task(s). Candidate directions (NOT prejudged — the measurement decides): a segment free-list keyed on "reset = release" for `scratch` (and any other reset arena), growth-policy tuning (factor/cap/exact-fit), per-arena pools, or a compacting/reset-aware bump. Each F-task carries the standard gate battery.

## Success criterion

Reduce `pool.peak` toward the live working set; report the final number (no fixed 16 MiB gate). Redesign F-tasks keep: 4 MD5 gates keep-or-re-baseline with golden 9/9 runtime evidence; self-compile 41 `.c` / 0 err / 0 PANIC; reference build 0-warning (1 pre-authorized fwrite carve-out); Z98 dialect (no packed/bitfield/anytype/@Type); `edit`/`fastedit` only.

## Constraints

- I-tasks are read-only: no `sf/src` edits, no commits; measurement via existing `arena grew` markers + instrumented `/tmp` builds (the I-4B pattern — checkpoint loggers in generated `main.c`/`allocator.c`, never source).
- `--markers` self-compile on the reference zig1 is the measurement workload; `timeout 120` on all invocations, `timeout 900` on builds.
- Ledger: append one line per task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent memrefactor-session --type <discovery|decision|problem|pattern>`.
- Report file: `.superpowers/sdd/task-ALLOC-report.md` (gitignored; WARNING: `task-1-report.md` is TRACKED — never reuse).
- Pre-existing dirty files never staged: `docs/superpowers/plans/2026-08-26-assoc-misparse-pendingscope-plan.md`, `mnemoria/*`, untracked `build/`.
