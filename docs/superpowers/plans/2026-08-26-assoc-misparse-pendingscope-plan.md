# Assoc-Chain Misparse (Self-Compile) + pending_scope Nest-Safety — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** (A) find and fix the self-emission defect that makes the self-compiled `zig1_5` mis-parse left-associative operator chains (`a-b-c` → `a-(b-c)`); (B) make the B3b scope-chain `pending_scope` slot nest-safe.

**Architecture:** Phase A reproduces the reversal with a runtime fixture, diffs the self-emitted parser against the reference emission, pins the single mis-emitted construct, and fixes it. Phase B pins and applies a nest-safe pending-scope design. **AMENDMENT 4 (operator-ruled 2026-08-26):** Phase B fix = **option (c) — reorder the for-range lowering** (move the capture-add + `decl_local` to AFTER the end-expr lower, eliminating the pending-scope window entirely). The LIFO-stack + fresh/reuse + boundary-low-watermark design was REJECTED as patchy (operator: "this again just bloats with a patch"). Correctness governs; byte-identity is not required for Phase B (though the reorder is in fact MD5-neutral for the 4 gates — gol/lisp/mud have no for-loops and json uses only for-slice, so no gate program hits the reordered for-range path).

**Tech Stack:** Zig (sf/src), C89 (emitted code), gcc -m32, bash (build scripts).

## Global Constraints

