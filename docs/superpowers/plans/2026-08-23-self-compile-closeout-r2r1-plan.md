# Self-Compile 194-Error Closeout + R2/R1 Residual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the 194-error self-compile plan, extend solved fixtures for analogous valid-Zig shapes, fix the final 12 self-compile gcc errors (R2 `zT_<n>` undeclared ×11 + R1 Opt_10 ×1) via R/I/F, and fix the newly-surfaced array-copy direct-assign emission bug (R-ACOPY/I-ACOPY/F-ACOPY).

**Architecture:** Eleven-task sequence — GATE-CLOSE (docs) → A-ANALYZE (read-only) → A-ADD (fixtures) → R-R2/I-R2/F-R2 → R-R1/I-R1/F-R1 → R-ACOPY/I-ACOPY/F-ACOPY (AMENDMENT 1) → GATE-FINAL. Soft gate: fixture GREEN + no regression is hard; self-compile re-count observational.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, 4 MD5 gates, matrix 21/21, corpus 310 (re-baselined, AMENDMENT 1).

## Global Constraints

- **Soft success gate (operator ruling):** per-F HARD gate = fixture GREEN (gcc -c rc=0) + no functional regression; self-compile re-count **observational only**. **Runtime-identity governs** (byte-diff runtime-identical = re-baseline default; byte-diff with runtime/correctness doubt = STOP).
- **4 MD5 baselines (authoritative):** gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), **json `d31e43b19f752e40b9fd4b8885b13600`** (re-baselined), mud `a1d0dd55aada9c3fd904ae33f54de32e`. Matrix 21/21.
- **Emission-only.** Only `sf/src` files named by the I reports are touched.
- **`sf/build/out_release/` is WEDGED — NEVER touch/list/build into it.** All compiler runs `timeout 120`.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std: `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Commit messages verbatim per task.
- **Self-compile re-count recipe:** `bash scripts/self_compile/build_zig1_5.sh` then `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs_<n>.txt`.

> **AMENDMENT 1 (2026-08-24, operator rulings after A-ANALYZE):** (1) `emission_misc_xmod` is NOT solved — it fails on a NEW live RED class (array-copy direct-assign: `assignment to expression with array type` at `fb = src;` + co-occurring `'zT_<n>' undeclared`; root = the array-copy `.assign`/`.store_local` path emits BOTH the bogus `dst = src;` line AND the correct copy loop, `c89_emit.zig`). Operator ruling: **extend this plan with a new R/I/F task set — R-ACOPY / I-ACOPY / F-ACOPY** (added below, before GATE-FINAL) to reproduce, investigate, and fix this array-copy direct-assign bug. **Ruling (b) (2026-08-24): A-ADD writes ALL 4 live-RED shapes (incl. the array-copy fixture `emission_array_copy_xmod`); R-ACOPY is re-pointed to VERIFY that fixture, not create its own.** (2) `emission_pal_xmod` now classifies **green-guard** (front-end `error[20]` reject = correct rejection of the undeclared-identifier class; the class can never be a gcc-RED fixture again). (3) **Corpus re-baselined 303 → 310** (GATE-FINAL measures the true 310-dir corpus: +7 new 194-plan fixture dirs; their per-dir classification recorded in the final sweep). (4) **A-ADD scope:** write fixtures for the 4 verified-live RED shapes (§5.1) AND a representative set of expected-GREEN control cells grouped by family (§5.2), documenting each control as GREEN per A-ADD Step 2 — do NOT force a wrong class. Incidental out-of-plan live bug (optional-fn-ptr wrap gap, §6.1) recorded only, NOT fixed.

> **AMENDMENT 3 (2026-08-24, operator ruling after I-ORELSEBLK review):** I-ORELSEBLK's report identified a genuine fix-design fork (Step 3 STOP trigger) — Fix A (mirror the catch arm: guard the orelse join materialize+assign on `block_terminated == 0` for ALL RHS) vs Fix B (scoped block-RHS-only guard). The implementer pinned Fix B without STOPping (reviewer-graded Critical); the fork was presented to the operator. **OPERATOR RULING: Fix A.** The catch arm (`lower.zig:3546-3550`) already holds the canonical correct pattern (flag check BEFORE the join assign); the orelse arm (`:3594` assigns unconditionally) is the out-of-sync sibling. Fix A restores symmetry, fires only on failing programs, ALSO closes the `orelse unreachable` first-param leak, and (reviewer-verified) changes zero baselines (no gate/corpus emits `orelse unreachable`; the removed dead line is overwritten on the ok path → runtime-identical). Fix B rejected as incomplete (ad-hoc kind-check, leaves orelse asymmetric with catch, leaves the `orelse unreachable` leak live). F-ORELSEBLK implements Fix A (commit msg `fix: orelse block terminator emits no void temp assign (zT undeclared, 5 errors)`).

> **AMENDMENT 2 (2026-08-24, operator ruling after R-R2):** R-R2 investigation FALSIFIED the plan's stated R2 mechanism. The 11 residual `zT_<n> undeclared` errors are TWO distinct root causes: **(a) comptime array `.len` inside `@intCast` → TYPE_VOID** (semantic_analyzer.zig slice-only `.len` branch :584-592; array base falls to :649 else; lowering allocates a never-written VOID temp; hoisted-decl emitter skips its C declaration `c89_emit.zig:3158`) — **c89_emit ×6** sites, reproduced by the committed `emission_temp_index_drift_xmod` fixture (RED verified, commit `751c36e6`); and **(b) orelse-block terminator** (`orelse { return null; }` — orelse else-branch emits `assign join_temp = null_val` unconditionally at `lower.zig:3584` BEFORE the `block_terminated` check :3586, unlike the catch arm :3536-3541) — **import_resolver ×2, main ×1, module_registry ×2** = 5 sites, already given a RED fixture `emission_orelse_block_xmod` in A-ADD. **RULING: I-R2/F-R2 re-scoped to the real array-`.len`→VOID mechanism (F-R2 commit msg `fix: array .len resolves to VOID temp (zT undeclared, 6 errors)`); a NEW I-ORELSEBLK/F-ORELSEBLK task pair added (after F-R2) for the orelse-block terminator (commit msg `fix: orelse block terminator emits no void temp assign (zT undeclared, 5 errors)`).**

---

### Task GATE-CLOSE: 194-plan docs closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATECLOSE-r2r1-report.md`

