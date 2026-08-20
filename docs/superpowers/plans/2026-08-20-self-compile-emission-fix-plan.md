# Self-Compile C-Emission Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5 C-emission defect classes so `zig1` produces a compilable `zig1_5` (self-compiled compiler): `build_zig1_5.sh` completes with 0 gcc errors, both binaries smoke on hello, and the 4 MD5 + corpus 287 + matrix 21/21 byte-identity gate holds.

**Architecture:** D → R → I → I-E → F-A..F-E → GATE pipeline. D maps the 5 error classes to root causes (read-only); R builds one minimal RED fixture per independent root cause; I pins the upstream-correct fix per root cause (read-only, STOP on design forks); **I-E pins the E1 design + triages the class-1b residual (read-only, AMENDMENT 1)**; **F is split into F-A..F-E — one fix task per root cause (AMENDMENT 1)**; GATE reconciles docs.

> **OPERATOR RULING (2026-08-20, AMENDMENT 1):** (1) Lower.zig fixes are approved — "I don't have a concern if the files are different from the plan"; root causes C (C1) and E (E1) are fixed in `lower.zig` as their upstream-correct location. (2) An I-E follow-up task pins E1's which-variant-payload derivation (the I report left a `<variant payload type_id>` placeholder) and triages the 202 class-1b errors into shapes before any F-E code. (3) F is split into F-A, F-B, F-C, F-D, F-E — one per root cause, each independently gated + reviewed. (4) A1 (kind-G module-independent mangle key) accepted, with an F-A grep gate for same-named user globals. E2 (emitter `int zT_n` fallback) rejected as a patch. C2 (emitter name+type dedup) rejected in favor of C1.

> **OPERATOR RULING (2026-08-20, AMENDMENT 2):** I-E findings accepted (option a). F-E re-scoped to three parts: **E1** (bindOptionalCapture tagged-union branch — latent-correct, first-non-void-variant derivation), **E1c** (variant-payload field access `inst.<variant>.<field>` — the dominant class-1b producer, root `semantic_analyzer.zig:607` + `lower.zig:2450-2458`, ~115 errs), and **tag-test** (if (union.field) compares runtime tag vs variant index, `lower.zig:4225-4237` — required for the R fixture to print 7). F-E runs AFTER F-A and F-C (their ~68 class-1b errors collapse first); it re-measures the class-1b residual before the full self-compile gate.

**Tech Stack:** Z98 compiler (`sf/src/*.zig`), compiler under test `/tmp/fx_subfolder/zig1`, gcc -m32 -std=c89, `bash sf/scripts/build_release.sh`, 4 MD5 gates, corpus 287, matrix 21/21.

## Global Constraints

- **Emission-only.** Zero memory (AST-spill/16 MB) work; zero determinism/runtime/memory (correctness-plan T3-T6) work. Fix scope: `sf/src/c89_emit.zig` (A, B, D) and `sf/src/lower.zig` (C1, E1) per AMENDMENT 1 — no other files.
- **Hard byte-identity gate:** 4 MD5s byte-identical — gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3` (repo-root CWD), json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. Corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`. Matrix 21/21.
- **Runtime-priority override:** if a fix changes an MD5 but the emitted C is still correct AND runtime-identical, STOP and report to operator + propose a re-baseline. If MD5 changes with any runtime/correctness doubt, STOP without proposing.
- **`sf/build/out_release/` is WEDGED — NEVER touch/list/build into it.** All compiler runs `timeout 120`.
- **Build:** `bash sf/scripts/build_release.sh` → gate `=== [release] Done: /tmp/fx_subfolder/zig1 ===`; then reinstall std: `cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/`.
- **Editing:** `edit`/`fastedit` only (AGENTS.md §X.7: re-read region before each edit, bottom-to-top; fastedit: re-read after every edit, never `end_line = start_line - 1`).
- **Z98 constraints** (AGENTS.md §1.3): no anytype/@Type; concrete maps; `@intCast` for i32↔usize; switch requires `else`.
- **The plan is the ONLY authority.** STOP on any issue/confusion. Do not fix anything outside the 5 classes.
- **Commit messages verbatim per task.**

---

### Task D: discovery — map 5 error classes to root causes

