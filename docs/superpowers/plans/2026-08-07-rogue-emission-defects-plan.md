# rogue_mud Emission Defects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 5 C89 emission defects blocking rogue_mud end-to-end compilation, each gated by a defensive repro with mandatory RUNTIME verification.

**Architecture:** 4 batched I-tasks (investigation) → ONE combined STOP for operator ruling → 4 F-tasks (fix, each runtime-gated) → F5 gate sweep. I1 covers the shared duplicate-field topo-sort bug (gaps #1+#2); I2/I3/I4 cover the other 3 gaps. All I-tasks are independent (dispatch in any order); all F-tasks are independent of each other. Each F-task flips its repro(s) FAIL→OK.

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — timeouts):
  ```bash
  OUT=/tmp/zrg
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors.
- **RUNTIME gate mandatory per F-task**: each fixed repro must run rc=0 AND print the expected output — NOT just gcc-clean. NOTES.md documents the expected runtime output.
- 4 MD5 baselines byte-identical unless operator-approved re-baseline (F-5 AMENDMENT B — runtime is the gate): mud `50beb1bf...`, gol `0d8f0092...`, lisp `605b597e...`, json `b5f56ebd...`
- Corpus: 210 repros, OK=203/FAIL=3/gg=4 (raw 7) baseline. FAIL count must not increase. Only the task's repro(s) flip FAIL→OK.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
- The plan is the ONLY authority. Plan says A → do A; if you think X/Y is better, STOP and present.

---

### Task I1: Investigate duplicate-field emission (gaps #1 + #2)

**Files:** investigation → `.superpowers/sdd/I-rogue-dupfld-report.md`; no source changes.

**Interfaces:**
- Produces: recommended fix site (edges-count vs dequeue side) with file:line, A/B/C options, blast radius (repros flipped, MD5s affected) for F1.

- [ ] **Step 1: Reproduce both failures**

Build `/tmp/zrg/zig1`. Run `--dump-c89 --output-dir` on `repro/mi_matrix/dup_optptr_field_emit/main.zig` and `dup_val_field_emit/main.zig`. Confirm: dump rc=0, gcc fails with `unknown type name 'zT_...'`. Record exact gcc output.

- [ ] **Step 2: Trace the topo-sort**

Read `sf/src/c89_emit.zig` `tstTopologicalSort` (:935-971), `tstEdgesCount`, `tstEdgesFill`, `tstIsDep`, and the dequeue/indegree loop. Read tech docs `08_c89_emission.md` + `03_type_resolution.md`. Confirm the mechanism: 2 same-typed edge-requiring fields → `tstEdgesCount` counts 2 edges → dequeue decrements indegree once per dependent type → struct never dequeued → dropped from `sorted`.

- [ ] **Step 3: A/B/C options**

- **A:** Fix the dequeue loop to consume ALL edges (decrement indegree per edge, not per dependent type)
- **B:** Fix `tstEdgesCount`/`tstEdgesFill` to dedupe same-typed field edges (count once per dependent type)
- **C:** Fix the sorted-closure computation (add dropped-but-reachable nodes)

For each: exact file:line, blast radius (which repros flip, whether any gate baseline uses duplicate-typed fields → MD5 impact), risk.

- [ ] **Step 4: Report + stop**

Write `.superpowers/sdd/I-rogue-dupfld-report.md` with confirmed mechanism, options, blast radius, recommendation. STOP for operator ruling (with the other I-tasks batched).

---

### Task I2: Investigate undefined array struct-literal init (gap #3)

**Files:** investigation → `.superpowers/sdd/I-rogue-undefarr-report.md`; no source changes.

**Interfaces:**
- Produces: recommended fix (lowerer vs emitter), A/B/C, blast radius for F2.

- [ ] **Step 1: Reproduce**

Build `/tmp/zrg/zig1`. `--dump-c89` on `repro/mi_matrix/undef_arr_struct_literal/main.zig`. Confirm: dump rc=0, gcc fails `incompatible types assigning 'zT_..._Client' from 'int'`. Inspect the emitted C — find the `clients[_j] = 0` zero-fill.

- [ ] **Step 2: Trace**

Read `sf/src/lower.zig` struct-literal array-field lowering + `sf/src/c89_emit.zig` array-init emission. Read `07_lir_lowering.md` + `08_c89_emission.md`. Find where `undefined` array init becomes a zero-fill loop and why it assumes primitive element type.

- [ ] **Step 3: A/B/C options**

- **A:** Lowerer — emit no init for `undefined` struct-array fields (leave uninitialized)
- **B:** Emitter — for `undefined` struct-array, emit no initializer (skip the zero-fill)
- **C:** Per-element `undefined` / memset

For each: file:line, blast radius (does any gate baseline use `undefined` struct-array fields?), risk.

- [ ] **Step 4: Report + stop**

Write `.superpowers/sdd/I-rogue-undefarr-report.md`. STOP (batched).

---

### Task I3: Investigate cross-module pub const global (gap #4)

**Files:** investigation → `.superpowers/sdd/I-rogue-xmodconst-report.md`; no source changes.

**Interfaces:**
- Produces: recommended fix (fold vs extern decl vs definition), A/B/C, blast radius for F3.

- [ ] **Step 1: Reproduce**

Build `/tmp/zrg/zig1`. `--dump-c89 --output-dir` on `repro/mi_matrix/xmod_pub_const_global/main.zig`. Confirm: dump rc=0, gcc fails `'zG_..._COLOR_WHITE' undeclared`. Inspect emitted C — the consumer `.c` reads `zG_...` with no definition anywhere.

- [ ] **Step 2: Trace**

Read `sf/src/lower.zig` global-ref lowering (cross-module `pub const` → storage-global read), the F-7 storage-global registry, `sf/src/c89_emit.zig` global-decl pass + the P1-2 header extern pattern (c89_emit.zig:2063-2079). Read `07_lir_lowering.md`, `08_c89_emission.md`, `02_symbol_registration.md`. Confirm: `pub var` gets a storage slot; `pub const` does not; F8 fold is same-module-only.

- [ ] **Step 3: A/B/C options**

- **A:** Emit a definition for cross-module `pub const` in its owning module (mirror `pub var` storage slot)
- **B:** Emit an extern decl in the consumer header (mirror P1-2 extern-global pattern, c89_emit.zig:2063-2079)
- **C:** Extend comptime fold through the module boundary (fold cross-module const chains)

For each: file:line, blast radius (do mud/lisp/json use cross-module `pub const`? → MD5 impact), risk.

- [ ] **Step 4: Report + stop**

Write `.superpowers/sdd/I-rogue-xmodconst-report.md`. STOP (batched).

---

### Task I4: Investigate switch mixed-case arg typing (gap #5)

**Files:** investigation → `.superpowers/sdd/I-rogue-switcharg-report.md`; no source changes.

**Interfaces:**
- Produces: recommended fix site (call_arg_types mapping), A/B/C, blast radius for F4.

- [ ] **Step 1: Reproduce**

Build `/tmp/zrg/zig1`. `--dump-c89` on `repro/mi_matrix/switch_mixed_case_argtype/main.zig`. Confirm: dump rc=0, gcc fails `incompatible type for argument`. Inspect emitted C — find the call after the switch where arg temp types are wrong (`&arena`→`unsigned int`, `"save.dat"`→`char*`).

- [ ] **Step 2: Trace**

Read `sf/src/semantic_analyzer.zig` switch-case resolution + call-arg typing (`call_arg_types`). Read `05_semantic_analysis.md` + `07_lir_lowering.md`. Determine why a switch mixing assignment cases and empty/break cases corrupts `call_arg_types` while single-type switches work.

- [ ] **Step 3: A/B/C options**

- **A:** Fix the switch-case resolution to always populate `call_arg_types` for the call regardless of case mix
- **B:** Fix the call-arg lowering to not rely on switch-poisoned state
- **C:** Build `call_arg_types` from the actual call arguments, not switch residue

For each: file:line, blast radius (does any gate baseline have a mixed-case switch before a call?), risk.

- [ ] **Step 4: Report + stop**

Write `.superpowers/sdd/I-rogue-switcharg-report.md`. STOP (batched).

---

### Task F1: Fix duplicate-field emission (gaps #1 + #2)

**Files:** per I1 ruling (`sf/src/c89_emit.zig`).

**Interfaces:**
- Consumes: I1 report + operator ruling.
- Produces: `dup_optptr_field_emit` + `dup_val_field_emit` FAIL→OK, both runtime-correct.

- [ ] **Step 1: Implement the ruling — OPTION B (operator ruling 2026-08-07, per I1)**

I1 confirmed: `tstEdgesCount` (c89_emit.zig:799-839) counts one edge per field occurrence; the Kahn dequeue (c89_emit.zig:960-968) decrements once per dependent type via boolean `tstIsDep` (:898-933) — two same-typed edge-forming fields → indegree=2, decrement=1 → struct never dequeued → dropped from `sorted` → no fwd-decl/body → gcc `unknown type name`.

**Fix:** in `tstEdgesCount`, count each distinct dependent type ONCE (dedupe same-typed field edges per type; including dedupe of tag_type vs fields in the tagged_union branch). Mirror the same dedupe in `tstEdgesFill` (c89_emit.zig:841-896) for consistency — NOTE it is dead code (0 callers), change has zero runtime effect. Indegree then equals "number of distinct dep types" == exactly the count of `tstIsDep`-true decrements in :961, so count and dequeue can never drift. Kahn drains fully (all nodes emitted), which also eliminates the uninitialized-`sorted`-tail hazard (sandAlloc does not zero).

- [ ] **Step 2: Verify both repros**

`dup_optptr_field_emit` + `dup_val_field_emit`: dump rc=0, gcc rc=0, link rc=0, run rc=0 printing expected values (struct fields read back correctly). Confirm the emitted C now contains the struct bodies.

- [ ] **Step 3: Gate sweep**

Build 0 err. 4 MD5s byte-identical (mud `50beb1bf...`/gol `0d8f0092...`/lisp `605b597e...`/json `b5f56ebd...` — verified no duplicate edge-forming field types in any gate program). Corpus: 210→212, +2 OK (dup_optptr, dup_val), FAIL 3 stays. EXPECTED_FAIL.md rows updated.

- [ ] **Step 4: Commit**

```bash
git add sf/src/c89_emit.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix: duplicate-typed struct fields emit correctly (dup field topo-sort)"
```

---

### Task F2: Fix undefined array struct-literal init (gap #3)

**Files:** per I2 ruling (`sf/src/lower.zig` and/or `sf/src/c89_emit.zig`).

**Interfaces:**
- Consumes: I2 report + operator ruling.
- Produces: `undef_arr_struct_literal` FAIL→OK, runtime-correct.

- [ ] **Step 1: Implement the ruling — OPTION A (operator ruling 2026-08-07, per I2)**

I2 confirmed: `undefined` array-typed struct-literal field init is emitted as a zero-fill loop by `emitFieldAssign` (c89_emit.zig:276-287) that hardcodes `base.fld[_j] = 0;` — never checking element type or `src`; only valid for scalar elements. The zig0 oracle emits NOTHING for `undefined` array fields (both struct and primitive elements — verified). 

**Fix — lowerer, upstream (matches oracle exactly):** in `sf/src/lower.zig`, skip the `assign_field` for the field entirely when `child_0.kind == undefined_literal` AND the field's declared type is `array_type`:
- `lower.zig:2988` — skip `lowerExpr` for the field (avoid the dead `undefined_const` temp).
- `lower.zig:3031-3042` struct_type branch — if `fe_items[fs+fj].type_id` is `array_type` AND `child_0.kind == undefined_literal`, skip the `emitInst(assign_field)`.
- Mirror in the tagged-union branch (`:3024-3027`).

**Gate consequence (operator-approved, F-5 AMENDMENT B precedent):** mud re-baseline REQUIRED — mud `main.zig:159` `.buffer = undefined` (`[256]u8` primitive array) currently emits the zero-fill (gate output `/tmp/mud_gate.c:800-802`); Option A drops it. Runtime identical (buffer written by `plat_recv` before any read; mud gate = listen rc=124, no client connects). gol/lisp/json byte-identical. Record the new mud MD5.

**Known-affected output:** `emitFieldAssign` ignores `src` for ALL array fields (real array-of-struct values fail with undeclared temps) — a SEPARATE latent bug, OUT of this fix's scope (tracked as follow-up, do NOT fix here).

- [ ] **Step 2: Verify the repro**

`undef_arr_struct_literal`: dump rc=0, gcc rc=0, run rc=0 printing expected. Emitted C has valid struct-array handling (no `= 0` on a struct element).

- [ ] **Step 3: Gate sweep**

Build 0 err. **mud RE-BASELINED** (Option A drops the `[256]u8` dead zero-fill at mud main.zig:159; runtime-identical — buffer written by `plat_recv` before read, F-5 AMENDMENT B precedent; record the new mud MD5). gol/lisp/json byte-identical (no struct-literal `undefined` array fields). Corpus: 212→213, +1 OK, FAIL 3 stays. EXPECTED_FAIL.md row updated.

- [ ] **Step 4: Commit**

```bash
git add sf/src/<fixed>.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix: undefined struct-array field init emits valid C (undef_arr_struct_literal)"
```

---

### Task F3: Fix cross-module pub const global (gap #4)

**Files:** per I3 ruling (`sf/src/lower.zig` and/or `sf/src/c89_emit.zig`).

**Interfaces:**
- Consumes: I3 report + operator ruling.
- Produces: `xmod_pub_const_global` FAIL→OK, runtime-correct.

- [ ] **Step 1: Implement the ruling — OPTION C (operator ruling 2026-08-07, per I3)**

I3 confirmed: cross-module `pub const` literal-init (e.g. `pub const COLOR_WHITE: u8 = 7`) registers as `SymbolKind.global` but gets NO F-7 storage slot (main.zig:616-660 skips literal-init consts, bit0=mutable only) → no definition in owner `.c`, no extern in headers → consumer `load_global` reads an undeclared `zG_...` name.

**Fix:** in the cross-module `SymbolKind.global` module-field-access branch at `lower.zig:2005-2011`, when `(ts.flags & 0x01) == 0` (const) and the target's `decl_node.child_1` init is an int/float/char literal, emit the corresponding `int_const`/`float_const` with the type from `resolvedTypeTableGet(resolved_types, ts.decl_node)` (the branch already computes `gbl_tid` at `lower.zig:2006`) — mirroring the same-module literal fold at `lower.zig:1681-1710`. Type the folded temp at the DECLARED type (u8, not TYPE_U32 — avoids the F-7 u64-width regression class). Keep the `load_global` fallback for non-literal consts (already storage-classified via main.zig:627, works today). Do NOT emit a bare definition without an initializer (zero-init trap: `unsigned char zG_...;` would silently hold 0 not 7).

- [ ] **Step 2: Verify the repro**

`xmod_pub_const_global`: dump rc=0, gcc rc=0, run rc=0 printing the const value (7). Emitted C has the const defined/declared/folded.

- [ ] **Step 3: Gate sweep**

Build 0 err. 4 MD5s — assess in I3; re-baseline only if legit (F-5 AMENDMENT B). Corpus: 213→214, +1 OK, FAIL 3 stays. EXPECTED_FAIL.md row updated.

- [ ] **Step 4: Commit**

```bash
git add sf/src/<fixed>.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix: cross-module pub const resolves (xmod_pub_const_global)"
```

---

### Task F4: Fix switch mixed-case arg typing (gap #5)

**Files:** per I4 ruling (`sf/src/semantic_analyzer.zig` and/or `sf/src/lower.zig`).

**Interfaces:**
- Consumes: I4 report + operator ruling.
- Produces: `switch_mixed_case_argtype` FAIL→OK, runtime-correct.

- [ ] **Step 1: Implement the ruling — OPTION A (operator ruling 2026-08-07, per I4)**

I4 confirmed the mechanism is NOT `call_arg_types` corruption — it is a sema mid-switch abort: the MIX else-branch at `semantic_analyzer.zig:1167` `return type_mod.TYPE_VOID;` aborts `resolveSwitchExpr` when two prong bodies have non-coercible types (assignment→i32 vs empty-block→void), skipping all later prongs — the call prong is never sema'd, so `call_arg_types` is never populated at `:775`, and the lowerer fallback (`lower.zig:2388`) types arg slots as raw lowered types.

**Fix (validated by I4 on a patched /tmp build):** replace `return type_mod.TYPE_VOID;` at `semantic_analyzer.zig:1167` with `continue;` (skip this prong's contribution to `unified` but keep resolving remaining prongs). Keep the `resolvedTypeTableSet(..., TYPE_VOID)` on :1167 (stmt-switch resolved type is unused; drop is acceptable but keep-minimal preferred). Read the region first, follow existing patterns.

- [ ] **Step 2: Verify the repro**

`switch_mixed_case_argtype`: dump rc=0, gcc rc=0, run rc=0 printing expected. Emitted C has correct arg temp types at the call.

- [ ] **Step 3: Gate sweep**

Build 0 err. 4 MD5s byte-identical. Corpus: 214→215, +1 OK, FAIL 3 stays. EXPECTED_FAIL.md row updated.

- [ ] **Step 4: Commit**

```bash
git add sf/src/<fixed>.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix: switch mixed-case call-arg typing (switch_mixed_case_argtype)"
```

---

### Task F5: Gate sweep + docs

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, tech docs (per AGENTS §1.1.1)

**Interfaces:**
- Consumes: all completed fixes.
- Produces: final corpus accounting, MD5 table, updated tech docs.

- [ ] **Step 1: Full corpus sweep**

Run the corpus classifier (QUICK_REF recipe). Expected final: **215 repros, OK=208/FAIL=3/gg=4 (raw 7)** — the 5 gap repros all OK, FAIL 3 = field_store_drop, test_stub_0, self_embed_optional_cycle. Record actual.

- [ ] **Step 2: MD5 gate**

Verify 4 MD5s (or re-baselined values with runtime proof). Document any re-baseline.

- [ ] **Step 3: Tech docs**

Update affected tech docs per AGENTS §1.1.1 (07_lir_lowering, 08_c89_emission, 05_semantic_analysis, 02_symbol_registration, 03_type_resolution as applicable). Add `[updated: 2026-08-07]`.

- [ ] **Step 4: Update EXPECTED_FAIL.md + QUICK_REF.md**

Clear the 5 gap rows (dup_optptr, dup_val, undef_arr, xmod_pub_const, switch_mixed_case) → OK; note the latent `opt_slice_null_return` guard repro (OK-by-gate, type-incorrect, tracked separately). Update corpus baseline 215/208/3/4 (raw 7) + MD5 table. Keep the 3 remaining FAILs enumerated.

- [ ] **Step 5: Commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md sf/docs/tech_docs/ examples/z98/rogue_mud/NOTES.md
git commit -m "docs: gate sweep + tech docs for rogue_mud emission defects plan"
```