**Consumes:** the 194-plan's final state (12 errors, json re-baseline). **Produces:** reconciled tracking docs closing the 194-plan.

- [ ] **Step 1: Reconcile EXPECTED_FAIL.md**

Bump v44→v45. Add a closeout section for the 194-error plan: all landed fixes (F-MIGRATE `1a06716b`+`df9c3017`, F-A `6b44d7a3`, F-B `6d4892bf`+`56a80136`, F-ORELSE `f8e3d914`, F-C `cb378f17` + AMENDMENTs 4/5), the json MD5 re-baseline `9720478c…`→`d31e43b1…`, and the **final 12-error state** (R2 zT-undeclared ×11 + R1 Opt_10 ×1) with a forward-pointer to this plan.

- [ ] **Step 2: Reconcile QUICK_REF.md**

Update the json MD5 table row `9720478c…`→`d31e43b1…` (row :335 area). Add a post-194-closeout baseline paragraph recording the 12-error residual + pointer to this plan.

- [ ] **Step 3: Verify docs internal consistency**

Cross-check both docs: same 12-error split, same json MD5, same fix-commit list, arithmetic consistent (11+1=12).

- [ ] **Step 4: Commit**

Commit: `docs: self-compile 194-error plan closeout GATE + reconciliation`

---

### Task A-ANALYZE: analogous-shape fixture analysis (read-only)

**Files:**
- Read: `repro/mi_matrix/emission_*_xmod/` (24 dirs), `docs/sf/QUICK_REF.md`
- Create: `.superpowers/sdd/task-A-analyze-report.md` (report, no commit)

