# TCO (Tail Call Optimization) — Implementation Plan

**Date:** 2026-08-02
**Branch:** `zig1_start`
**Design:** `docs/superpowers/specs/2026-08-02-tco-design.md`

Goal: real compiler TCO. Detect tail-call positions in the lowerer. Self-recursion → `jump loop_header` with arg rebinding. Cross-function → new `tail_call` LIR variant (C89 falls back to `call+ret`).

## Required Reading

| Document | Role | Key Sections |
|----------|------|--------------|
| `docs/superpowers/specs/2026-08-02-tco-design.md` | Design oracle | All sections |
| `sf/src/lower.zig` | Lowerer — tail detection + LIR emission | `return_stmt` :3614-3634, `fn_call` :1954-2380, `lowerFn` entry block creation, `LoopInfo` :65-75 |
| `sf/src/lir.zig` | LIR union — variants | `LirInst` union :20-80, `call_direct` :45-53, `call` :37-43, `jump` :28, `loop_header` :31 |
| `sf/src/c89_emit.zig` | C89 emitter — instruction match | `loop_header` :2754, `.ret` :2898, `.call_direct` :3606-3740, `.call` :3580-3605, `emitFunctionBody` :4164-4249, `emitHoistedDecls` :2157-2660, `resolveTempName` :2732 |
| `sf/docs/tech_docs/07_lir_lowering.md` | Lowerer reference | TCO section :551-685, `while_stmt` :3302, `LoopInfo` |
| `sf/docs/tech_docs/08_c89_emission.md` | Emitter reference | Function emission, call/match structure |

## Global Constraints

- **Source files only:** `sf/src/lir.zig`, `sf/src/lower.zig`, `sf/src/c89_emit.zig`. Docs: `sf/docs/tech_docs/07_lir_lowering.md`, `sf/docs/tech_docs/08_c89_emission.md`, `docs/sf/QUICK_REF.md`.
- **Z98 idioms required:** `@intCast` for all integer conversions, `var msg: []const u8 = "text";` before PAL calls, if/else-if chains (no switch on non-integers), no generics.
- **Build gate:** `bash sf/scripts/build_release.sh` → `=== [release] Done ===`, 0 errors.
- **Stdout md5s (4):** mud `5fb57e70c2d637276ab0264c1401cd0d`, gol `f855c9f93c73422f56378f3f73231727`, lisp `0ad0204088f91c1eae7c040da8f99a1c`, json `11a5db1d3d43acf4880e2d157590abe3`. All byte-identical. TCO is additive — none of the 4 gated examples contain tail-recursive calls, so no LIR/output change expected.
- **Corpus gate:** `165/15/6/0` baseline preserved (186 repros). No regression.
- **No out-of-plan fixes.** Stop on ambiguity.

## I-M Research Tasks

### I-M1 — Lowerer Tail Detection Site
**Files:** `sf/src/lower.zig`
**Report:** `.superpowers/sdd/IM-tco1-report.md`

1. Exact `return_stmt` lowering flow — what LIR does it emit for plain `return x`, `return f()`, `return try f()` ?
2. How is `try` lowered? Walk the LIR sequence from `call_direct` → `check_error` → `branch` → `unwrap` → `ret`.
3. Can a `return_stmt` contain `if/switch` expressions? If so, how does the lowerer handle branching return values?
4. Where in `lowerFn` is the entry basic block created? What is its block ID convention?
5. What is the `LirFunction.params` structure? How are params linked to temps?
6. What does `self.func` expose at the point of `return_stmt` lowering? (name_id, module_id, params, return_type)

### I-M2 — LIR Union Layout
**Files:** `sf/src/lir.zig`
**Report:** `.superpowers/sdd/IM-tco2-report.md`

1. Where exactly in the `LirInst` union does `tail_call` belong? Between which variants?
2. What format/print/im-gen functions reference `LirInst`? Does `loop_header` already appear in any match?
3. What is `call_direct`'s full struct layout? Copy for `tail_call` basing.
4. Does any code iterate `LirInst` variants by ordinal (enum-to-int)? Adding `tail_call` could shift indices.
5. What is the exact struct layout for `jump` (the TCO self-recursion target LIR instruction)?
6. Does LIR have any validation/walk function that matches all variants?

### I-M3 — C89 Emitter Match Structure
**Files:** `sf/src/c89_emit.zig`
**Report:** `.superpowers/sdd/IM-tco3-report.md`

