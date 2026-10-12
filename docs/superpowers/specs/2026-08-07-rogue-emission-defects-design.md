# rogue_mud Emission Defects — Design Spec

**Date:** 2026-08-07
**Status:** Draft
**Predecessor:** `2026-08-07-labeled-stmt-design.md` (complete at HEAD f75e8041)

## Goal

Fix the 5 C89 emission defects that block rogue_mud end-to-end compilation. Frontend fully passes (the labeled_stmt gap is fixed); C89 emission fails on 5 distinct defects. Each fix is gated by a defensive repro (already created by the I-task), with mandatory RUNTIME verification.

## Background

After the labeled_stmt fix, `zig1 --dump-c89` on `examples/z98/rogue_mud/main.zig` succeeds (rc=0, 20 modules). gcc per-file fails on **5 distinct emission defects** (all dump-OK, gcc-fail, all zig0-verified = genuine compiler gaps). A syntax survey found 8 uncovered patterns — only the combinations below fail; primitives compile clean.

## The 5 gaps

| # | Repro | Root cause | gcc symptom |
|---|-------|-----------|-------------|
| 1 | `dup_optptr_field_emit` | Kahn topo-sort indegree bug (`tstTopologicalSort`, c89_emit.zig:935-971): `tstEdgesCount` counts 2 edges for two same-typed fields but dequeue decrements indegree once per dependent type → struct never dequeued → body never emitted | `unknown type name 'zT_..._BspNode'` |
| 2 | `dup_val_field_emit` | Same root cause as #1, by-value variant (`a: Point, b: Point`) | `unknown type name 'zT_..._Line'` |
| 3 | `undef_arr_struct_literal` | `.clients = undefined` for `[5]Client` lowers to zero-fill loop `clients[_j] = 0` (valid only for primitive arrays) | `incompatible types assigning 'zT_..._Client' from 'int'` |
| 4 | `xmod_pub_const_global` | Cross-module `pub const COLOR_WHITE: u8 = 7` refs lower to storage-global `zG_...` reads; no definition/extern decl emitted for a `pub const` (only `pub var` gets a slot). F8 fold doesn't cover cross-module | `'zG_..._COLOR_WHITE' undeclared` |
| 5 | `switch_mixed_case_argtype` | Switch mixing assignment cases + empty/break cases before a call poisons call-arg temp typing (`&arena`/`"save.dat"` fall back to `unsigned int`/`char*`) | `incompatible type for argument 1/3` |

**Latent (OK-by-gate, type-incorrect, NOT in FAIL list):** `opt_slice_null_return` — `catch return null` in `?[]T` fn emits null-payload temp as `int` (`-Wint-conversion` warning). Guard repro created; would FAIL under `-Werror`.

## Architecture

4 independent I-tasks (investigation) — **batched**: all 4 dispatch, then ONE combined STOP for operator ruling. Then 4 F-tasks (fix), each gated on runtime behavior. Then a gate sweep.

```
I1 (dup fields #1+#2, shared topo-sort root) → \
I2 (undef array init #3)                        → COMBINED STOP → F1..F4 → F5 (sweep)
I3 (xmod pub const #4)                          → (each F-task: runtime-gated)
I4 (switch case argtype #5)                     → /
```

## Gates (global, per F-task)

- Build: zig0 → zig1 bootstrap in /tmp, 0 gcc errors (QUICK_REF recipe, NOT `sf/build/out_release/`)
- 4 MD5 baselines byte-identical: mud `50beb1bf...`, gol `0d8f0092...`, lisp `605b597e...`, json `b5f56ebd...` (unless operator-approved re-baseline, F-5 AMENDMENT B precedent — runtime is the gate)
- Corpus: 210 repros, OK=203/FAIL=3/gg=4 (raw 7) baseline. FAIL count must not increase. Only the task's repro(s) flip FAIL→OK.
- **RUNTIME gate mandatory per F-task**: each fixed repro must run rc=0 AND print the expected output (NOT just gcc-clean — emission changes can be benign at compile but wrong at runtime). NOTES.md documents the expected runtime output.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- QUICK_REF.md reference mandatory for all gates.
- The plan is the ONLY authority. Plan says A → do A; if you think X/Y is better, STOP and present.

---

# Item 1: Duplicate-Field Emission (gaps #1 + #2)

## Investigation (I1)

Read `08_c89_emission.md` + `03_type_resolution.md`. Trace `tstTopologicalSort` (c89_emit.zig:935-971), `tstEdgesCount`, `tstEdgesFill`, the indegree decrement loop, and the Kahn dequeue. Confirm: 2 same-typed edge-requiring fields → 2 edges counted → dequeue decrements once → struct never reaches indegree 0 → dropped from `sorted` → struct body never emitted.

Key question: what is the correct indegree semantics — per dependent-type or per field? Check how `tstIsDep`/`fieldEmbedsByValue` count edges vs how the dequeue loop consumes them.

Options (A/B/C): where the mismatch is — edges-count side, dequeue side, or the sorted-closure. Blast radius: which repros flip, which MD5s change.