**Files:**
- Read: `sf/src/c89_emit.zig` (emitter), `sf/src/lir.zig`, `sf/src/lower.zig` (as needed to trace)
- Create: `.superpowers/sdd/task-D-emission-report.md` (report, read-only — no commit)

**Consumes:** the 5-class table in the spec. **Produces:** `class → root-cause → emitter-site` map + which classes share a root cause + which classes are self-compile-only vs latent-in-corpus.

- [ ] **Step 1: Regenerate the failed build, capture per-class error list**

Run: `bash scripts/self_compile/build_zig1_5.sh` — expected to FAIL at `gcc -c` (rc=1). Then run:

```bash
cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2> /tmp/emit_errs.txt; echo "rc=$?"
```

- [ ] **Step 2: Bucket every error into its class**

For each of the 5 classes, count errors and collect representative `file:line` examples + the exact emitted-C text + the mangled identifier involved. Verify the counts are stable vs the T2 baseline (1195 errors / 16 files; class 1 ~190, class 2 ~200, class 5 = 9).

- [ ] **Step 3: Trace each class to its emitter site**

For class 1 (`zG_` enum globals): identify where enum constants are referenced as globals (kind-1 mangling, `nameManglerMangle` `c89_emit.zig:400-475`) vs where their definition SHOULD be emitted but isn't. Grep `c89_emit.zig` for the enum-constant emission path and the `.enum_const => |ec|` arms (`:2672`, `:5058`). For classes 2-5, trace the corresponding temp-decl / anon-type / payload / void-as-value emission sites.

- [ ] **Step 4: Determine shared vs distinct root causes**

Write the report with a `class → root-cause → site(s)` table, marking which classes are distinct root causes and which are the same bug. This table drives the R-task fixture count (one fixture per *independent* root cause).

- [ ] **Step 5: Write report**

Report at `.superpowers/sdd/task-D-emission-report.md`. No commit (read-only).

---

### Task R: repro — one RED fixture per root cause

**Files:**
- Create: `repro/mi_matrix/<name>_xmod/{main.zig,NOTES.md}` (one dir per independent root cause, named per the D report)
- Report: `.superpowers/sdd/task-R-emission-report.md`

**Consumes:** D report (root-cause list). **Produces:** RED fixtures — each minimal input that reproduces its class's bad C emission under the current `/tmp/fx_subfolder/zig1`.

- [ ] **Step 1: For each root cause, write a minimal fixture**

Each fixture is the smallest Z98 program that triggers the class (e.g. for class 1: an enum with many variants, some referenced as compile-time globals; for class 2: a function with enough temps to collide; for class 3: a `switch` producing an anonymous type; for class 4: a tagged-union payload field access; for class 5: a void-fn call in value position). Mirror the existing `xmod` fixture style (see `repro/mi_matrix/widthbits_union_intconst_xmod/`).

- [ ] **Step 2: Verify RED on each fixture**

Run (from the fixture dir where the fixture imports `std`): `timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rfx <fixture main.zig>` then `cd /tmp/rfx && gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c`. Expected: the same gcc error class as the full self-compile. If a class cannot be reproduced minimally, record it in NOTES.md and report DONE_WITH_CONCERNS (do NOT fake a fixture).

- [ ] **Step 3: Write NOTES.md per fixture**

Each NOTES.md: fixture source, RED evidence (exact gcc error + rc), the root cause it pins, expected post-fix result.

- [ ] **Step 4: Commit**

Commit: `repro: self-compile emission defects (<class-name>_xmod fixtures)`

---

### Task I: investigate — pin the upstream-correct fix per root cause

**Files:**
- Read: `sf/src/c89_emit.zig` (targeted sites from D)
- Create: `.superpowers/sdd/task-I-emission-report.md` (report, read-only — no commit)

**Consumes:** D report + R fixtures. **Produces:** per-root-cause fix design (the correct emitter change, NOT a patch of emitted text), plus STOP if any design fork needs an operator ruling.

- [ ] **Step 1: For each root cause, identify the correct emitter fix**

Design the change in `c89_emit.zig` that makes the emitted C correct (e.g. for class 1: emit the `zG_` enum-constant definition when it is referenced — or stop referencing it as a global and use the existing `zT_` macro). For each, name the exact function/line to change and the shape of the change.