1. Where is the main LIR instruction match/switch block? What line range?
2. How does `.call_direct` resolve function names? How would `tail_call` differ?
3. Where exactly do temp declarations appear relative to the entry block body? Can `tco_restart:` label go after temps?
4. What does the `.jump` case emit? (precedent for `goto` pattern)
5. What does the `.assign` case emit? (precedent for arg rebinding)
6. Does `c89_emit.zig` have any `else => {},` or `_ => {}` catch-alls that would silently swallow new variants?

## F-S Implementation Tasks

### F-S1 — LIR: Add `tail_call` Variant + Activate `loop_header`

**Files:** `sf/src/lir.zig`
**Pre-requisite:** I-M2

**Scope:** Add `tail_call` struct variant to LirInst union. Ensure all match/print/walk functions handle new variant (no-op or basic). No lowerer or emitter changes.

**Steps:**
1. Add `tail_call` variant to `LirInst` union. **AMENDMENT 1 (insertion point):** insert at lir.zig:46, AFTER `call_direct` (:45) and BEFORE `func_ref` (:46) — keeps the call family contiguous (`call` :37, `call_direct` :45, `tail_call`, `func_ref` :46). Note: the original plan text "before `jump`" was WRONG — `jump` is at lir.zig:28, BEFORE the call family. Do NOT place near jump/ret. Fields: `callee: u32, module_id: u32, args_start: u32, args_count: u32, result: u32, return_type: u32, is_indirect: u8`.
2. Add no-op `.tail_call` match cases where LirInst is switched (c89_emit.zig:2215-2243, 2255-2551, 2747-4161, 4178-4217). All 4 switches have `else => {}` catch-alls (2242, 2550, 4160, 4216) so compile will NOT break without these — but add explicit no-op cases per plan. The written_type-scan switch (2255-2551) should mirror the `.call_direct` case (2355-2374) so `tail_call` result temps get written_flag=2 (keeps D4/D9 instrumentation truthful; cosmetic, not required for correct C).
3. Verify no compile errors from match exhaustiveness violations across the codebase.

**Gate:** `bash sf/scripts/build_release.sh` → `=== [release] Done ===`. No errors from new LIR variant.
**Commit:** `feat: F-S1 add tail_call LIR variant`

---

### F-S2 — Lowerer: Tail Detection + TCO Emission

**Files:** `sf/src/lower.zig`, `sf/src/lir.zig` (1-field edit: add `is_extern` to tail_call variant)
**Pre-requisite:** I-M1, F-S1

**Scope:** Detect tail-call positions in `return_stmt` lowering. Emit self-recursion TCO (arg rebind + jump header) or `tail_call` LIR. Inject `loop_header` at function entry. No C89 emitter changes.