Repros: `dup_optptr_field_emit` (2× `?*BspNode`), `dup_val_field_emit` (2× `Point`). Both must FAIL→OK post-fix.

## Fix (F1)

Per I1 ruling. Expected: correct the indegree/edge accounting so duplicate-typed fields are each counted OR the dequeue consumes all edges. Both repros gcc-clean + run correct.

**Gate:** build 0 err; both repros dump rc=0, gcc rc=0, link rc=0, run rc=0 printing expected values (struct fields read back correctly). 4 MD5s byte-identical. Corpus: 210→212, +2 OK (dup_optptr, dup_val), FAIL 3 stays.

---

# Item 2: Undefined Array Struct-Literal Init (gap #3)

## Investigation (I2)

Read `07_lir_lowering.md` + `08_c89_emission.md`. Trace struct-literal lowering for array fields with `undefined` init. Find where the zero-fill (`clients[_j] = 0`) is emitted — it assumes primitive element type. Determine the correct emission for struct-typed array elements (memset? per-element undefined? skip?).

Options (A/B/C): (a) emit no init for undefined struct-array fields (leave uninitialized), (b) memset to 0, (c) per-element `undefined`. Blast radius.

Repro: `undef_arr_struct_literal` (`server.clients = undefined` for `[5]Client`).

## Fix (F2)

Per I2 ruling. The `.clients = undefined` for a struct-array field must emit valid C (not `= 0`).

**Gate:** build 0 err; repro dump rc=0, gcc rc=0, run rc=0 printing expected. 4 MD5s byte-identical. Corpus: 212→213, +1 OK, FAIL 3 stays.

---

# Item 3: Cross-Module pub const Global (gap #4)

## Investigation (I3)

Read `07_lir_lowering.md` (global lowering), `08_c89_emission.md` (extern decl pass + F-S7 header extern pattern), `02_symbol_registration.md`. Trace: `pub const COLOR_WHITE: u8 = 7` cross-module refs lower to storage-global `zG_...` reads; `pub var` gets a storage slot but `pub const` does not. F8 comptime fold only covers same-module const chains. Determine where a cross-module `pub const` must get: (a) a definition in its owning module, (b) an extern decl in the consumer header (mirror the P1-2 extern-global pattern, c89_emit.zig:2063-2079), or (c) comptime fold through the module boundary.

Options (A/B/C): where to emit the def/extern, whether it's a lowerer or emitter change. Blast radius: json/mud/lisp use cross-module consts? Which MD5s change.

Repro: `xmod_pub_const_global` (module A `pub const COLOR: u8 = 7`, main reads `A.COLOR`).

## Fix (F3)

Per I3 ruling. Cross-module `pub const` resolves (either folded or declared).

**Gate:** build 0 err; repro dump rc=0, gcc rc=0, run rc=0 printing the const value. 4 MD5s — assess in I3 (re-baseline if legit, F-5 AMENDMENT B). Corpus: 213→214, +1 OK, FAIL 3 stays.

---

# Item 4: Switch Mixed-Case Arg Typing (gap #5)

## Investigation (I4)

Read `05_semantic_analysis.md` (switch case resolution) + `07_lir_lowering.md` (call-arg lowering). Trace: a switch mixing assignment cases and empty/break cases before a call → `call_arg_types` param-type mapping misses some arg slots → `&arena`/`"save.dat"` fall back to wrong types. Determine why a single case-type works but a mix breaks.

Options (A/B/C): where the call_arg_types mapping is built, why mixed cases corrupt it, the correct fix. Blast radius.

Repro: `switch_mixed_case_argtype` (switch with mixed assign/empty cases then a call).

## Fix (F4)

Per I4 ruling. Call-arg temp typing correct under mixed switch cases.

**Gate:** build 0 err; repro dump rc=0, gcc rc=0, run rc=0 printing expected. 4 MD5s byte-identical. Corpus: 214→215, +1 OK, FAIL 3 stays.

---

# Item 5: Gate Sweep + Docs (F5)

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`, tech docs (per AGENTS §1.1.1)

- Run full corpus sweep. Expected final: 215 repros, OK=208/FAIL=3/gg=4 (raw 7) — the 5 gap repros all OK, FAIL 3 = the 2 std-lib-deferred + 1 C89 fundamental.
- 4 MD5s verified (or re-baselined with runtime proof).
- Update EXPECTED_FAIL.md (5 rows cleared + latent note for opt_slice_null_return), QUICK_REF baseline, tech docs for the changed files (07/08/05/02/03 as applicable).

---

## Follow-ups (NOT this plan)

- **rogue_mud full re-attempt** after the 5 fixes — expect it to compile (or reveal the next gap).
- The 0-FAIL corpus goal remains blocked by the 2 std-lib-deferred FAILs + 1 C89 fundamental.
- Syntax-survey residual: the 8 uncovered patterns are primitives that compile clean; only the 5 combinations above fail. Any new combination failures during the rogue_mud re-attempt become new repros.