**Consumes:** the solved fixtures. **Produces:** per-fixture analogous-shape variant table with COVERED/ADD/N-A verdicts.

- [ ] **Step 1: Enumerate the 24 solved fixtures + their mechanisms**

List each `emission_*_xmod` fixture, its root cause (name-keyed conflation, capture shadowing, orelse terminator, `.f_2` drain, void-payload guard, mangler/type-storage, etc.), and the exact shape it exercises.

- [ ] **Step 2: For each fixture, enumerate analogous valid-Zig shape variants**

For each fixture's trigger shape, list the dialect-valid variants that could hit the SAME root cause: if↔switch (expr/stmt), while↔for (incl. for-slice/for-range), flat↔nested blocks, single↔multi-capture, orelse↔orelse-block / catch variants, tagged-union↔plain-union, single-module↔cross-module, expression-position↔statement-position, single-prong↔multi-prong. For each variant: **COVERED** (an existing fixture already exercises it), **ADD** (no fixture exercises it — new RED fixture needed), **N-A** (shape doesn't exist in the dialect).

- [ ] **Step 3: Verdicts + byte-identity reasoning**

For each ADD, state the expected RED error text (analogous to the solved fixture's) and confirm the fixture would be gcc-invalid (so it's a valid diagnostic fixture, not a false positive).

- [ ] **Step 4: Write report + STOP if a fork arises**

Report at `.superpowers/sdd/task-A-analyze-report.md`. No commit (read-only). If any ADD verdict is uncertain (dialect question), STOP and present.

---

### Task A-ADD: analogous-shape fixtures

**Files:**
- Create: `repro/mi_matrix/<name>_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}` per ADD verdict
- Report: `.superpowers/sdd/task-A-add-report.md`

**Consumes:** A-ANALYZE report. **Produces:** committed RED fixtures for all ADD verdicts.

- [ ] **Step 1: Write one fixture per ADD verdict** (AMENDMENT 1 scope: the 4 verified-live RED shapes from A-ANALYZE §5.1 — array-copy direct-assign, orelse+labeled-stmt RHS, orelse+plain-block RHS, catch+labeled-stmt RHS — PLUS a representative set of expected-GREEN control cells grouped by family from §5.2; each control documented GREEN in NOTES.md, do NOT force a wrong class)

Follow the established `emission_*_xmod` convention (full-graph 3+ modules where scale matters, `std.io.printInt` main, NOTES.md with purpose + verbatim fixture + RED evidence + root-cause pin + expected post-fix).

- [ ] **Step 2: Verify RED on each**

Run: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir <dir> <main.zig>` then `cd <dir> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: same gcc error class as the solved fixture it mirrors. If a shape turns out to be GREEN (no error), record it as a control in NOTES.md (do NOT force a wrong class).

- [ ] **Step 3: Commit**

Commit: `repro: emission fixture extension (analogous-shape variants)`

---

### Task R-R2: zT temp-index drift fixture (DONE — AMENDMENT 2 re-scope)

**Files:**
- Create: `repro/mi_matrix/emission_temp_index_drift_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}` — DONE (commit `751c36e6`)
- Report: `.superpowers/sdd/task-RR2-r2r1-report.md`

**Consumes:** the residual c89_emit zT-undeclared sites ×6. **Produces:** RED fixture reproducing the exact `zT_<n> undeclared … did you mean zT_<m>?` class. **AMENDMENT 2 (operator ruling, 2026-08-24): the plan's stated "cross-function hoisted-temp index drift" mechanism was FALSIFIED by investigation. The real mechanism is comptime array `.len` inside `@intCast` resolving to `TYPE_VOID` (semantic_analyzer.zig slice-only `.len` branch :584-592; array base → :649 else) → lowering allocates a never-written VOID temp → hoisted-decl emitter skips its C declaration (`c89_emit.zig:3158`) → the cast reference remains undeclared. The 11 residual R2 errors are TWO root causes: array-`.len`→VOID (c89_emit ×6, this fixture) + orelse-block terminator (import_resolver ×2, main ×1, module_registry ×2 — handled by new I-ORELSEBLK/F-ORELSEBLK). I-R2/F-R2 re-scoped accordingly.**