**Steps:**
1. In `lowerFn`, after creating the entry basic block, inject `loop_header(entry_bb_id)` as the first instruction. Use `emitInst(self, LirInst{ .loop_header = entry_bb_id });` or equivalent. Ordering note: `hoistTemps` (lower.zig:4181) PREPENDS `decl_temp` instructions to block 0, so the final entry-block order is `decl_temp*`, `loop_header`, body — exactly the "label after temps" requirement for F-S3.
2. **AMENDMENT 2 (detection mechanism):** In `return_stmt` lowering, after `expandDefers`, add tail-call detection via a BOUNDED DEF-USE CHAIN WALK (NOT a tail_pending flag, NOT a full dataflow pass):
   - New private helper `findTailCall(self, ret_temp)` in lower.zig that walks the emitted-LIR def-use chain backward from the return temp, max 5 hops:
     - For each step, scan `self.func.blocks` for the instruction whose `.result` field == current temp
     - If found inst is `.call_direct` → return its info (test self: `name_id == self.func.name_id && module_id == self.func.module_id`)
     - If `.call` (indirect) → return info with `is_self = false`
     - If `.unwrap_error_payload` → continue chain from its `.value`
     - If `.unwrap_error_code` → continue chain from its `.value`
     - Any other inst kind or exceeding 5 hops → return null (not a tail call)
   - Helper self-limits, follows the natural def chain, mutates NO other handler. Single call site: return_stmt (3615-3634).
   - **AMENDMENT 6 (extern handling — OPERATOR RULING B):** Extern callees ARE converted to `tail_call` (do NOT skip them). The `call_direct.is_extern` flag is carried through into the `tail_call` variant. This means: F-S1's `tail_call` variant (lir.zig:46) gains an `is_extern: u8` field (edit lir.zig in this task); `findTailCall` copies `call_direct.is_extern` into CallInfo; Step 4/5 populate `tail_call.is_extern`.
   - Detection outcomes:
     - `call_direct` to self → emit TCO sequence (step 3)
     - `call_direct` to other function → emit `tail_call` LIR ONLY IF `ci.return_type == self.func.return_type` (step 4). **AMENDMENT 11 (same-type-only cross TCO — OPERATOR RULING on F-S4 regression):** if the callee return type DIFFERS from the enclosing fn return type (coercion rewrap, e.g. `fn f() E!*u32 { return getp(); }` where getp returns `*u32`), do NOT emit tail_call — fall through to the normal call_direct+ret path (the coercion wrap produces the correct EU). Reason: zeroChainInsts would nop the semantically-required wrap_error_ok and the tail_call fallback would `return <raw payload>` with the wrong type (dropped EU wrapper → broken C). This fixes the F-S4 regression (extern_fn_eu_return, mi_eu_opt_val).
     - `call` indirect → emit `tail_call` with `is_indirect=1` ONLY IF `ci.return_type == self.func.return_type` (same rule; indirect call return_type is TYPE_UNDEFINED, so it must match the fn type — apply the same guard)
     - otherwise → standard `ret` (unchanged)
   - Must NOT convert the err-path ret of try (lower.zig:2507/2509 — those rets are inside err_bb, not in the return_stmt tail position; the walk only starts from the return_stmt's own ret temp).
3. For self-recursion TCO sequence:
   - Verify `call.args_count == self.func.params.len` (defensive; fallback to `call_direct+ret` on mismatch)
   - **AMENDMENT 7 (try-CFG elimination — F-S2-A design):** `findTailCall` ALSO returns the defining call's position: `call_block_idx: u32`, `call_inst_idx: u32` (the block index and inst index of the call_direct/call in `self.func.blocks`). When TCO fires:
     - (a) Zero the defining call inst: `blocks[call_block].insts[call_inst] = LirInst{ .nop = {} }` (eliminates the retained call — resolves review Finding 2).
     - (b) Zero `check_error`/`check_optional` at `call_inst+1` (if present — try lowering emits `check_error` immediately after `call_direct`).
     - (c) Zero `branch` at `call_inst+2` (if present — kills the only edge into err_bb/ok_bb).
     - (d) Re-walk the chain from the return temp (1-2 hops, same dispatch as findTailCall) and zero every intermediate inst that the walk passed through: `unwrap_error_payload`, `wrap_error_ok`, `wrap_error_err`, `unwrap_error_code` (these read the nop'd call result — now dead).
     - (e) If `call_block != current_bb` (the try case — call lives in bb_call, return_stmt lives in join_bb): save current_bb, set `self.current_bb = call_block_idx`, emit the param-rebind assigns + `jump 0` INTO the call block, restore current_bb. If same block (simple case), emit in current_bb (existing behavior).
     - (f) `block_terminated = 1` (suppresses join_bb's ret; err_bb/ok_bb/join_bb become unreachable dead blocks — they still emit `return`/`unwrap` referencing dead temps, but are never reached; compile with warnings only).
   - For each param i (0..params.len-1): emit `assign local_param[i].temp_id = call.args[args_start+i]`
   - Emit `jump loop_header_bb` (entry block ID, = 0)
   - Set `self.block_terminated = 1` (suppresses the normal `ret` emission at 3629)
4. For cross-function `tail_call`: emit `LirInst{ .tail_call = { ... } }` with all call fields filled INCLUDING `is_extern` (from CallInfo, itself from `call_direct.is_extern`). Set `self.block_terminated = 1`. For indirect calls, `.is_extern = 0`. **AMENDMENT 7 applies equally:** zero the defining call inst + check_error + branch + intermediate chain insts (steps a-d above) before emitting the `tail_call` — otherwise the original call_direct AND the tail_call both remain (double call). Emit `tail_call` in the call block if `call_block != current_bb`.
5. **AMENDMENT 3 (scope clarification):** Handle `if`/`switch` branching return values in STATEMENT form (`if (c) return f();` / `switch { ... => return f(); }`) — these lower to per-branch return_stmt sites (lowerStmtBody at 3220-3301/3520-3613), each processed independently by the return_stmt walk, so TCO applies automatically. The EXPRESSION form (`return if(c) f() else g();` — calls hidden behind join temps) is explicitly OUT OF SCOPE for this plan; it is not in the design spec and is not a Z98 idiom.

**Gate:** Build 0 errors. Stdout md5s: mud `5fb57e70c2d637276ab0264c1401cd0d`, gol `f855c9f93c73422f56378f3f73231727` all byte-identical. **json EXPECTED CHANGE (OPERATOR RULING B):** json md5 becomes `e52d876f...` because json.zig:155 `return file.strtod(...)` (extern) becomes `tail_call` LIR, which the emitter no-ops until F-S3 (transient UB, restored at F-S3). **lisp EXPECTED CHANGE (OPERATOR RULING, Finding 3):** with AMENDMENT 7 the walk now follows `wrap_error_ok`/`wrap_error_err`, so lisp's `return try apply(...)` (eval.zig:169, cross-function) also becomes `tail_call` → lisp md5 becomes a transient (restored at F-S3). lisp's new expected md5 is captured at implementation time (verify it differs from `0ad0204088f91c1eae7c040da8f99a1c` and record it). This is KNOWN TRANSIENT, not a regression to fix in F-S2.
**Commit:** `feat: F-S2 lowerer tail-call detection and TCO emission`

---

### F-S3 — C89 Emitter: Activate `loop_header` + `tail_call` Fallback

**Files:** `sf/src/c89_emit.zig`
**Pre-requisite:** I-M3, F-S1, F-S2

**Scope:** Activate `.loop_header` case in instruction match (emit `tco_restart:` label after temp declarations). Add `.tail_call` case (emit `call`/`call_direct` + `ret` as semantic fallback). No wrapper or trampoline generation.

**Steps:**
1. In the main LIR instruction match block (emitInst, c89_emit.zig:2747-4161), replace `.loop_header => {},` (c89_emit.zig:2754) with:
   ```
   .loop_header => |hdr| {
       bufferedWriterWriteIndent(&emitter.writer, emitter.indent);
       var label_s: []const u8 = "z_bb_0:\n";
       bufferedWriterWrite(&emitter.writer, label_s);
   }
   ```
   **AMENDMENT 4 (label placement):** I-M3 confirmed the label lands AFTER all temp/local declarations automatically. C body layout: hoisted temp decls (2605-2659) → local decls (4171-4221) → bb0 entry-block insts (no label). F-S2 injects `loop_header` as the FIRST instruction of bb0, so the label is emitted at the top of the entry-block stream — after every declaration. This is correct. NOTE: C89 has NO "jump-past-initializer" rule (that is a C++ rule) and emitted decls are all uninitialized, so both placements are C89-legal; after-decls is still the right choice. There is NO `emitLabel()` helper in c89_emit.zig — write the label inline (matches block-label pattern at 4226-4236). `hdr` is the entry-BB id (always 0).
   **AMENDMENT 8 (label NAME — OPERATOR RULING on review Finding 1):** emit `z_bb_0:` (NOT `tco_restart:`). The `.jump` arm (c89_emit.zig:2859-2872) emits `goto z_bb_<id>;`, and self-TCO's `jump 0` emits `goto z_bb_0;` — so the loop_header label MUST be `z_bb_0:` to match the jump target. `tco_restart:` would not match and would leave `goto z_bb_0` undefined. Consequence: EVERY function gets an unused `z_bb_0:` label when no tail call exists → gcc `-Wunused-label` warnings for all functions. Warnings are tolerated (gate = 0 errors only); do NOT try to suppress them.
2. Add `.tail_call` case AFTER the `.call_direct` arm closes (c89_emit.zig:3740), before `.switch_br` (:3741). Emit same C code as `call_direct`/`call` followed by `ret`:
   - Resolve callee: if `is_indirect == 1`, `fn_name = resolveTempName(emitter, tc.callee)` (mirrors `.call` :3581-3582); else `nameManglerMangle(emitter.mangler, tc.callee, 0, tc.module_id)` + `stringInternerGet` (mirrors `.call_direct` :3619-3621)
   - Arg loop: `resolveTempName(emitter, tc.args_start + ai)` per arg (mirrors :3728-3736)
   - If `return_type != TYPE_VOID`: `result = fn_name(args);` then `return result;` else `fn_name(args); return;`
   - **AMENDMENT 6 (extern override — OPERATOR RULING B):** The `tail_call` variant carries `is_extern: u8` (added in F-S2). If `is_extern == 1`, resolve the callee as the ORIGINAL name (mirrors `.call_direct` :3621: `var orig_c = stringInternerGet(emitter.interner, tc.callee); fn_name = orig_c;`), NOT mangled. This restores json correctness: extern `return file.strtod(...)` becomes `zT = strtod(args); return zT;` — byte-identical to the old call_direct+ret output, so json md5 returns to `11a5db1d3d43acf4880e2d157590abe3`.
3. **AMENDMENT 5 (written_type scan):** Add a `.tail_call` case in the written_type-tracking switch (c89_emit.zig:2255-2551) mirroring `.call_direct` (2355-2374) so the result temp gets `written_flag=2` — keeps D4/D9 instrumentation truthful. Cosmetic (decl types come from hoisted_temps), but required to avoid UNWRITTEN markers.
4. Verify no catch-all match case silently absorbs `tail_call` — the `else => {}` at c89_emit.zig:4160 is the dangerous one; the explicit `.tail_call` arm in step 2 must exist or tail calls are silently dropped.

**Gate:** Build 0 errors. Stdout md5s — **AMENDMENT 9 (OPERATOR RULING B, re-baseline all 4):** the all-4-byte-identical gate is REPLACED by re-baselining. AMENDMENT 8's unconditional `z_bb_0:` label appears in every function, so mud/gol gain an unused label line; lisp/json additionally collapse their try-CFG to `zT = f(args); return zT;` (semantically correct for same-type EU returns). NEW expected md5s are captured at implementation time and become the authoritative baselines (record them in the FS3-report). Verify: build 0 errors; try-repro from F-S2-A7 compiles + runs with O(1) stack (the z_bb_0 undefined-label transient is gone); gcc -Wall -Werror on emitted C.
**Commit:** `feat: F-S3 C89 emitter loop_header activation and tail_call fallback`

---

### F-S4 — Gate Sweep

**Files:** none (verification only)
**Pre-requisite:** F-S1, F-S2, F-S3

**Scope:** Full gate verification. No source changes.

**Steps:**
1. Build: `bash sf/scripts/build_release.sh` → 0 errors, `[release] Done`.
2. Stdout md5s: dump mud/gol/lisp/json, verify against the AMENDMENT-9 re-baselined values: mud `9fde02d8a05e951de738e2df5d12b4f7`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `a2e72c86be89cf9e8debf4d3651fc2e9`, json `3492a935883ee91258feece576ba23d5`.
3. TCO repro: create `examples/z98/tco_factorial/main.zig` with accumulator-style factorial. `zig1 --dump-c89 ...` → emitted C has `z_bb_0:` label + `goto z_bb_0;` (AMENDMENT 8). gcc compile + link → `./prog` with large argument produces correct result, no stack overflow.
4. TCO repro `return try`: create self-recursive function with `try` to verify try-unwrap chain detection + try-CFG elimination (AMENDMENT 7).
5. Lisp runtime: `(+ 1 2)` → `> 3`.
6. Multi-module lisp: `--output-dir` build still links and runs.
7. Corpus: run 186-repro classifier. Verify `OK=165 FAIL=15 ICE=6 CRASH=0`.
8. build_test.sh: verify same result as baseline (5/4).
9. **AMENDMENT 10 (Finding-5/defer gate):** verify the known latent issues do NOT cause regressions on the corpus: (a) `var x = self(...); use(x); return x` (Finding 5 — TCO on a used intermediate) — confirm no corpus repro exhibits broken output from this; (b) defer+TCO interaction — confirm the corpus and examples build clean.

**Gate:** All 7 gates pass. Document any deviations.
**Commit:** report-only, no commit (or empty-checkpoint commit if required)

---

### F-S5 — Documentation

**Files:** `sf/docs/tech_docs/07_lir_lowering.md`, `sf/docs/tech_docs/08_c89_emission.md`, `docs/sf/QUICK_REF.md`
**Pre-requisite:** F-S4

**Scope:** Update docs. No source changes.

**Steps:**
1. `07_lir_lowering.md`: Update §TCO section — replace "not implemented" with description of self-recursion TCO mechanism + `tail_call` LIR variant. Add line refs for lowerer tail-detection sites. Document `loop_header` injection at entry block.
2. `08_c89_emission.md`: Add `.loop_header` (label emission) and `.tail_call` (fallback call+ret) to instruction table. Add `tco_restart:` label to function layout diagram. Note C89 cross-function limitation.
3. `docs/sf/QUICK_REF.md`: Add TCO gate recipes. Add `tco_factorial` example to example list.

**Gate:** Doc-only; verify line refs against source.
**Commit:** `docs: F-S5 TCO documentation update`

---

## Execution Notes

- **Sequential:** I-M1 → I-M3 in parallel (independent). Then F-S1 → F-S2 → F-S3 → F-S4 → F-S5 sequentially.
- **Single commit per F-S stage.**
- **All gates pass before proceeding to next stage.**
- **No optimization passes, no `--enable-tco` flag, no trampoline mode.**
- **`tail_call` C89 fallback is intentionally minimal — future backends will optimize it.**
- **Arg-rebinding `.assign` needs NO emitter changes** (I-M3 Q5): the `.assign` arm (c89_emit.zig:2757-2832) already emits `dst = src;` with param-name resolution via `name_id`/`fl_temps` (2784-2787). F-S2 emits `assign { name_id = param.name_id, dst = param.temp_id, src = arg_temp }`.
- **`loop_header` references** (I-M2): only lir.zig:31 (decl) and c89_emit.zig:2754 (no-op). No lower.zig emit sites today. F-S2 adds the first emit site.

## Amendments Record

- **AMENDMENT 1 (F-S1):** `tail_call` insertion at lir.zig:46 (after `call_direct`, before `func_ref`). Original "before `jump`" was wrong (jump at :28 precedes call family).
- **AMENDMENT 2 (F-S2):** Detection = bounded def-use chain walk (`findTailCall`, max 5 hops) from return_stmt. Not a tail_pending flag, not a full dataflow pass.
- **AMENDMENT 3 (F-S2):** `if`/`switch` branching — STATEMENT form in scope (per-branch return_stmt, automatic); EXPRESSION form (`return if(c) f() else g()`) OUT OF SCOPE.
- **AMENDMENT 4 (F-S3):** `tco_restart:` label placement confirmed after-decls via bb0-first-inst injection. No emitLabel helper — write inline. C89 has no jump-past-init rule.
- **AMENDMENT 5 (F-S3):** Add `.tail_call` case to written_type scan (2255-2551) mirroring `.call_direct` (2355-2374) for instrumentation truth.
- **AMENDMENT 6 (F-S2 + F-S3, OPERATOR RULING B):** Extern callees ARE converted to `tail_call` (do not skip). `tail_call` variant gains `is_extern: u8` (added in F-S2 alongside lower.zig). F-S2 populates it from `call_direct.is_extern`; F-S3 uses it to resolve extern callee names as-is (mirrors .call_direct:3621). Net: json md5 changes to `e52d876f` at F-S2 (transient, emitter no-ops tail_call), restored to `11a5db1d` at F-S3 (is_extern override emits `strtod(...)` as-is → byte-identical).
- **AMENDMENT 7 (F-S2, F-S2-A design — OPERATOR RULING on review Findings 2+3):** Try-CFG elimination. `findTailCall` returns `call_block_idx` + `call_inst_idx`. On TCO: zero the defining call inst → nop; zero `check_error`/`branch` at +1/+2; re-walk the chain and zero intermediate `unwrap_error_payload`/`wrap_error_ok`/`wrap_error_err`/`unwrap_error_code` insts; emit rebind+jump (self) or `tail_call` (cross) into the CALL block when `call_block != current_bb`. Resolves: (2) retained-call double-call/stack-growth, (3) try-chain never converts (walk now follows wraps). Gate consequence: lisp becomes a KNOWN TRANSIENT at F-S2 (its `return try apply` is cross-function → tail_call → emitter no-ops), restored at F-S3.
- **AMENDMENT 8 (F-S3, OPERATOR RULING on review Finding 1):** The `.loop_header` case emits `z_bb_0:` label (NOT `tco_restart:`), matching the `.jump` arm's `goto z_bb_<id>;` target. Consequence: every function gets an unused `z_bb_0:` label → gcc `-Wunused-label` warnings (tolerated, 0-error gate).
- **AMENDMENT 9 (F-S3, OPERATOR RULING B):** All-4-byte-identical md5 gate REPLACED by re-baselining. AMENDMENT 8's unconditional label breaks mud/gol identity; lisp/json additionally collapse try-CFG. New md5s captured at implementation time, become authoritative baselines.
- **AMENDMENT 11 (F-S2 fix, OPERATOR RULING on F-S4 regression):** Same-type-only cross TCO. Cross-function tail_call (and indirect call) only fires when `ci.return_type == self.func.return_type`. Type-changing coercion (wrap_error_ok into a different EU) falls back to normal call_direct+ret. Fixes extern_fn_eu_return + mi_eu_opt_val corpus regressions.
