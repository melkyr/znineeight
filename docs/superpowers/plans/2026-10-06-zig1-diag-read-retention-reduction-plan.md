# zig1 `diag_read` Retention Reduction — Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** lower the `-s0` self-compile `pool` toward/below 16,384 K by bounding the `diag_read`
fault arena (L3 primary; L6 growth-rule secondary), runtime-equivalent.

**Architecture:** reset the `SourceManager` fault arena per module (L3) and bound the whole-file
fault's segment tail with a growth rule selected by measurement (L6); both on the seed compiler.

**Tech Stack:** seed model (`release/seed/`, `scripts/seed/build_from_seed.sh`), `--markers`
`arena <name>: grew` attribution, `--track-memory`, `/usr/bin/time -v`, `repro/mi_matrix` corpus and
goldens.

**Spec:** `docs/superpowers/specs/2026-10-06-zig1-diag-read-retention-reduction-design.md` (binding
authority; the plan argues from it). Measurement authority: the 2026-10-06 non-AST memory spike
reports (`docs/superpowers/plans/2026-10-06-zig1-nonast-memory-plan.md`).

## Global Constraints

- **Seed model (binding).** Current seed **v92** (rotated 2026-10-06): binary + fixed point
  `d40e875a7ba3aa55d441af56006f6023`, archive md5 `3cacdd44df75c0ce96abfd51af93f928`. Build:
  `FIXED_POINT_MD5=d40e875a7ba3aa55d441af56006f6023 bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/retention_seed`.
- **Memory metric.** Self-compile `-s0 --markers --track-memory -o <fresh> sf/src/main.zig`
  (CWD = repo root, RELATIVE path) + `/usr/bin/time -v` Maximum RSS. Per-arena carve = Σ of
  `arena <name>: grew <old> -> <new>` `new` values (`sf/src/allocator.zig:193`).
- **Runtime equivalence is the oracle.** Every refactor must leave: `repro/mi_matrix` corpus
  classify byte-identical (diff-empty), runtime goldens exact, `verify_stdlib` 266/0, examples 24/24,
  `--markers` stderr identical. Emitted C may change; **record** the dump-MD5 delta (`-fsafe` and
  `-ffast`, gol/lisp/json/mud) per task; do NOT re-baseline without an operator ruling.
- **L6 is a growth *rule*, not exact-fit.** The rule is chosen and justified by measured per-arena
  carve + pool in Task 3; candidates R-a…R-e are in the spec.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.3/§X.7 — re-read the region immediately before
  each edit; edit bottom-to-top). No `sed`/python/bulk transforms.
- **Compression is FORBIDDEN during build sessions.** No push. `timeout 120` per step; aggregate
  gates (corpus classify, `verify_stdlib`, `verify_upgraded`) `timeout 600`.
- Reports + ledger under `.superpowers/sdd/2026-10-06-zig1-diag-read-retention-reduction-plan/`.

---

### Task 0: Preflight baseline (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-diag-read-retention-reduction-plan/task-0-report.md`.

- [ ] **Step 1:** Build the v92 seed per Global Constraints; record the binary path + md5.
- [ ] **Step 2:** Self-compile at `-s0`; record the `track-memory` line, `/usr/bin/time -v` RSS/wall,
  `.c`/`.h` counts, and the per-arena carve table (Σ ≈ `pool`).
- [ ] **Step 3:** Capture the **pre-fix dump-MD5** the spike never recorded: `-fsafe` and `-ffast`,
  for `examples/z98/{gol,lisp,json,mud}` (or the four the spike used), emitted-C hash + file counts.
- [ ] **Step 4:** Record the corpus classify tally, runtime goldens, and `verify_stdlib` result.
- [ ] **Step 5:** Write the report and commit `docs: diag_read retention plan — Task 0 baseline`.