- [x] **Step 1: Identify the minimal trigger**

From the residual sites (c89_emit ×6), determine the minimal Zig construct whose lowering produces a referenced-but-never-declared `zT_<n>` temp. Mirror the observed shape (`@intCast(u32, <array>.len)` buffer-slicing).

- [x] **Step 2: Write the fixture + verify RED**

Full-graph 3+ modules; RED must be `'zT_<n>' undeclared … did you mean 'zT_<m>'?` (m = n + offset), byte-identical class to the residual. NOTES.md: purpose, verbatim fixture, RED evidence, root-cause pin (array-`.len`→VOID), expected post-fix.

- [x] **Step 3: Commit**

Commit: `repro: self-compile 194-error fixture (zT temp-index drift)`

---

### Task I-R2: investigate array-`.len`→VOID (read-only)

**Files:**
- Read: `sf/src/semantic_analyzer.zig` (`.len` field-access resolution — slice branch :584-592, array base falls through to :649 else → TYPE_VOID), `sf/src/lower.zig` (temp alloc for void result ~:2568-2701), `sf/src/c89_emit.zig` (hoisted-decl VOID skip :3158)
- Create: `.superpowers/sdd/task-IR2-r2r1-report.md` (report, no commit)

**Consumes:** R-R2 fixture + the 6 residual c89_emit sites. **Produces:** pinned upstream fix design.

- [ ] **Step 1: Trace the array-`.len`→VOID leak**

Determine why comptime array `.len` inside `@intCast(u32, <array>.len)` resolves to `TYPE_VOID` (semantic analyzer has only a slice-`.len` branch at :584-592; an array base falls through to the final else :649). Confirm the lowering allocates a never-written VOID temp and the hoisted-decl emitter skips its C declaration (`c89_emit.zig:3158` `eff_type != 1`), leaving the `@intCast` reference undeclared.

- [ ] **Step 2: Pin the fix design**

Name the exact site + change shape (likely add an array-`.len` branch in `semanticAnalyzerResolveFieldAccess` returning the array's length type). Reason byte-identity: gates/corpus have no such array-`.len`-in-cast today (they're gcc-clean) → fix fires only on failing programs → no re-baseline expected.

- [ ] **Step 3: STOP on fork if two valid fixes exist**