- [ ] **Step 2: Verify the fix would NOT change the 4 MD5s / corpus / matrix**

Reason about whether the fix path is also reachable from any of the 287 corpus dirs or 21 examples. If a fix WOULD change existing-correct output, flag it as a design fork.

- [ ] **Step 3: Flag design forks → STOP for operator ruling**

If any root cause has two valid fixes with different byte-identity risk, present them and STOP. Otherwise proceed.

- [ ] **Step 4: Write report**

Report at `.superpowers/sdd/task-I-emission-report.md`. No commit (read-only).

### Task I-E: pin E1 design + triage class-1b residual (read-only)

**Files:**
- Read: `sf/src/lower.zig:1283-1303` (`bindOptionalCapture`), `sf/src/type_registry.zig`, `sf/src/c89_emit.zig` (as needed)
- Create: `.superpowers/sdd/task-IE-emission-report.md` (report, read-only — no commit)

**Consumes:** I report (E fork). **Produces:** E1 design fully pinned — the which-variant-payload derivation replacing the `<variant payload type_id>` placeholder — plus a class-1b (202) shape triage.

- [ ] **Step 1: Pin the which-variant-payload derivation for E1**

The I report's E1 sketch leaves `<variant payload type_id>` unresolved. Determine, from the emitted C + `bindOptionalCapture` + the type registry, how an `if (union) |v|` capture must derive the payload type (which variant is the non-null/payload variant). Name the exact type-id derivation (type_registry fields, variant-index source). If `if`-capture on a tagged union cannot determine a unique payload variant, document the constraint (e.g. single-payload-variant unions only) and the resulting scope.

- [ ] **Step 2: Triage the 202 class-1b errors by shape**

From `/tmp/emit_errs.txt` (or regenerate via `cd /tmp/zig1_5/gen && gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I /workspace/znineeight/sf/src/include -c *.c 2>/tmp/emit_errs.txt`), bucket the 202 `zT_<n> undeclared` errors: how many are the if-capture family (fixed by E1) vs a second shape (e.g. the int_cast chain `zT_1159 = (unsigned int)zT_1158;`). Report counts + representative sites + whether a second fix (E1b) is needed.

- [ ] **Step 3: Write report + STOP if a second shape needs design**

Report at `.superpowers/sdd/task-IE-emission-report.md`. If a second class-1b shape exists and needs its own design, present it (may extend F-E scope). No commit (read-only).

---


### Task F-A: fix — mangler collision on type storage globals (root cause A)

**Files:**
- Modify: `sf/src/c89_emit.zig:400-476` (kind-G cache key drops `module_id`)
- Report: `.superpowers/sdd/task-FA-emission-report.md`

**Consumes:** I report §A (A1 recommended). **Produces:** `emission_mangler_collision_xmod` GREEN.

- [ ] **Step 1: Apply fix A1**

In `nameManglerMangle` `c89_emit.zig:404`, make the kind-G (storage global) cache key a pure function of `(name_id, kind)` — drop `module_id` for `kind == 1` (per I report §A shape). All other kinds unchanged. Via `edit`/`fastedit` (re-read region, bottom-to-top).

- [ ] **Step 2: Verify no same-named user global across two modules**

Whole-tree scan (I report §A residual): confirm no two modules define the same module-scope `var` name in `sf/src` or the std lib (grep the corpus + self-compile closure). If a real collision exists, STOP and report (re-route to A2).

- [ ] **Step 3: Rebuild + reinstall std**

```bash
bash sf/scripts/build_release.sh
cp sf/src/std.zig sf/src/std_io.zig sf/src/std_arena.zig sf/src/std_net.zig /tmp/fx_subfolder/lib/
```

- [ ] **Step 4: Fixture GREEN + byte-identity gate**

Re-run `emission_mangler_collision_xmod`: dump + gcc -c → 0 errors. Then 4 MD5s byte-identical (gol `9cf758d96f25d41980379564a5501bc8`, lisp `88dcb7f9abf215aa6420f63e0e67e9c3`, json `9720478c937409a29fe23ae0199821cf`, mud `a1d0dd55aada9c3fd904ae33f54de32e`), corpus 287 unchanged, matrix 21/21. If an MD5 changed: check emitted C correct + runtime-identical → STOP + propose re-baseline; else STOP (defect).

