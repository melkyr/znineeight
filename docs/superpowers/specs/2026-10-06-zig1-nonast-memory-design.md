# zig1 Self-Compile Non-AST Memory — Design

> Status: draft (2026-10-06). Measurement spike; no compiler fixes are committed by the paired plan.

## Problem

Self-compile `-s0` `pool.peak` ≈ 19.3–19.5 MB / RSS ≈ 20 MB against the 16,384K (`-mm16`)
accountability. Prior memory plans (S-series, F-series, M-series, I-F1) exhausted the
AST/LIR/module/scratch allocator levers; the residual ~9–10 MiB gap was studied and closed. The
logic-dedup plan (Tasks 0–10) returned ~−1.5 MB. The remaining dominant consumers are not
duplication.

## New evidence (2026-10-06 measurement)

Per-arena `arena <name>: grew` attribution of the `-s0` pool (self-compile `sf/src/main.zig`, seed v91
`0b8c3e4ac0b1fc49c0bdf8caf9d39945`):

| Arena | carve | share |
|---|---:|---:|
| `module` | 4,872K | 25% |
| `scratch` | 4,570K | 24% |
| **`diag_read`** | **4,545K** | **23%** |
| `perm` | 2,497K | 13% |
| `import_scratch` | 1,353K | 7% |
| `type_db` | 1,008K | 5% |
| `source` | 583K | 3% |
| `emission` / `lir_read` | 0 | 0% |

Σ carve 19,428K ≈ `pool` 19,473K ≈ RSS 20,844K. Spill sweep: `-s1` moves AST into `module`
(→26,120K), `-s2` adds LIR into `emission` (→+36,800K; rc=3 over the 64 MB budget). This confirms
that at `-s0` the AST and LIR are on disk and contribute **0**; the 20 MB is other structures.
Live total (perm+mod+scr) = ~3,022K → carve is ~6.4× live. AST scale: `IRN:n294693` nodes
(+`IRE:x117727`); 34,020 interned strings.

## Candidate (previously untargeted)

`diag_read` (4,545K, 23%) = the `SourceManager.fault` arena (`sf/src/source_manager.zig:148-177`):
faulted-in **source file text** plus a **per-line `u32` offset index**, retained for the whole run.
Companion observations: `import_scratch` 1,353K and `source` 583K. None of these were targeted by
the prior memory plans.

## Approach — SPIKE (measure-first)

Decompose the retention, catalog levers, and recommend. **No fixes are committed by this plan**;
anything built to measure is throwaway. Fix tasks are authored only if the spike confirms a lever
with a measured prize.

## Success criteria

1. A measured decomposition of `diag_read` (file-text bytes vs per-line index bytes vs other; per
   file; when each grows; peak timing) and of `import_scratch`/`source`.
2. A ranked lever catalog: mechanism, expected bytes, risk, and the gate that proves it.
3. A written recommendation (proceed / NO-GO) with the decisive numbers.

## Candidate levers (to be tested, not assumed)

- **L1** line-index representation: `u32` per line → `u16`/delta/lazy; expected prize bounded by
  line count × 2–3 bytes.
- **L2** drop file text after the index is built (re-read on demand at diagnostic time).
- **L3** bound `diag_read` retention (reset/ceiling between modules) so it does not accumulate.
- **L4** skip fault-in for modules that never emit a diagnostic needing source text.
- **L5** `import_scratch` / `source` caps or early release.

## Risks / constraints

Seed model (code that changes must use constructs the current seed understands); runtime equivalence
is the oracle; emitted C may change and dump-MD5 is recorded; `edit`/`fastedit` only when fixing;
compression forbidden during build sessions; no push; `timeout 120` per step (aggregates 600).

## Non-goals

- Re-litigating the exhausted allocator/AST/LIR/spill levers (F-1/I-F1, M5, I-COMPACT, S-INTERNER).
- Changing the C89 back-end toolchain (explicitly deprioritized).
- Any fix that cannot be proven runtime-equivalent on the `repro/mi_matrix` + goldens battery.