If the fix has two valid resolutions with different byte-identity/correctness implications, present and STOP.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-IR2-r2r1-report.md`. No commit.

---

### Task F-R2: apply array-`.len`→VOID fix

**Files:**
- Modify: the file(s) named by the I-R2 report
- Report: `.superpowers/sdd/task-FR2-r2r1-report.md`

**Consumes:** I-R2 report. **Produces:** R2 fixture GREEN + re-count.

- [ ] **Step 1: Apply the fix**

Implement per I-R2 via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
mkdir -p /tmp/fx_subfolder/lib && cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 3: R2 fixture GREEN + prior fixtures still GREEN**

`emission_temp_index_drift_xmod` gcc rc=0; re-run a few solved fixtures (assign/request_member/orelse) to confirm no regression.

- [ ] **Step 4: Re-count (observational)**

`bash scripts/self_compile/build_zig1_5.sh` + gcc -c → record `zT_<n> undeclared` count (target 0 for the array-`.len` class; the 5 orelse-block sites are tracked separately by I-ORELSEBLK/F-ORELSEBLK — see AMENDMENT 2). Record full class split.

- [ ] **Step 5: Runtime-identity gate**

4 MD5s (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json `d31e43b1…`, mud `a1d0dd55…`) + matrix 21/21. Byte-diff runtime-identical → re-baseline; any doubt → STOP.

- [ ] **Step 6: Commit**

Commit: `fix: array .len resolves to VOID temp (zT undeclared, 6 errors)`

---

### Task I-ORELSEBLK: investigate orelse-block terminator (read-only) — AMENDMENT 2

**Files:**
- Read: `sf/src/lower.zig` (orelse_expr arm ~:3557-3609, the unconditional `assign join_temp = null_val` at :3584 before the `block_terminated` check :3586; catch_expr arm ~:3490 which checks block_terminated BEFORE the join assign :3536-3541), `sf/src/c89_emit.zig` (temp emission)
- Create: `.superpowers/sdd/task-IORELSEBLK-r2r1-report.md` (report, no commit)

**Consumes:** the 5 residual orelse-block sites (import_resolver ×2, main ×1, module_registry ×2) + the `emission_orelse_block_xmod` RED fixture (A-ADD). **Produces:** pinned upstream fix design.

- [ ] **Step 1: Trace the orelse-block double assign**

Confirm the mechanism: orelse else-branch emits `assign join_temp = null_val` unconditionally (`lower.zig:3584`) BEFORE checking `block_terminated` (`:3586`), so a terminated plain-block RHS (`orelse { return null; }`) yields a void temp that's referenced but never declared (`'zT_<n>' undeclared`). Compare against the catch arm (checks block_terminated first — GREEN) and the F-ORELSE direct-terminator guard (only handles direct return/continue/break RHS, not block RHS).

- [ ] **Step 2: Pin the fix design** (AMENDMENT 3: operator ruled Fix A — mirror the catch arm's ordering: guard the join materialize+assign on `block_terminated == 0` for ALL RHS. Fix B, the block-RHS-only scoped guard, REJECTED as incomplete. Fix A also closes the `orelse unreachable` first-param leak; reviewer verified zero baselines change, runtime-identical.)

Name the exact site + change shape. Reason byte-identity: the 5 sites are gcc-invalid today → fix fires only on failing programs → no re-baseline expected (Fix A additionally verified: no gate/corpus emits `orelse unreachable`).

- [x] **Step 3: STOP on fork if two valid fixes exist**

Two valid fixes (Fix A catch-arm mirror, Fix B scoped block guard) with different byte-identity implications were identified and PRESENTED to the operator; operator ruled **Fix A** (AMENDMENT 3, 2026-08-24).

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-IORELSEBLK-r2r1-report.md`. No commit.

---

### Task F-ORELSEBLK: apply orelse-block terminator fix — AMENDMENT 2/3