- [ ] **Step 5: Commit**

Commit: `fix: mangler kind-G module-independent name (type storage globals)`

---

### Task F-B: fix — local dedup 128-slot cap (root cause B)

**Files:**
- Modify: `sf/src/c89_emit.zig:499` (field), `:531` (init), `:6061-6064` (grow)
- Report: `.superpowers/sdd/task-FB-emission-report.md`

**Consumes:** I report §B. **Produces:** `emission_local_dedup_cap_xmod` GREEN.

- [ ] **Step 1: Apply fix B**

Change `dedup_names: [128]u32` → `[*]u32` + add `dedup_cap: u32` (`:499`), init in `c89EmitterInit` (`:531`) with `sandAlloc` for 128 + `dedup_cap = 128`, and replace the cap guard at `:6061-6064` with grow-then-store (per I report §B shape). Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (same commands as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_local_dedup_cap_xmod`: dump + gcc -c → 0 errors. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: grow local dedup table past 128 (duplicate redecls)`

---

### Task F-C: fix — sibling-variant payload conflation (root cause C, C1 lowering)

**Files:**
- Modify: `sf/src/lower.zig:308-314` (5 arrays), `:629` (64-cap → grow), `:656-677` (`maybeDisambiguateCapture` full scan)
- Report: `.superpowers/sdd/task-FC-emission-report.md`

**Consumes:** I report §C (C1, operator-approved lower.zig scope). **Produces:** `emission_sibling_payload_xmod` GREEN.

- [ ] **Step 1: Apply fix C1**

Grow the 5 `local_decl_*` arrays from `[64]` to growable (`sandAlloc`-backed, mirroring the memory-plan pattern; update init at `lower.zig:438-444`), remove the silent 64-cap `return` at `:629`, and ensure `maybeDisambiguateCapture` (`:656-677`) scans the full local list. Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_sibling_payload_xmod`: dump + gcc -c → 0 errors, run → expected output. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: grow local-decl arrays past 64 + full capture disambiguation (sibling payload)`

---

### Task F-D: fix — indirect .call void guard (root cause D)

**Files:**
- Modify: `sf/src/c89_emit.zig:5233-5258` (.call arm)
- Report: `.superpowers/sdd/task-FD-emission-report.md`

**Consumes:** I report §D. **Produces:** `emission_void_call_xmod` GREEN.

- [ ] **Step 1: Apply fix D**

In the `.call` arm, resolve the callee's fn type (per I report §D shape: hoisted_temps lookup, deref ptr, fn_items return_type) and suppress the `result = ` assignment when the return type is void. `call_direct` guard at `:5372` is the reference. Via `edit`/`fastedit`.

- [ ] **Step 2: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 3: Fixture GREEN + byte-identity gate**

Re-run `emission_void_call_xmod`: dump + gcc -c → 0 errors, run → expected output. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 4: Commit**

Commit: `fix: suppress void result assignment in indirect call (.call arm)`

---

### Task F-E: fix — void-temp class-1b (root cause E: E1 + E1c + tag-test)

> **AMENDMENT 2 (2026-08-20):** I-E investigation re-scoped F-E. E1 (if-capture) fixes ~0 of the 202 class-1b errors (corpus has no tagged-union if-captures); the dominant producer is **E1c** (variant-payload field access `inst.<variant>.<field>`, ~115 errs, root `semantic_analyzer.zig:607` override + `lower.zig:2450-2458`); ~68 of the 202 are actually A (~30 global/pal type loss) + C (~38 switch-arm conflation) and collapse when those land; and the R fixture won't print 7 until the **tag-test** bug is fixed (`lower.zig:4225-4237` tests the constant variant index, not `i`'s runtime tag). Runs AFTER F-A and F-C.

**Files:**
- Modify: `sf/src/lower.zig` (E1 `bindOptionalCapture` tagged-union branch; E1c variant-payload field access at `:2450-2458`; tag-test at `:4225-4237`), `sf/src/semantic_analyzer.zig:607` (drop the `result = base_type_id` override for tagged-union field access)
- Report: `.superpowers/sdd/task-FE-emission-report.md`

