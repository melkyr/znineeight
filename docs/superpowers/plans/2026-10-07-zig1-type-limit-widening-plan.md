# zig1 Type-Limit Widening — Implement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** raise the user-facing `Type`-column ceilings (created by the structural live-set
narrowing) by widening the ceiling columns, keeping peak RSS ≤16 MB and full byte/runtime
equivalence.

**Architecture:** one focused source change (`sf/src/type_registry.zig` + its writer call
sites), guarded by the standard runtime-equivalence battery and an RSS median check; then a
docs note and a seed rotation.

**Tech Stack:** the seed model (`release/seed/`, `scripts/seed/build_from_seed.sh`), the
`--markers`/`--track-memory` stream, `/usr/bin/time -v`, the `repro/mi_matrix` corpus +
goldens + `verify_stdlib`.

**Spec:** `docs/superpowers/specs/2026-10-07-zig1-type-limit-widening-design.md` (the plan
argues from the spec; executors read both).

## Global Constraints

- **Seed model (binding).** Current seed **v93** (fixed point `639902d5146233091f6b2f98508ce3eb`,
  archive md5 `e1955908f3aa58992592f9c021c36d42`). Build:
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/widen_seed`
  (NO `FIXED_POINT_MD5` pin); gate `hop1 == hop2`. Any fix moves the fixed point — recorded,
  never silent.
- **Metric (binding).** Peak **RSS** (`/usr/bin/time -v` Maximum RSS), median of ≥3
  interleaved `-s0` self-compile runs. Carve ≠ touched RSS. Baseline to beat/meet:
  the structural-plan final median (~16,150 K, committed at `3fae3552`), target **≤16,384 K**.
- **Runtime-equivalence battery for every fix:** corpus classify diff-empty
  (923 OK / 58 GREEN / 116 FAIL / 0 ICE / 0 CRASH) + goldens gol/lisp/json/mud + `verify_stdlib`
  266/0 + examples 24/24 + dump-MD5 8/8 (stdout-stream) + semantic markers byte-identical
  IN-SESSION. Self-compile `-s0 --markers --track-memory -o <fresh-dir> sf/src/main.zig` (repo
  root, RELATIVE path; pre-create the dir).
- **Do not touch:** the interner bucket switch (`string_interner.zig`), the comptime `FoldVal`
  representation (`comptime_eval.zig`), or any right-sizing/representation change from the
  structural plan. This plan widens `Type` ceiling columns only.
- **Editing:** `edit`/`fastedit` only; re-read the region before each edit; edit bottom-to-top;
  INSERT = replace the anchor line with `[new content + the original anchor line]`.
- **Compression is FORBIDDEN during build sessions.** No push. Seed rotation only at closeout.
  `timeout 120` per step; aggregate gates (corpus/`verify_stdlib`/`verify_upgraded`) `timeout 600`.
- Reports go under `.superpowers/sdd/2026-10-07-zig1-type-limit-widening-plan/` (commit via
  `git add -f`).

---

### Task 0: Baseline adoption

**Files:** Report: `.superpowers/sdd/2026-10-07-zig1-type-limit-widening-plan/task-0-report.md`.

- [ ] **Step 1:** Confirm `sf/src` is at the structural-plan final state: HEAD `3fae3552`
  (or its successor), `git diff --stat 3fae3552..HEAD -- sf/src` empty unless HEAD already
  carries only doc commits. If `sf/src` has diverged, STOP-present.
- [ ] **Step 2:** Adopt the frozen baseline: seed v93, fixed point
  `639902d5146233091f6b2f98508ce3eb`, archive md5 `e1955908f3aa58992592f9c021c36d42`;
  `-s0` self-compile pool ≈11,965 K; peak RSS median ≈16,150 K; battery state (dump-MD5 8/8,
  corpus 923/58/116, stdlib 266/0, examples 24/24, goldens gol/lisp/json/mud).
- [ ] **Step 3:** Write the report and commit `docs: type-limit widening plan — Task 0 baseline`.
  **No measurement, no rewiring.**

### Task 1: Widen the `Type` ceiling columns

**Files:** Source: `sf/src/type_registry.zig` (+ writer call sites); Report: `.../task-1-report.md`.

- [ ] **Step 1:** In `sf/src/type_registry.zig`, widen the `Type` struct fields:
  `name_id: u16 → u32`, `payload_idx: u16 → u32`, `module_id: u8 → u16`, `alignment: u8 → u16`
  (keep `size: u32`, `kind`, `flags`, `state`, `iw: u8`). Expected struct size **20 B**.
- [ ] **Step 2:** Remove the ceiling guards `typeDbCeiling`, `typeNarrowU16`, `typeNarrowU8`
  and replace every writer wrapper with a plain cast: `name_id`/`payload_idx` writers become
  u32→u32 (drop the cast), `module_id`/`alignment` writers become u32→u16 `@intCast`. Touch the
  external writer sites too (`sf/src/symbol_registrator.zig` payload_idx sites;
  `sf/src/type_resolver.zig` payload_idx + alignment sites) and any internal `type_registry.zig`
  sites. Use `edit`/`fastedit` only.
- [ ] **Step 3:** If any now-stale comment references the old widths/ceilings (the `Type`
  declaration comment; the tech doc `sf/docs/tech_docs/03_type_resolution.md`), update in the
  same task or note for Task 2 closeout.
- [ ] **Step 4:** Run the full battery; record dump-MD5 delta (expected 0) and the new fixed
  point. Measure peak RSS median ≥3 vs the adopted baseline; record the delta (expected
  +~10–16 KB, still ≤16,384 K).
- [ ] **Step 5:** Report + commit `refactor(type-registry): widen Type ceiling columns`.

### Task 2: Closeout

**Files:** Report: `.../task-2-report.md`; docs updates.

- [ ] **Step 1:** Re-verify the battery at HEAD; record the final peak RSS and the new fixed
  point. Confirm the four `Type`-column ceilings are gone/residual-only (name_id/payload_idx
  u32; module_id/alignment u16).
- [ ] **Step 2:** Add a short **compiler-limits** note to `docs/sf/QUICK_REF.md` recording the
  ceilings, the current headroom, and that they were raised (so future readers know the
  history and the residual u16 module/alignment limits). Update
  `sf/docs/tech_docs/03_type_resolution.md` `Type` layout 16 B → 20 B.
- [ ] **Step 3:** Rotate the seed v93→v94 via
  `bash scripts/seed/archive_seed.sh <new-binary> <gen_dir> release/seed/zig1-seed.tgz --update-changelog`
  (operator-ruled re-baseline).
- [ ] **Step 4:** Report + commit `docs: type-limit widening plan — closeout + seed v94`.

---

## Deferred (not in this plan)

The de-narrowing/undo of the interner bucket width, the comptime `FoldVal` representation, and
the general "what if a user still hits a residual limit" policy (e.g. an auto-migrating
side-table for `module_id`) — out of scope; only the `Type` ceiling columns are widened here.