**Files:**
- Modify: `sf/src/lower.zig` (orelse_expr arm — Fix A: mirror the catch arm's ordering; guard the join materialize+assign on `block_terminated == 0` for ALL RHS)
- Report: `.superpowers/sdd/task-FORELSEBLK-r2r1-report.md`

**Consumes:** I-ORELSEBLK report. **Produces:** `emission_orelse_block_xmod` GREEN + the 5 residual orelse-block sites closed + re-count. **AMENDMENT 3 (operator ruling, 2026-08-24): Fix A is the pinned design** — mirror the catch arm's ordering: the join-assign must be emitted only when `block_terminated == 0` (catch arm at `lower.zig:3546-3550` checks the flag BEFORE materialize/assign; orelse arm currently assigns unconditionally at `:3594` then checks at `:3596`). Fix A also closes the `orelse unreachable` first-param leak. Byte-identity (reviewer-verified): no gate/corpus baseline emits `orelse unreachable`; the removed dead line is overwritten on the ok path → runtime-identical → zero baselines change, no re-baseline. Fix B (scoped block-RHS-only guard) REJECTED by operator as incomplete.

- [ ] **Step 1: Apply the fix** (per I-ORELSEBLK Fix A, `edit`/`fastedit`)
- [ ] **Step 2: Rebuild + reinstall std**
- [ ] **Step 3: `emission_orelse_block_xmod` GREEN + prior fixtures still GREEN**
- [ ] **Step 4: Re-count (observational)** — record orelse-block `zT_<n> undeclared` count (target 0) + full class split
- [ ] **Step 5: Runtime-identity gate** — 4 MD5s + matrix 21/21
- [ ] **Step 6: Commit**

Commit: `fix: orelse block terminator emits no void temp assign (zT undeclared, 5 errors)`

---

### Task R-R1: Opt_10 fixture

**Files:**
- Create: `repro/mi_matrix/emission_opt10_assign_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-RR1-r2r1-report.md`

**Consumes:** the verified R1 mechanism (`zT_970 = rt` where `rt` is `Opt_10`-typed optional, lower.zig:1501 `resolvedTypeTableGet` result). **Produces:** RED fixture reproducing `incompatible types … unsigned int ← Opt_10`.

- [ ] **Step 1: Identify the minimal trigger**

From lower.c:31469 (`ft = zT_968`, R1-family), determine the minimal Zig construct whose lowering assigns an `Opt_10`-typed optional to an `unsigned int` temp.

- [ ] **Step 2: Write the fixture + verify RED**

RED must be `incompatible types when assigning to type 'unsigned int' from type 'zT_BAEE192E_Opt_10'` (byte-identical). NOTES.md per convention.

- [ ] **Step 3: Commit**

Commit: `repro: self-compile 194-error fixture (Opt_10 assign)`

---

### Task I-R1: investigate Opt_10 (read-only)

**Files:**
- Read: `sf/src/lower.zig` (lower.zig:1501 `resolvedTypeTableGet` bindOptionalCapture/expr path, optional handling), `sf/src/semantic_analyzer.zig`
- Create: `.superpowers/sdd/task-IR1-r2r1-report.md` (report, no commit)

**Consumes:** R-R1 fixture + lower.c:31469. **Produces:** pinned upstream fix design.

- [ ] **Step 1: Trace the Opt_10 leak**

Determine where the optional-typed value is assigned into an `unsigned int` temp (the `ft = zT_968` site) — whether the temp type should be the optional's payload or the assign is misplaced.

- [ ] **Step 2: Pin the fix design + byte-identity reasoning**

Name the exact site + change shape; reason byte-identity (gcc-clean gates unaffected).

- [ ] **Step 3: STOP on fork if two valid fixes exist**

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-IR1-r2r1-report.md`. No commit.

---

### Task F-R1: apply Opt_10 fix

**Files:**
- Modify: the file(s) named by the I-R1 report
- Report: `.superpowers/sdd/task-FR1-r2r1-report.md`

**Consumes:** I-R1 report. **Produces:** R1 fixture GREEN + re-count.

- [ ] **Step 1: Apply the fix** (per I-R1, `edit`/`fastedit`)
- [ ] **Step 2: Rebuild + reinstall std**
- [ ] **Step 3: R1 fixture GREEN + prior fixtures still GREEN**
- [ ] **Step 4: Re-count (observational)** — record `incompatible types … Opt_10` count (target 0) + full class split
- [ ] **Step 5: Runtime-identity gate** — 4 MD5s + matrix 21/21
- [ ] **Step 6: Commit**

Commit: `fix: Opt_10 incompatible assign (1 error)`

---

### Task R-ACOPY: array-copy direct-assign fixture (verify)

**Files:**
- Verify: `repro/mi_matrix/emission_array_copy_xmod/` (created by A-ADD as the §5.1 array-copy live-RED shape — AMENDMENT 1 ruling (b): A-ADD writes all 4 live-RED shapes; R-ACOPY VERIFIES the array-copy fixture, it does NOT create its own)
- Report: `.superpowers/sdd/task-RACOPY-r2r1-report.md`

**Consumes:** the A-ADD array-copy fixture + the live misc residual (A-ANALYZE §5.1: `emission_misc_xmod` fails on `assignment to expression with array type` at `fb = src;` + co-occurring `'zT_<n>' undeclared`; root = the array-copy `.assign`/`.store_local` path emits BOTH the bogus direct `dst = src;` line AND the correct copy loop `dst[_i] = src[_i];`, `c89_emit.zig`). **Produces:** verified RED fixture reproducing the exact array-copy direct-assign class.

- [ ] **Step 1: Confirm the A-ADD array-copy fixture is RED**

Re-run the A-ADD `emission_array_copy_xmod` fixture: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir <dir> <main.zig>` then `cd <dir> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: `error: assignment to expression with array type` at the direct-assign line (byte-identical class to the misc residual). If it is GREEN or fails differently, STOP and present.

- [ ] **Step 2: Confirm the NOTES.md pins the array-copy root cause**

Verify NOTES.md states: root cause (the array-copy `.assign`/`.store_local` path emits both the bogus `dst = src;` line AND the correct copy loop), RED evidence, expected post-fix. Correct only if A-ADD's NOTES is materially wrong (minor wording) — otherwise leave verbatim.

- [ ] **Step 3: Commit (only if the fixture needed correction)**

If the fixture had to be corrected/re-verified to a byte-identical class, commit: `repro: self-compile 194-error fixture (array-copy direct assign)`. If it already matched A-ADD's committed state byte-identical, no commit — report only.

---

### Task I-ACOPY: investigate array-copy direct-assign (read-only)

**Files:**
- Read: `sf/src/c89_emit.zig` (array-copy emission in `.assign`/`.store_local` — where `dst = src;` AND `dst[_i] = src[_i];` both emit), `sf/src/lower.zig` (array-copy lowering)
- Create: `.superpowers/sdd/task-IACOPY-r2r1-report.md` (report, no commit)

**Consumes:** R-ACOPY fixture + the live misc residual. **Produces:** pinned upstream fix design.

- [ ] **Step 1: Trace the double emission**

Determine where the direct `dst = src;` assignment is emitted in addition to the copy loop — identify the emitter site and why both forms are produced (a fall-through path, an unconditional direct-assign before a loop, etc.).

- [ ] **Step 2: Pin the fix design**

Name the exact site + change shape. Reason byte-identity: gates/corpus have no such array-copy direct-assign today (they're gcc-clean) → fix fires only on failing programs → no re-baseline expected.

- [ ] **Step 3: STOP on fork if two valid fixes exist**

If the fix has two valid resolutions with different byte-identity/correctness implications, present and STOP.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-IACOPY-r2r1-report.md`. No commit.

---

### Task F-ACOPY: apply array-copy direct-assign fix

**Files:**
- Modify: the file(s) named by the I-ACOPY report
- Report: `.superpowers/sdd/task-FACOPY-r2r1-report.md`

**Consumes:** I-ACOPY report. **Produces:** ACOPY fixture GREEN + misc fixture GREEN + re-count.

- [ ] **Step 1: Apply the fix** (per I-ACOPY, `edit`/`fastedit`)
- [ ] **Step 2: Rebuild + reinstall std**
- [ ] **Step 3: ACOPY fixture GREEN + misc fixture GREEN + prior fixtures still GREEN**
- [ ] **Step 4: Re-count (observational)** — record array-copy class count (target 0) + full class split
- [ ] **Step 5: Runtime-identity gate** — 4 MD5s + matrix 21/21
- [ ] **Step 6: Commit**

Commit: `fix: array-copy direct assign emits no bogus dst = src (array copy)`

---

### Task GATE-FINAL: final sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATEFINAL-r2r1-report.md`

**Consumes:** F-R2/F-R1/F-ACOPY results. **Produces:** reconciled docs; milestone record if self-compile gcc-clean.

- [ ] **Step 1: Final gate sweep**

4 MD5s byte-identical, matrix 21/21, **corpus 310 (re-baselined from 303 — AMENDMENT 1: +7 new 194-plan fixture dirs; pal classifies green-guard via `error[20]` reject)**, `test_analyzer_bin` "5 passed, 4 failed". Record final self-compile re-count.

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + closeout section: R2/R1 fixes + final re-count. If 12→0, record the **self-compile gcc-clean milestone**.

- [ ] **Step 3: Update QUICK_REF.md**

Post-closeout baseline paragraph.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile residual closeout GATE + reconciliation`
