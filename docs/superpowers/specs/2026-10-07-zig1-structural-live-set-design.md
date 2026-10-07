# zig1 Structural Live-Set Reduction — Design

> Status: draft (2026-10-07). Deep structural reduction of the large *resident* compiler
> structures. Fixes are in scope (unlike the prior measurement spike).

## Problem

Peak **RSS** is the binding budget (operator ruling). After L3 the `-s0` self-compile is
pool 14,924 K / RSS median ≈17.4–17.6 MB. The prior live-set spike (allocation census + zig0-era
workaround census) found only a small, mostly *provisional* ceiling (~1.0–1.4 MB) because it looked
at allocation-level hygiene, not at the **big live structures**. Those are where the real reduction
is, and they require a deeper analysis: representation, value reuse, one-use retention, and
pointer-vs-inline (with mutation safety) — not "does the language support a smaller packing".

**Interim target:** peak RSS **≤ 16 MB** (the design's long-standing machine budget). This is a
stop-gate, not a promise: **if Task 1 (the string interner) alone reaches it, the plan STOPS** and
Tasks 2–3 are not executed, to avoid disturbing the compiler more than necessary.

## Metric

Peak **RSS** of the self-compile (`/usr/bin/time -v` Maximum RSS), median of ≥3 interleaved runs.
`pool`/`total`/per-arena carve and the static table sizes are context only. Carve ≠ touched RSS
(only resident/touched pages raise RSS). Per-fix RSS delta is recorded (median ≥3).

## Approved reconnaissance (leads; the per-task static analysis confirms)

Resident at `-s0` self-compile, biggest first:

| # | structure | ~RAM | arena | note |
|---|---|---:|---|---|
| 1 | String interner | ~1.5 MB | `perm` (never freed) | 34,020 names; buckets + entries + text |
| 2 | Type registry (`type_db`) | ~1.0 MB | `type_db` (never freed) | `Type[]` + 8 id-caches + per-kind payload arrays |
| 3 | Comptime fold table | ~0.9 MB | `module` (freed at lowering→emission) | 48-byte value per folded constant |
| 4 | AST in-RAM window | ~0.9 MB | `module` | 8 resident disk-blocks (AST itself ~9.5 MB on disk) |

Deferred (not tasks here): AST window/value-pool representation, hash-map layout, one-use
retention — captured in the reconnaissance but held until 1–3 are done and the stop-gate re-judged.

## Analysis lens (each per-task static analysis must answer these)

1. **Integer reuse / interning** — repeated values that could be shared/deduplicated; redundant
   parallel columns holding derivable data.
2. **One-use-and-discard / retention** — data built then read once, or held after its last use.
3. **Representation** — sparse vs dense, narrower widths within observed value ranges, SoA↔AoS,
   shared/interleaved pools, packing only where the language allows it (seed model).
4. **Pointer vs inline, with mutation safety** — where indirection would save bytes, plus the
   aliasing analysis that proves it safe (interior pointers into growable arrays are a known trap).

## Binding constraints

- **Static analysis only, no rewiring.** Do not wire currently-unwired helpers (e.g.
  `astStoreComputeMemory`) or add instrumentation; the analysis reads source and uses existing
  measured counts. No "make the measurement infra better" side-quests.
- **Seed model.** Any changed code must compile with the current seed; new syntax only after a
  fixed point supports it. Current seed v92 (archive md5 `3cacdd44df75c0ce96abfd51af93f928`).
- **Runtime-equivalence oracle** for every fix: corpus classify diff-empty
  (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + runtime goldens gol/lisp/json/mud +
  `verify_stdlib` 266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream) + semantic markers
  byte-identical IN-SESSION. Emitted C may change; the fixed point is re-baselined with the
  operator's ruling, never silently.
- **Do not re-litigate closed levers:** 16-B `AstNode` (I-COMPACT — byte-neutral/net-worse),
  sparse→dense for `coercion`/`enum_value_table`/`comptime_values` (sparse-wins; dense adds
  ~4.7 MB), F-1/I-F1 free-list, M5, S-INTERNER as previously scoped.
- `edit`/`fastedit` only; re-read the region before each edit; edit bottom-to-top.
- No push. Seed rotation only at closeout.

## Task shape

- **Task 0 — Baseline adoption** (no work wasted): reuse the prior plan's frozen baseline
  (`.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-0-report.md`) after confirming
  `sf/src` is unchanged since L3 (`2d713a9a`) — the live-set spike committed docs only.
- **Tasks 1–3 — Investigate/Fix pairs**, biggest-first: **1** string interner, **2** type
  registry, **3** comptime fold table. Each = an **Investigate** task (read-only static analysis →
  a ranked candidate list with byte prize + risk) followed by a **Fix** task (implement the chosen
  candidate, run the battery, measure RSS).
- **Stop-gate after each Fix:** if peak RSS ≤ 16 MB, STOP; do Tasks 2–3 only if it has not been met.
- **Closeout:** re-verify, record RSS, update docs, rotate seed v92→v93.

## Non-goals

- Micro-packing that the language cannot express (packed structs are bitfield-only).
- Rewiring dormant measurement/allocator code.
- The deferred structures (#4 AST, hash-map layout, one-use retention) until the stop-gate is judged.
- Any fix that cannot be proven runtime-equivalent on the battery.
