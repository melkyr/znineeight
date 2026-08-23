# Self-Compile 194-Error Closeout + R2/R1 Residual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close out the 194-error self-compile plan, extend solved fixtures for analogous valid-Zig shapes, and fix the final 12 self-compile gcc errors (R2 `zT_<n>` undeclared ×11 + R1 Opt_10 ×1) via R/I/F.

**Architecture:** Ten-task sequence — GATE-CLOSE (docs) → A-ANALYZE (read-only) → A-ADD (fixtures) → R-R2/I-R2/F-R2 → R-R1/I-R1/F-R1 → GATE-FINAL. Soft gate: fixture GREEN + no regression is hard; self-compile re-count observational.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, 4 MD5 gates, matrix 21/21, corpus 303.

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

- [ ] **Step 1: Write one fixture per ADD verdict**

Follow the established `emission_*_xmod` convention (full-graph 3+ modules where scale matters, `std.io.printInt` main, NOTES.md with purpose + verbatim fixture + RED evidence + root-cause pin + expected post-fix).

- [ ] **Step 2: Verify RED on each**

Run: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir <dir> <main.zig>` then `cd <dir> && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: same gcc error class as the solved fixture it mirrors. If a shape turns out to be GREEN (no error), record it as a control in NOTES.md (do NOT force a wrong class).

- [ ] **Step 3: Commit**

Commit: `repro: emission fixture extension (analogous-shape variants)`

---

### Task R-R2: zT temp-index drift fixture

**Files:**
- Create: `repro/mi_matrix/emission_temp_index_drift_xmod/{main.zig,mod_a.zig,mod_b.zig,NOTES.md}`
- Report: `.superpowers/sdd/task-RR2-r2r1-report.md`

**Consumes:** the verified R2 mechanism (cross-function hoisted-temp index drift, `zT_N` referenced in fn B but declared in fn A at `zT_N+1000`). **Produces:** RED fixture reproducing the exact `zT_<n> undeclared … did you mean zT_<n+1000>?` class.

- [ ] **Step 1: Identify the minimal trigger**

From the 11 residual sites (c89_emit ×6, import_resolver ×2, main ×1, module_registry ×2), determine the minimal Zig construct whose lowering produces a cross-function temp-index drift (two functions where fn B references a temp that fn A declares at an offset index). Mirror the observed shape (e.g., a function with a large hoisted-temp set whose index collides with a later function's reference).

- [ ] **Step 2: Write the fixture + verify RED**

Full-graph 3+ modules; RED must be `'zT_<n>' undeclared … did you mean 'zT_<m>'?` (m = n + offset), byte-identical class to the residual. NOTES.md: purpose, verbatim fixture, RED evidence, root-cause hypothesis (temp-index drift), expected post-fix.

- [ ] **Step 3: Commit**

Commit: `repro: self-compile 194-error fixture (zT temp-index drift)`

---

### Task I-R2: investigate temp-index drift (read-only)

**Files:**
- Read: `sf/src/c89_emit.zig` (emitHoistedDecls + temp numbering/name emission), `sf/src/lower.zig` (nextTemp / hoisted_temps), `sf/src/lir.zig`
- Create: `.superpowers/sdd/task-IR2-r2r1-report.md` (report, no commit)

**Consumes:** R-R2 fixture + the 11 residual sites. **Produces:** pinned upstream fix design.

- [ ] **Step 1: Trace the drift**

Determine where the hoisted-temp index/name for fn B's reference is computed vs where fn A's declaration is emitted — identify why fn B's reference `zT_N` doesn't match fn A's declared `zT_N+1000`. Check `nextTemp`/`hoisted_temps` reset-per-function semantics and the emitted-name derivation.

- [ ] **Step 2: Pin the fix design**

Name the exact site + change shape. Reason byte-identity: gates/corpus have no such drift today (they're gcc-clean) → fix fires only on failing programs → no re-baseline expected.

- [ ] **Step 3: STOP on fork if two valid fixes exist**

If the fix has two valid resolutions with different byte-identity/correctness implications, present and STOP.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-IR2-r2r1-report.md`. No commit.

---

### Task F-R2: apply temp-index drift fix

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

`bash scripts/self_compile/build_zig1_5.sh` + gcc -c → record `zT_<n> undeclared` count (target 0; may be less/greater if new sites surface — record, don't chase beyond the plan). Record full class split.

- [ ] **Step 5: Runtime-identity gate**

4 MD5s (gol `4afb203f…`, lisp `5f886646…` repo-root CWD, json `d31e43b1…`, mud `a1d0dd55…`) + matrix 21/21. Byte-diff runtime-identical → re-baseline; any doubt → STOP.

- [ ] **Step 6: Commit**

Commit: `fix: hoisted temp index drift (zT undeclared, 11 errors)`

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

### Task GATE-FINAL: final sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATEFINAL-r2r1-report.md`

**Consumes:** F-R2/F-R1 results. **Produces:** reconciled docs; milestone record if self-compile gcc-clean.

- [ ] **Step 1: Final gate sweep**

4 MD5s byte-identical, matrix 21/21, corpus 303 unchanged, `test_analyzer_bin` "5 passed, 4 failed". Record final self-compile re-count.

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + closeout section: R2/R1 fixes + final re-count. If 12→0, record the **self-compile gcc-clean milestone**.

- [ ] **Step 3: Update QUICK_REF.md**

Post-closeout baseline paragraph.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile residual closeout GATE + reconciliation`