---

## Amendments Record

- **AMENDMENT 0 (2026-08-07):** Plan structure finalized from brainstorm. 4 batched I-tasks (I1 covers gaps #1+#2 shared topo-sort root; I2/I3/I4 cover #3/#4/#5) → ONE combined STOP for operator ruling → 4 F-tasks (each runtime-gated) → F5 sweep. User confirmed: formal I-tasks required; gaps #1+#2 merged; I-tasks batched; runtime gate mandatory per F-task ("gate functionality because those changes usually can have benign impact but it needs to be runtime").

- **AMENDMENT 1 (2026-08-07, operator ruling after I1-I4 + deep-dive):** I-tasks I1-I4 COMPLETE (reports in `.superpowers/sdd/I-rogue-{dupfld,undefarr,xmodconst,switcharg}-report.md`). Operator approved fix options and amended each F-task:
  - **F1 = Option B** (dedupe `tstEdgesCount` by distinct dep type; mirror in dead `tstEdgesFill`). Root-cause invariant fix (count vs dequeue consistency). All 4 MD5s byte-identical.
  - **F2 = Option A** (lowerer skip `assign_field` for `undefined` array-typed fields; upstream, matches zig0 oracle which emits NOTHING). **mud re-baseline required** (drops dead `[256]u8` zero-fill; runtime-identical, F-5 AMENDMENT B precedent). gol/lisp/json byte-identical.
  - **F3 = Option C** (fold literal at cross-module ref site lower.zig:2005-2011, mirroring same-module fold :1681-1710). Zero MD5 impact.
  - **F4 = Option A** (`semantic_analyzer.zig:1167` `return TYPE_VOID` → `continue`; validated on patched build — repro FAIL→OK, 4 MD5s byte-identical, corpus exactly 1 flip).
  - Corpus accounting corrected: 210 → 212 (F1) → 213 (F2) → 214 (F3) → 215 (F4). F5 final: 215 repros, OK=208/FAIL=3/gg=4.
  - **Out-of-scope finding (documented, follow-up):** `char_literal` switch `case` labels dropped at lower.zig:3858-3860/:3121-3123 — rogue_mud's input switch (`main.zig:236-256`) would be runtime-dead even after all 5 fixes. Orthogonal to gap #5; NOT fixed in this plan.
  - **Stale refs corrected:** P1-2 header extern pattern is c89_emit.zig:2149-2167 (not 2063-2079); lower.zig module-field-access is :2005-2011 (not :1869-1875); doc filenames are `AST_LIR_Lowering_p2.md`/`LIR_C89_Emission_p2.md`/`Import_Symbol_reg.md` (not 07/08/02).
