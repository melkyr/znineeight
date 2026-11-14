# zig1 Self-Compile Non-AST Memory — Measurement Spike Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** measure and attribute the `-s0` self-compile non-AST memory consumers (chiefly
`diag_read`), catalog the levers, and recommend — **no compiler fixes are committed**.

**Architecture:** read-only per-arena and addressed measurement on the seed compiler; the spike's
output is a measured decomposition + ranked lever catalog + recommendation.

**Tech Stack:** the seed model (`release/seed/`, `scripts/seed/build_from_seed.sh`), the
`--markers` `arena <name>: grew` stream, `--track-memory`, `/usr/bin/time -v`, the
`repro/mi_matrix` corpus and its goldens.

**Spec:** `docs/superpowers/specs/2026-10-06-zig1-nonast-memory-design.md` (the plan argues from the
spec; executors read both).

## Global Constraints

- **Seed model (binding).** Reference compiler rebuilt per the seed model; current seed **v91**
  (archive md5 `39669954c928df59263e5d03cbaacd1d`; archived binary fixed point
  `0b8c3e4ac0b1fc49c0bdf8caf9d39945`). Build:
  `FIXED_POINT_MD5=0b8c3e4ac0b1fc49c0bdf8caf9d39945 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/nonast_seed`.
- **Memory metric.** Self-compile `-s<s> --markers --track-memory -o <fresh-dir> sf/src/main.zig`
  (CWD = repo root, RELATIVE `sf/src/main.zig`), plus `/usr/bin/time -v` Maximum RSS. Per-arena
  carve = sum of `arena <name>: grew <old> -> <new>` `new` values (`sf/src/allocator.zig:193`).
- **This is a spike.** No `sf/src` fixes, no seed rotation, no dump-MD5 re-baseline. The only
  committed artifacts are this plan, the spec, and the reports. Any measurement instrumentation is
  throwaway and must not be committed.
- **Editing:** `edit`/`fastedit` only, and only if a throwaway probe is unavoidable; re-read the
  region before each edit; edit bottom-to-top.
- **Compression is FORBIDDEN during build sessions.** No push. `timeout 120` per step; aggregate
  gates (corpus classify, `verify_stdlib`, `verify_upgraded`) `timeout 600`.
- Reports go under `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/`.

---

### Task 0: Preflight baseline (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/task-0-report.md`.

- [ ] **Step 1:** Build the seed per Global Constraints; record the resulting binary path + md5.
- [ ] **Step 2:** Self-compile at `-s0`; record `track-memory` line, `/usr/bin/time -v` RSS/wall, and
  the `.c`/`.h` counts.
- [ ] **Step 3:** Extract every `arena <name>: grew` line; sum `new` per arena; record the per-arena
  table and Σ (must ≈ `pool`).
- [ ] **Step 4:** Repeat at `-s1` and `-s2` (expect `-s2` to exceed the 64 MB budget, rc=3); record
  the arena deltas that show AST/LIR leaving disk.
- [ ] **Step 5:** Record AST/LIR scale markers (`L nodes=`, `IRN:n`, `IRE:x`) and the interned-string
  count (`INT:new` count).
- [ ] **Step 6:** Write the report and commit `docs: non-AST memory plan — Task 0 baseline`.

### Task 1: Decompose `diag_read` (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/task-1-report.md`.

- [ ] **Step 1:** Read `sf/src/source_manager.zig:148-262` and record exactly what `fault` retains
  (file text bytes, per-line `u32` offset array, any alignment/allocation overhead) and its lifetime.
- [ ] **Step 2:** Compute, from the on-disk self-compile inputs, the sum of source bytes faulted in
  and the sum of `line_count` across those files; multiply the latter by 4 for the index size; compare
  against the measured `diag_read` carve (4,545K). If they do not reconcile, do a throwaway
  allocation-count probe (not committed) to close the gap.
- [ ] **Step 3:** Establish *when* `diag_read` grows relative to other arenas (chronological position
  of its `arena grew` lines) and whether it is ever reset/reused.
- [ ] **Step 4:** Write the decomposition (text vs index vs other; per-file; timing) and commit.

### Task 2: Attribute `import_scratch` + `source` + `scratch`/`module` carve (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/task-2-report.md`.

- [ ] **Step 1:** Same decomposition for `import_scratch` (1,353K) and `source` (583K): what each
  holds, lifetime, and whether real vs quantized.
- [ ] **Step 2:** For `module` (4,872K) and `scratch` (4,570K), reconcile carve against the reported
  live peaks (`mod=`/`scr=`), and state how much is segment-quantization vs live (cite
  `sf/src/allocator.zig:118-191` growth policy: doubling capped at 1 MiB + `seg_free_head` reuse).
- [ ] **Step 3:** Write the report and commit.

### Task 3: Lever catalog + recommendation (READ-ONLY) — SPIKE TERMINAL

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/task-3-report.md`.

- [ ] **Step 1:** For each candidate lever L1–L5 (spec §"Candidate levers"), state: exact mechanism,
  files/sites, expected prize in bytes (bounded by the Task 0–2 measurements), risk, and the gate
  that would prove it (corpus + goldens + dump-MD5 delta recorded).
- [ ] **Step 2:** Rank by expected prize ÷ risk; mark any lever the measurements reject as **NO-GO**
  with the disconfirming number.
- [ ] **Step 3:** Write the recommendation (proceed on which levers, or NO-GO) and commit
  `docs: non-AST memory spike — findings + lever catalog`. **STOP. No fixes.**

---

## Prospective fixes (OUT OF SCOPE unless Task 3 confirms a lever)

These are **not** tasks of this spike. If Task 3 confirms a lever, a separate fix plan is authored,
one task per lever, each `measure → implement (edit/fastedit) → corpus+goldens+stdlib battery →
record dump-MD5 delta → commit`. Illustrative shapes only:

- **F-L1** `source_manager.zig`: store line offsets as `u16` (or delta/lazy) instead of `u32`.
- **F-L2** `source_manager.zig`: free faulted file text once the line index is built; re-read on
  demand.
- **F-L3** `source_manager.zig`: reset/ceiling the `diag_read` arena between modules.
- **F-L4** skip fault-in for modules that never produce a source-bearing diagnostic.
- **F-L5** cap/early-release `import_scratch` / `source`.

## Closeout

- Final report under `.superpowers/sdd/2026-10-06-zig1-nonast-memory-plan/`; commit docs only.
  No compiler code changed, no seed rotated, no dump-MD5 re-baselined.
