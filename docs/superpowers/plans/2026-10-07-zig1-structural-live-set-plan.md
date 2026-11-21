# zig1 Structural Live-Set Reduction — Implement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** structurally reduce the large resident compiler structures (string interner, type
registry, comptime fold table), biggest first, stopping as soon as peak RSS reaches the 16 MB
target so the compiler is disturbed no more than necessary.

**Architecture:** per work package, a read-only **Investigate** task (static analysis → ranked
candidates with byte prize + risk) followed by a **Fix** task (implement, run the battery, measure
RSS). Three work packages; each Fix has a stop-gate.

**Tech Stack:** the seed model (`release/seed/`, `scripts/seed/build_from_seed.sh`), the
`--markers`/`--track-memory` stream, `/usr/bin/time -v`, the `repro/mi_matrix` corpus + goldens +
`verify_stdlib`.

**Spec:** `docs/superpowers/specs/2026-10-07-zig1-structural-live-set-design.md` (the plan argues
from the spec; executors read both).

## Global Constraints

- **Seed model (binding).** Current seed **v92** (archive md5 `3cacdd44df75c0ce96abfd51af93f928`).
  Build: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/struct_seed`
  (NO `FIXED_POINT_MD5` pin); gate `hop1 == hop2`. Any fix moves the fixed point — recorded, never
  silent.
- **Metric (binding).** Peak **RSS** (`/usr/bin/time -v` Maximum RSS), median of ≥3 interleaved
  self-compile runs at `-s0`. Carve ≠ touched RSS.
- **Static analysis only; no rewiring.** Investigate tasks read source and use existing counts;
  they do NOT wire dormant helpers or add instrumentation.
- **Runtime-equivalence battery for every Fix:** corpus classify diff-empty
  (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + goldens gol/lisp/json/mud + `verify_stdlib`
  266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream) + semantic markers byte-identical
  IN-SESSION. Self-compile `-s0 --markers --track-memory -o <fresh-dir> sf/src/main.zig` (repo root,
  RELATIVE path; pre-create the dir).
- **Do not re-litigate closed levers:** 16-B `AstNode` (I-COMPACT), sparse→dense for
  `coercion`/`enum_value_table`/`comptime_values`, F-1/I-F1, M5, prior S-INTERNER scope.
- **Editing:** `edit`/`fastedit` only; re-read the region before each edit; bottom-to-top.
- **Compression is FORBIDDEN during build sessions.** No push. Seed rotation only at closeout.
  `timeout 120` per step; aggregate gates (corpus/`verify_stdlib`/`verify_upgraded`) `timeout 600`.
- Reports go under `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/` (commit via
  `git add -f`).

**Work packages:** **1** = Tasks 1–2 (string interner) · **2** = Tasks 3–4 (type registry) ·
**3** = Tasks 5–6 (comptime fold table). **Stop-gate:** after Task 2, if peak RSS ≤ 16 MB → STOP and
skip Tasks 3–6; else proceed. Same gate after Task 4 and Task 6.

---

### Task 0: Baseline adoption (no work wasted)

**Files:** Report: `.superpowers/sdd/2026-10-07-zig1-structural-live-set-plan/task-0-report.md`.

- [ ] **Step 1:** Confirm `sf/src` is byte-identical to the post-L3 state: `git diff --stat
  2d713a9a..HEAD -- sf/src` must be empty (the prior live-set spike committed docs only).
- [ ] **Step 2:** Adopt the prior frozen baseline from
  `.superpowers/sdd/2026-10-06-zig1-live-set-reduction-plan/task-0-report.md` (pool 14,924 K;
  per-arena carve; RSS median ≈17.4–17.6 MB; 8/8 dump-MD5; corpus 923/58/116; stdlib 266/0;
  examples 24/24; goldens gol/lisp/json/mud). Record the seed version + closure fixed point
  (`2293f756a8250351740cf6acde194d17`).
- [ ] **Step 3:** Note the interim target: peak RSS ≤ 16 MB; restate that Task 1's Fix is the first
  stop-gate.
- [ ] **Step 4:** Write the report and commit `docs: structural live-set plan — Task 0 baseline`.
  **No measurement, no rewiring.** If `sf/src` has drifted, STOP-present.

### Task 1: Investigate the string interner (READ-ONLY)

**Files:** Report: `.../task-1-report.md`.

- [ ] **Step 1:** Read `sf/src/string_interner.zig` end to end and all consumers
  (`internerGet/GetOrCreate`, `stringInternerCopyToArena`, init sizing at `main.zig:188-190`).
  Record the exact layout: bucket array width/count, entry size/columns, text copy, load-factor and
  rehash/clone behaviour.
- [ ] **Step 2:** Establish the true counts at self-compile (34,020 interned strings; buckets
  ~125,798; entries cap 62,899; text bytes) from existing measurements/markers only (no new wiring).
- [ ] **Step 3:** Apply the four lenses (integer reuse; one-use/retention; representation;
  pointer-vs-inline with mutation safety) and produce a ranked candidate list — each with a concrete
  mechanism, file:line, byte prize (resident at `-s0`), risk, and the gate. Do not re-open the
  closed S-INTERNER verdict without new evidence; state explicitly what the prior verdict closed.
- [ ] **Step 4:** Write the report and commit `docs: structural live-set plan — Task 1 interner analysis`.

### Task 2: Fix the string interner → STOP-GATE

**Files:** Source: `sf/src/string_interner.zig` (+ any call sites); Report: `.../task-2-report.md`.

- [ ] **Step 1:** Implement the top candidate(s) from Task 1 with `edit`/`fastedit` only.
- [ ] **Step 2:** Run the full battery (Global Constraints); record dump-MD5 delta and the new fixed
  point; re-run corpus/goldens/stdlib/examples.
- [ ] **Step 3:** Measure peak RSS (median ≥3) vs the baseline; record the delta.
- [ ] **Step 4:** Report + commit `refactor(interner): structural reduction`. **STOP-GATE:** if peak
  RSS ≤ 16 MB, STOP the plan (go to Task 7 closeout) — do **not** start Task 3.

### Task 3: Investigate the type registry (READ-ONLY)

**Files:** Report: `.../task-3-report.md`.

- [ ] **Step 1:** Read `sf/src/type_registry.zig` (Type, side tables, the 8 caches, `payloadEnsure`
  growth, `types_alloc`/`type_db`) and its consumers. Record layout, element sizes, counts, and caps.
- [ ] **Step 2:** Apply the four lenses; produce a ranked candidate list (mechanism, file:line,
  resident byte prize, risk, gate). Every pointer/inline or SoA↔AoS idea must carry the mutation/
  aliasing analysis (the registry hands out slices into growable arrays).
- [ ] **Step 3:** Explicitly avoid the closed sparse→dense lever; do not re-open I-COMPACT-type node
  work. Write the report and commit `docs: structural live-set plan — Task 3 type-registry analysis`.

### Task 4: Fix the type registry → STOP-GATE

**Files:** Source: `sf/src/type_registry.zig` (+ call sites); Report: `.../task-4-report.md`.

- [ ] **Step 1:** Implement the top candidate(s) with `edit`/`fastedit` only.
- [ ] **Step 2:** Full battery; record dump-MD5 delta + new fixed point.
- [ ] **Step 3:** Measure peak RSS (median ≥3) vs baseline; record delta.
- [ ] **Step 4:** Report + commit `refactor(type-registry): structural reduction`. **STOP-GATE:** if
  peak RSS ≤ 16 MB, STOP (go to Task 7).

### Task 5: Investigate the comptime fold table (READ-ONLY)

**Files:** Report: `.../task-5-report.md`.

- [ ] **Step 1:** Read `sf/src/comptime_eval.zig` (`ComptimeVal` 48 B, `ComptimeInt` 36 B, the fold
  table slots/vals, `comptimeFoldTablePut/Get`) and its consumers in `lower.zig`.
- [ ] **Step 2:** Apply the four lenses; ranked candidate list (mechanism, file:line, resident byte
  prize, risk, gate). The leading lead is a narrow common-case value with a rare big-integer side
  pool — state the value-range evidence and the copy-by-value call sites it touches.
- [ ] **Step 3:** Write the report and commit `docs: structural live-set plan — Task 5 comptime analysis`.

### Task 6: Fix the comptime fold table

**Files:** Source: `sf/src/comptime_eval.zig` (+ call sites); Report: `.../task-6-report.md`.

- [ ] **Step 1:** Implement the top candidate(s) with `edit`/`fastedit` only.
- [ ] **Step 2:** Full battery; record dump-MD5 delta + new fixed point.
- [ ] **Step 3:** Measure peak RSS (median ≥3) vs baseline; record delta.
- [ ] **Step 4:** Report + commit `refactor(comptime): structural reduction`.

### Task 7: Closeout

**Files:** Report: `.../task-7-report.md`; docs updates.

- [ ] **Step 1:** Re-verify the battery at HEAD; record the final peak RSS and what was/was not
  executed under the stop-gate.
- [ ] **Step 2:** Record dump-MD5 deltas/fixed points; update `docs/sf/QUICK_REF.md` memory/seed
  notes as required; note any deferred structures (AST window, hash-map layout, one-use retention).
- [ ] **Step 3:** Rotate the seed v92→v93 via
  `bash scripts/seed/archive_seed.sh <binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`
  (operator-ruled re-baseline). Commit `docs: structural live-set plan — closeout + seed v93`.

---

## Deferred (not in this plan)

AST window/value-pool representation, hash-map layout (interleaved single array), and one-use
retention (classify work arrays, symbol registry). They are captured in the reconnaissance and
re-judged after the stop-gate — not executed here.