**Consumes:** I-E report (E1 pinned design + E1c analysis + tag-test), F-A + F-C results (reorder). **Produces:** class-1b residual re-measured (expect ~68 already gone from A/C), `emission_void_temp_xmod` GREEN printing 7, full self-compile build.

- [ ] **Step 1: Apply fix E1 (bindOptionalCapture tagged-union branch)**

In `bindOptionalCapture`, add the `tagged_union_type` branch per the I-E report's pinned first-non-void-variant derivation (`types_items[cond_ty].payload_idx` → `tu_items[...]` → `fe_items[fields_start+i].type_id`, first `!= TYPE_VOID`), emitting `load_field TU_FIELD_PAYLOAD` into a payload-typed temp — mirroring the switch-arm at `lower.zig:3790-3815`. Via `edit`/`fastedit`.

- [ ] **Step 2: Apply fix E1c (variant-payload field access — the dominant class-1b producer)**

Fix `inst.<variant>.<field>`: stop overriding the result to `base_type_id` for tagged-union field access at `semantic_analyzer.zig:607`, and emit a real payload load in `lower.zig:2450-2458` (payload struct member access `.payload.<variant>._0`, or `load_field TU_FIELD_PAYLOAD` + variant-tag check) so a follow-on `.field` (`inst.call_direct.result`, `inst.tail_call.is_extern`) resolves instead of producing a void temp. Via `edit`/`fastedit`.

- [ ] **Step 3: Apply tag-test fix (if (union.field) compares runtime tag)**

Fix `if (union.field)` so the condition compares `load_field TU_FIELD_TAG` on the *base* (`i`) against the nominated variant index, instead of testing the constant tag value of the nominated variant (`lower.zig:4225-4237` + `:2450-2458`). Required for the fixture to print 7. Via `edit`/`fastedit`.

- [ ] **Step 4: Rebuild + reinstall std** (as F-A Step 3)

- [ ] **Step 5: Fixture GREEN + byte-identity gate**

Re-run `emission_void_temp_xmod`: dump + gcc -c → 0 errors, run → prints 7. Then 4 MD5s byte-identical + corpus 287 unchanged + matrix 21/21. Runtime-priority override as in F-A.

- [ ] **Step 6: Re-measure class-1b residual**

Regenerate `/tmp/emit_errs.txt` and count remaining `zT_<n> undeclared`. Expected: the ~68 A/C errors are gone (landed in F-A/F-C), E1c removed its ~115, leaving a small residual to triage. If a substantial NEW shape appears, STOP and report.

- [ ] **Step 7: Full self-compile build + smoke (success gate)**

```bash
bash scripts/self_compile/build_zig1_5.sh
```
Expected: rc=0, `=== [zig1_5] Done: /tmp/zig1_5 ===`, both `zig1_5_asan` + `zig1_5_clean` produced. Smoke both on `examples/z98/hello/main.zig` (rc=0, `.c` emitted). If any gcc error remains, it is an incomplete fix (iterate) or a NEW class (STOP and report).

- [ ] **Step 8: Commit**

Commit: `fix: tagged-union payload access (E1 if-capture, E1c variant-payload field, tag-test)`

---


### Task GATE: reconcile docs + closeout

**Files:**
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`
- Report: `.superpowers/sdd/task-GATE-emission-report.md`

**Consumes:** F result. **Produces:** reconciled tracking docs.

- [ ] **Step 1: Final gate sweep**

Re-verify 4 MD5s byte-identical, corpus 287 `OK=276 FAIL=7 ICE=0 CRASH=0 GREEN=4`, matrix 21/21, `test_analyzer_bin` "5 passed, 4 failed".

- [ ] **Step 2: Update EXPECTED_FAIL.md**

Version bump + a closeout section: the 5 emission classes fixed, the R fixtures (now GREEN), the self-compile-now-buildable milestone, and the next frontier (resume correctness plan T3-T6).

- [ ] **Step 3: Update QUICK_REF.md**

Add a post-emission-fix baseline paragraph; note that self-compile now produces a *buildable* `zig1_5` (gcc-compilable emitted C), correcting the prior "FULLY GREEN" wording that only checked rc + file count.

- [ ] **Step 4: Commit**

Commit: `docs: self-compile emission-fix GATE closeout + reconciliation`