### Task 1: Analyze + L6 growth-rule design (READ-ONLY)

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-diag-read-retention-reduction-plan/task-1-report.md`.

- [ ] **Step 1 (L3 confirm):** read `sf/src/main.zig:739-778`, `:103`, `sf/src/source_manager.zig:148-202`,
  `sf/src/import_resolver.zig:16`; state the exact insertion point and prove the reset is safe (all
  files transient; no analysis-time consumer retains a prior module's `content` across the reset;
  print-time re-fault path is exercised).
- [ ] **Step 2 (L6 design):** evaluate R-a…R-e (spec §L6) against `sf/src/allocator.zig:118-191`;
  for each viable candidate state the exact edit site, expected per-arena effect (especially
  `module`/`scratch`/`emission`), and risk. Select ≥2 candidates to try in Task 3 and nominate
  R-c as primary.
- [ ] **Step 3:** Write the report (verdict + chosen candidates) and commit
  `docs: diag_read retention plan — Task 1 analysis + growth-rule design`.

### Task 2: L3 — reset `diag_read` per module

**Files:** `sf/src/main.zig` (and `sf/src/source_manager.zig` only if the reset needs a change).

- [ ] **Step 1:** Add `ctx.source_man.sourceManagerResetFaults();` at the end of the per-module loop
  body in `phase_StaticAnalyzers` (after `az_mod.runAllAnalyzers(&ac, ast_root);`, `sf/src/main.zig:775`),
  using `edit`/`fastedit` per Global Constraints.
- [ ] **Step 2:** Build via the seed Gate; run the full battery (corpus/goldens/stdlib/examples/
  markers) — must be byte-identical.
- [ ] **Step 3:** Measure `-s0` pool / RSS / per-arena carve vs Task 0. Record the dump-MD5 delta.
- [ ] **Step 4:** Commit `perf(source_manager): reset diag_read per module (L3)`. **Gate:** pool must
  fall; if it does not, STOP and report the measurement.

### Task 3: L6 — bound the whole-file fault segment tail (growth rule)

**Files:** `sf/src/allocator.zig` (growth policy) and/or `sf/src/source_manager.zig` (fault site).

- [ ] **Step 1:** Implement the Task-1 candidate rule(s) (R-c primary; ≥2 measured). Measure each
  variant's `-s0` pool + per-arena carve; keep the best. Revert the loser(s) so only one rule lands.
- [ ] **Step 2:** Full battery byte-identical; measure `-s0` pool / RSS / per-arena vs Task 2; record
  the dump-MD5 delta. Confirm no `module`/`scratch` regression.
- [ ] **Step 3:** Commit `perf(allocator): bound diag_read segment tail (L6)`. **Gate:** battery
  byte-identical; pool falls; no other arena regresses beyond noise.

### Task 3b: L6 re-design — a rule that lowers BOTH `pool` and RSS

**Files:** Report: `.superpowers/sdd/2026-10-06-zig1-diag-read-retention-reduction-plan/task-3b-report.md`.

Context: Task 3 R-c was reverted (`841be07c`) — it lowered `pool` (14,019 K) but **raised** RSS
(~18,324 K vs the L3 baseline ~17,580 K). The binding spec's "L6 re-design (post-Task-3)" section
governs. `pool` is the `-mm16` metric; **RSS is the real-hardware goal.**

- [ ] **Step 1:** Read the spec's "L6 re-design" section. Starting from the current L3-only tree,
  evaluate the candidate directions by **throwaway** measurement (one at a time; revert each with
  `edit` before the next — never `git checkout`).
- [ ] **Step 2:** Per candidate, measure `pool` (`--track-memory`), RSS (`/usr/bin/time -v`,
  **median of ≥3**), the `arena <name>: grew` event count, and per-arena carve (esp. `source`,
  `type_db`, `module`, `diag_read`); run the byte-identical battery (semantic markers **in-session**).
- [ ] **Step 3:** Recommend a rule **iff** it satisfies the binding gate: `pool` ≤ 14,924 K AND
  RSS ≤ ~17,580 K (within stated noise) AND battery byte-identical. Otherwise recommend **L3-only /
  L6 NO-GO**.
- [ ] **Step 4:** Write the report and commit `docs: diag_read retention plan — Task 3b L6 re-design`.
  Do **not** commit a source rule — the operator approves the chosen rule before any L6 source lands.

### Task 4 (OPTIONAL / DEFERRED): L1 — line-index `u32` → `u16`/delta

**Files:** `sf/src/source_manager.zig:163-178`. Implement ONLY if the operator requests it; ≤103 K
live / ~0 pool benefit. Default: skip.

### Task 5: Closeout

**Files:** `docs/sf/QUICK_REF.md`, `README.md`, `release/seed/**`, this plan, reports.

- [ ] **Step 1:** Whole-set runtime re-verify vs the Task-0 baseline.
- [ ] **Step 2:** Record the `-s0` pool/RSS delta vs Task 0 and vs the 16,384 K target (honest
  remainder).
- [ ] **Step 3:** Record the dump-MD5 delta (operator-ruled; re-baseline only on ruling).
- [ ] **Step 4:** Reconcile the stale memory figures in `docs/sf/QUICK_REF.md` (last measured at seed
  v89) and `README.md` (stale at seed v27) with the measured post-fix values; state that `pool=` is
  cumulative carve, not RSS.
- [ ] **Step 5:** Rotate the seed **v92 → v93** via `scripts/seed/archive_seed.sh` (the compiler
  changed); verify the two-hop closure; update `release/seed/CHANGELOG.md`.
- [ ] **Step 6:** Commit `docs: diag_read retention closeout — memory re-measured, seed rotated`.

## STOP conditions

- A refactor that cannot pass the byte-identical battery, or whose measured pool does not fall: STOP,
  report the measurement; do not continue to the next task.
- Any change whose site/rule is not the approved one: STOP and present (operator is the authority).