- Compiler under test `/tmp/fx_subfolder/zig1`; rebuild = `bash sf/scripts/build_release.sh` from REPO ROOT (CWD-relative `src/bootstrap/`; from sf/ it fails) — gate `=== [release] Done ===`. Rebuild WIPES `/tmp/fx_subfolder/lib` — reinstall std: `mkdir -p /tmp/fx_subfolder/lib && cp sf/src/{std.zig,std_io.zig,std_arena.zig,std_net.zig} /tmp/fx_subfolder/lib/`.
- **No `sf/src` fixes outside the plan's pinned loci.** Never touch `sf/build/out_release/` (WEDGED).
- Byte-identity gates (QUICK_REF, authoritative after AMENDMENT 3): gol `eed963e0640a073ed4eebb292f136e05`, lisp `c3c5847798e4553b2e34950e085bb6c6` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Must remain byte-identical unless the operator rules a re-baseline; fixtures are new-only.
- Correctness bar = RUNTIME behavior (program prints the expected value), not byte-parity vs zig0.
- Compile recipe: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 X.zig`; multi-module `gcc -m32 -std=c89 -c` INSIDE output dir with absolute `-I /workspace/znineeight/sf/src/include`; link `sf/src/include/zig_runtime.c` + `sf/src/include/zig_pal.c`.
- Z98 dialect for all probe/fixture `.zig`: no anytype/@Type; `@intCast` for int casts; `switch` requires `else`; no method syntax; no pointer captures.
- Editing discipline: `edit`/`fastedit` only; re-read region before each edit; edit bottom-to-top; never `end_line=start_line-1`; insert via replacing an anchor line.
- Markers extract with `grep -a`, never `strings`.
- Enforce `timeout 120` on ALL compiler/binary invocations (`timeout 900` for build_release.sh / build_zig1_5.sh).
- Ledger: append one line per completed task to `.superpowers/sdd/progress.md`. Memory: `mnemoria --path .opencode/memory add --agent r2r1-session --type <discovery|decision|bugfix|problem|pattern> --summary "..." "..."` per task.
- Reports to `.superpowers/sdd/task-<N>-report.md` (gitignored). WARNING: `.superpowers/sdd/task-1-report.md` is TRACKED and holds an unrelated prior report — never reuse that exact name; use descriptive names like `task-ASSOC-report.md`.
- Self-compiled build: `scripts/self_compile/build_zig1_5.sh` → `/tmp/zig1_5/{zig1_5_asan,zig1_5_clean,lib/,gen/}`.
- Reference emission: `/tmp/ref_zig1.c` (zig0 concat) AND `/tmp/fx_subfolder/*.c` (the actual emission that built the working zig1 — this is the authoritative reference for self-emission diffs).
- Pre-plan self-compiled binary proving R-1 pre-existing: `/tmp/zig1_5_fixed` (built at `5ec13efb`).

---

### Task R-ASSOC: runtime fixture for the associativity reversal

**Files:**
- Create: `repro/mi_matrix/emission_assoc_chain_xmod/{main.zig,NOTES.md}`
- Commit: `repro: left-associative chain misparse fixture (self-compiled compiler)`

**Interfaces:**
- Consumes: the R-1 finding (self-compiled zig1_5 right-nests left-assoc chains).
- Produces: committed RED fixture; reference correct vs self-compiled wrong documented.

- [ ] **Step 1: Write minimal `.zig`**

A main that computes same-precedence left-assoc chains and prints the results. Use values where left vs right assoc differ observably: `10 - 4 - 3` = 3 (left) vs 9 (right); `100 / 10 / 2` = 5 vs 20; `1 + 2 + 3` = 6 (same either way — use `-`/`/`); `2 * 3 * 4` = 24 (same). Print via `std.io.printInt` per chain. Include `1 + 2 - 3` (mixed additive, = 0) and a `printInt`-style digit-reversal case if feasible (`-`/`/` on an int). Z98-clean.

- [ ] **Step 2: Verify reference vs self-compiled**

Reference: `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig` (CWD fixture dir) → rc=0; gcc -c (in output dir, `-I /workspace/znineeight/sf/src/include`) rc=0; link + run rc=0, prints the LEFT-assoc values (e.g. `3`, `5`, `0`).
Self-compiled: rebuild zig1_5 via `scripts/self_compile/build_zig1_5.sh` if stale; `timeout 120 /tmp/zig1_5/zig1_5_clean --dump-c89 main.zig` (mkdir output dir first) → rc=0; gcc/link/run → prints the RIGHT-assoc values (e.g. `9`, `20`, `0` or wrong) — RED.

- [ ] **Step 3: NOTES.md + commit**

Convention: purpose / verbatim source / RED evidence (ref correct output vs self-compiled wrong output, both rc=0) / root-cause status (self-emission fidelity gap, R-1; root not yet traced) / expected post-fix.

- [ ] **Step 4: Report + ledger + memory**

Report to `.superpowers/sdd/task-ASSOC-report.md` (gitignored): fixture, both outputs, commit. Ledger + mnemoria (discovery).

---

### Task I-ASSOC: trace the self-emission defect (read-only)

**Files:**
- Report: `.superpowers/sdd/task-ASSOC-report.md` (append; read-only investigation section)

**Interfaces:**
- Consumes: R-ASSOC fixture; self-compiled gen/ `parser_*.c`; reference `/tmp/fx_subfolder/parser.c` + `/tmp/ref_zig1.c`.
- Produces: pinned single-locus root cause file:line, OR STOP-present if broad class.

- [ ] **Step 1: Reproduce + capture**

Run the R-ASSOC fixture through reference (correct) and self-compiled (wrong); capture outputs. Then dump the self-compiled parser source via `--dump-ast` on a `a-b-c` input if supported (or use emitted-C inspection).

- [ ] **Step 2: Diff self-emitted parser vs reference**

Compare the SELF-EMITTED `gen/parser_<hash>.c` (esp. `parserParseExprPrec` body + `getInfixInfo` + `OpInfo` struct layout) against the reference `/tmp/fx_subfolder/parser.c` (the emission that built the working zig1) and/or `/tmp/ref_zig1.c`. Normalize mangler noise (zig0 double-hash lowercase vs zig1 single-hash uppercase). Find the construct zig1 mis-emits: candidates are (a) `OpInfo.right_assoc` bool field emission/init (true/false flipped), (b) the `if (info.right_assoc) ... else ...` branch inversion, (c) the `?OpInfo` optional-return unwrap, (d) `precToInt`/`precFromInt`/`next_min = prec + 1` arithmetic, (e) the `Prec` enum(u8) ordinal table.

- [ ] **Step 3: Trace to emission site + verify**

Map the divergent C back to its Zig source construct; record `file:line` + emission pattern. Confirm the defect is in the self-EMITTED parser (not the lowering of programs): the reference compiler parses `a-b-c` correctly, and the base zig1 compiles programs correctly — only the SELF-emitted parser's precedence logic is wrong.

- [ ] **Step 4: Single-locus vs broad class**

Single pin-able emission defect → pin F locus. Broad class → STOP-present.

- [ ] **Step 5: Report + ledger + memory**

Append the investigation to `.superpowers/sdd/task-ASSOC-report.md`. Ledger + mnemoria (discovery).

---

### Task F-ASSOC: apply the pinned fix

**Files:**
- Modify: the pinned `sf/src/*.zig` locus (single file/locus)
- Fixture: `emission_assoc_chain_xmod` RED→GREEN
- Commit: `fix: self-emitted parser no longer reverses left-assoc operator chains` (adjust wording to actual locus)

**Interfaces:**
- Consumes: I-ASSOC pinned locus.
- Produces: self-compiled zig1_5 parses `10-4-3`=3 and digit-reversal correct; 4 MD5s byte-identical; matrix 21/21.

- [ ] **Step 1: Apply the fix**

Per I-ASSOC's pinned locus, modify the single `sf/src` file. Z98-clean. Do NOT chase additional defects if I-ASSOC STOP applied.

- [ ] **Step 2: Gate verification**

Rebuild zig1 (repo root, reinstall std). Rebuild zig1_5. R-ASSOC fixture: reference rc=0 prints 3 (unchanged) AND self-compiled rc=0 now prints 3 (was 9) — GREEN; `printInt`-digit-reversal case correct. 4 MD5s byte-identical (gol `eed963e0…`, lisp `c3c58477…` repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`). Matrix 21/21. Self-compile re-count 0 errors.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit verbatim. Report (append to task-ASSOC-report.md): fix summary, gate evidence, commit. Ledger + mnemoria (bugfix).

---

### Task I-PENDSCOPE: pin the nest-safe pending_scope design (read-only)

**Files:**
- Report: `.superpowers/sdd/task-PENDSCOPE-report.md` (gitignored)

**Interfaces:**
- Consumes: I-1 finding (single `pending_scope` slot, for-range-end capture orphaning); B3b scope-chain code (lower.zig:316-339, :416, :555, :798, :824, :4189).
- Produces: pinned nest-safe design (**AMENDMENT 4: option (c) reorder**).

- [ ] **Step 1: Verify the hole**

Reproduce the I-1 shape if feasible: `for (0..if (rt) |x| x else 0) |t|` — a capture inside the range-end expr consuming the loop capture's pending scope. If no clean repro compiles, trace the code path in lower.zig (for-range lowering ~:4800-4830: capture add → end-expr lower → body scope push) and confirm the single-slot reuse. **AMENDMENT 4 note:** the I-1 verification (done 2026-08-26) confirmed the hole empirically — the end-expr capture (`x`) and loop capture (`t`) are at the SAME depth `D+1`; a depth-keyed map (option b) collapses them exactly like the single slot, so option (b) does NOT fix the hole. Only a mechanism that distinguishes sibling scopes at equal depth works.

- [ ] **Step 2: Design the fix**

**AMENDMENT 4 (operator-ruled): option (c) — reorder the for-range lowering.** The for-range is the ONLY site with a pending-scope window: `sf/src/lower.zig:4821` (capture-add + `decl_local t = start`) → `:4823` (`end_temp = lowerExpr(pattern.child_1)`) → body push via `lowerStmtBody` (`:4838`). Every other capture site (if/while `:1585/:1587`, switch prongs `:4168/:4172`, for-slice `:4891/:4892`) adds its capture immediately before its own `pushScopeDepth` — no window. Move the `:4821` capture-add block (maybeDisambiguateCapture + addLocalDecl + decl_local) to AFTER `end_temp = lowerExpr(self, pattern.child_1)` (`:4823`). This eliminates the pending-scope window entirely — NO stack, NO fresh/reuse selector, NO boundary low-watermark. It fixes BOTH the capture-in-end-expr case AND the capture-less end-expr case (`for (0..if (rt) 1 else 0) |t|`), which the stack design still orphaned. Semantically transparent: `t = start` is a pure prologue binding; the end-expr computation does not touch `t` or `start`. Only the emitted byte ORDER of the `decl_local` changes (moved after the end-expr's instructions) — allowed, correctness governs (AMENDMENT 4).

- [ ] **Step 3: Correctness + gate evaluation**

For the chosen reorder, verify by reasoning + spot measurement: (1) the I-1 repro now emits `total + t` (direct capture use, not `zT = t` load_local fallback); (2) the capture-less end-expr shape is fixed too; (3) gate impact — the 4 MD5 programs are unaffected (gol/lisp/mud: no for-loops; json: for-slice only, which is untouched) so the 4 gates stay byte-identical; matrix 21/21; self-compile re-count 0 errors. Pin the exact F locus: `sf/src/lower.zig:4821-4823` reorder.

- [ ] **Step 4: Report + ledger + memory**

Report: hole verification, option (c) design + rationale (vs rejected (a)/(b)/stack+watermark), pinned F locus + gate impact. Ledger + mnemoria (discovery/decision).

---

### Task F-PENDSCOPE: apply the nest-safe fix

**Files:**
- Modify: `sf/src/lower.zig` (for-range reorder, ~:4821-4823)
- Commit: `fix: pending_scope nest-safe (for-range capture after end-expr)`

**Interfaces:**
- Consumes: I-PENDSCOPE pinned design (AMENDMENT 4: option (c) reorder).
- Produces: pending_scope nest-safe (reorder); 4 MD5s byte-identical (gate programs have no for-range, so the reorder is byte-neutral for them); matrix 21/21.

- [ ] **Step 1: Apply the fix**

Per I-PENDSCOPE's pinned design (AMENDMENT 4), modify `sf/src/lower.zig`: in the for-range branch, move the capture-add block (`maybeDisambiguateCapture` + `addLocalDecl` + `decl_local`) from its current position at `:4821` (before `end_temp = lowerExpr(self, pattern.child_1)`) to AFTER the end-expr lower at `:4823`. Do NOT touch the for-slice captures (`:4891/:4892`) or any other scope-chain code. Z98-clean; `edit`/`fastedit` only.

- [ ] **Step 2: Gate verification**

Rebuild zig1 (repo root, reinstall std). The I-1 repro `for (0..if (rt) |x| x else 0) |t|` must now emit direct capture use (`total + t`, not `zT = t` load_local fallback). 4 MD5s byte-identical (gol `eed963e0…`, lisp `c3c58477…` repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`). Matrix 21/21. Self-compile re-count 0 errors. Re-run the R-ASSOC fixture + B1 `emission_lower_crash_xmod` (reference + self-compiled rc=0) to confirm no regression from B3a/B3b.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit verbatim. Report: fix summary, gate evidence, commit. Ledger + mnemoria (bugfix).

---

### Task GATE-FINAL: full sweep + reconciliation

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` + `docs/sf/QUICK_REF.md`
- Commit: `docs: assoc-chain + pending_scope plan GATE + reconciliation`

**Interfaces:**
- Consumes: F-ASSOC + F-PENDSCOPE results.
- Produces: reconciled docs; both residuals closed (or documented).

- [ ] **Step 1: Full sweep**

4 MD5s byte-identical (gol `eed963e0…`, lisp `c3c58477…` repo-root CWD, json `089e4f04…`, mud `a1d0dd55…`); matrix 21/21; corpus re-count; self-compile re-count 0 errors; self-compiled zig1_5 runs R-ASSOC fixture (prints left-assoc values) + a real std-importing program rc=0.

- [ ] **Step 2: Reconcile docs**

EXPECTED_FAIL: record R-1 (assoc-chain, F-ASSOC SHA) + I-1 (pending_scope, F-PENDSCOPE SHA) resolutions; remove/downgrade the two residuals. QUICK_REF: post-plan baseline paragraph + corpus-gate header refresh.

- [ ] **Step 3: Commit + report + ledger + memory**

Commit verbatim. Report + ledger + mnemoria.

---

## Self-Review (controller, before execution)

- **Spec coverage:** Phase A → R-ASSOC/I-ASSOC/F-ASSOC; Phase B → I-PENDSCOPE/F-PENDSCOPE; both → GATE-FINAL. All acceptance criteria covered.
- **Placeholder scan:** all steps carry exact commands/expected output; no TBD.
- **Type consistency:** artifact paths stable (`/tmp/fx_subfolder/zig1`, `/tmp/zig1_5/zig1_5_clean`, `/tmp/ref_zig1.c`, `/tmp/fx_subfolder/parser.c`); fixture dir per convention.
