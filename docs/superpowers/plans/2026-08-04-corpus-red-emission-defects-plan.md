# Corpus-RED 3 Emission Defects — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 3 emission defects — repros that dump rc=0 but gcc rejects the emitted C.

**Architecture:** Four tasks. P2-1 is a full root-cause investigation of `ptroint_arena_offset` (no prior I-R coverage), ending in a STOP for operator ruling. P2-2 fixes `array_tagged_union_read` (I-R4 Bug 2). P2-3 fixes `var_declared_void` (sema void-var rejection). P2-4 implements the P2-1-approved fix for `ptroint_arena_offset`.

**Design spec:** `docs/superpowers/specs/2026-08-04-corpus-red-remaining-design.md` (Plan 2 section)

**Tech Stack:** Z98 (zig0 → zig1 → gcc -m32 -std=c89)

## Global Constraints

- Build in /tmp via the QUICK_REF bootstrap recipe (NOT `sf/build/out_release/` — that folder causes timeouts). See QUICK_REF "LISP refactor testing" ~line 244:
  ```bash
  OUT=/tmp/zb
  rm -rf "$OUT" && mkdir -p "$OUT"
  ./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
  ```
  Gate: 0 gcc errors (`error:` count == 0).
- 4 MD5 baselines byte-identical throughout: mud `4644ad1349c55af80fa1a18fe0e17989`, gol `d0d3051d1cb1bd0db3ffd29495a2e18e`, lisp `f84c8748e6d0580ffac811d75e34e0e7`, json `3492a935883ee91258feece576ba23d5`
- Corpus: **188/9/0/0 baseline over 197 repros** (post-Plan-1, 2026-08-04; Plan 1 added 5 repros — 4 defensive + lzw guard — and the xmod repro became OK). FAIL count must not increase. Emission-defect fixes decrease FAIL. The 9 FAILs = 3 emission defects (`array_tagged_union_read`, `ptroint_arena_offset`, `var_declared_void`) + 5 frontend gaps (`catch_block_value_producing`, `eu_assign_incompat_payload`, `field_access_optional`, `field_store_drop`, `test_stub_0`) + 1 documented residual (`self_embed_optional_cycle`).
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4). test_semantic_bin KNOWN pre-existing broken (operator ruling A).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains.
- QUICK_REF.md reference mandatory for all gates.

---

### Task P2-1: Investigate ptroint_arena_offset (I-task, no prior coverage)

**Files:** investigation only → `.superpowers/sdd/P2-ptroint-report.md`

**Scope:** Full root-cause investigation of `repro/mi_matrix/ptroint_arena_offset` (gcc rejects emitted C — undeclared temps from `@ptrToInt`/`@intToPtr` arena arithmetic). No prior I-R report exists for this repro.

- [ ] **Step 1: Read docs + repro**

Read the repro source, NOTES.md, EXPECTED_FAIL.md entry. Read tech docs 03 (type resolution), 08 (C89 emission) for `@ptrToInt`/`@intToPtr` handling.

- [ ] **Step 2: Reproduce + trace**

```bash
OUT=/tmp/p2
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
"$OUT/zig1" --dump-c89 --output-dir /tmp/p2r repro/mi_matrix/ptroint_arena_offset/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p2r/*.c 2>&1 | head
```
Capture the exact gcc error. Trace the `@ptrToInt`/`@intToPtr` lowering path (lower.zig) and C emission (c89_emit.zig) with markers.

- [ ] **Step 3: Root cause + A/B/C options**

Identify why the emitted C has undeclared temps. Provide A/B/C fix options with file:line targets, blast radius. Green variant (`usize` index instead of pointer arithmetic) is the control.

- [ ] **Step 4: Report**

Write the report to `.superpowers/sdd/P2-ptroint-report.md`. STOP for operator review of the recommended option.

---

### Task P2-2: Fix array_tagged_union_read (I-R4 Bug 2)

**Files:** `sf/src/c89_emit.zig:3740-3743`

**Pre-requisites:** None.

**Scope:** Root-cause fix of the comptime-fold integer typing so a tagged-union payload store compiles. The repro `array_tagged_union_read` fails because `@intCast(i32, N)` comptime-folded consts are typed **USIZE** (lower.zig:2451-2464 `fold_ty_box` default) instead of the `@intCast` target type (I32). The TU payload store emitter then finds no exact type-id match (`USIZE≠I32`) and emits invalid bare-`.payload` C. **The fix must make the folded const carry the correct target type — NOT add an emitter-side fallback.**

> **AMENDMENT P2-2 (operator ruling, 2026-08-04):** the first P2-2 implementation (commit c4531c92) added an integer-compat fallback in the TU payload emitter (`emitFieldAssign`/`.store_field`) and was **REJECTED by the operator** ("reject that fallback chain of doom as it will rot on maintenance"). The root cause is upstream: the comptime fold at `lower.zig:2451-2464` types `@intCast(i32, N)` folded consts as USIZE (the `fold_ty_box` default) because `resolvedTypeTableGet` for the node does not yield the target type in this context. This task fixes the fold typing so the const carries the `@intCast` target type; the emitter's exact-match path then works unchanged. No fallback added.

- [ ] **Step 1: Read the handler**

Read `sf/src/c89_emit.zig:3719-3765` (`.undefined_const`). The tagged-union element case at :3740-3743 emits `result[_i].tag = 0; _i++;` — nothing touches the payload.

- [ ] **Step 2: Confirm root cause (fold typing)**

The repro `array_tagged_union_read` uses an explicit array literal: `var arr: [2]Command = [2]Command{ Command{ .Go = @intCast(i32, 3) }, Command{ .Go = @intCast(i32, 4) } };`. Confirmed (P2-2 v1 investigation, `.superpowers/sdd/task-P2-2-report.md`): `.undefined_const` does NOT fire (marker `UCT:r` count = 0), the array-copy loop is whole-struct and fine. The defect is the TU payload store: the folded const temp is typed **USIZE** (13) — `HT:zT_3(13->13)w1` — while the `Go` variant is **I32** (6), so the exact type-id match fails and the emitter falls back to bare `zT_2.payload = zT_3;` (invalid C89).

The fold is at `lower.zig:2451-2464`: `fold_ty_box` defaults to `TYPE_USIZE`; for `@intCast` nodes it is overridden from `resolvedTypeTableGet` only when the resolved type is a valid non-USIZE/UNDEFINED/INT_LIT type. Confirm WHY `resolvedTypeTableGet` does not yield I32 for the `@intCast` node here (markers/GDB): is the resolved-type entry absent, USIZE, UNDEFINED, or INT_LIT at lowering time? This is the root cause to fix — the folded const must be typed with the `@intCast` **target** type (I32). Note `@intCast(i32, N)` resolves to I32 in sema (`semantic_analyzer.zig:1241-1245`, result = `resolveTypeExprFull(ec[0])`), so the resolved-type table SHOULD carry it; determine why lowering sees otherwise.

- [ ] **Step 3: Implement the root-cause fix (fold typing)**

Fix at the fold site so `@intCast(<target>, const)` folded consts are typed with the target type (not USIZE). Exact approach per Step-2 findings — e.g. resolve the `@intCast` target type directly (the type expression is `node`'s first extra child via `astStoreGetExtraChildren`) when `resolvedTypeTableGet` is unavailable/unreliable, or fix the resolved-type lookup. Do NOT add an emitter fallback. Provide exact old→new code. If Step-2 reveals the true root cause is elsewhere (e.g. sema stores a wrong resolved type for the node), fix THAT — always address the root, never mask with an emitter fallback.

- [ ] **Step 4: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p2a repro/mi_matrix/array_tagged_union_read/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p2a/*.c
gcc -m32 /tmp/p2a/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p2a/prog
/tmp/p2a/prog
```
Expected: gcc-clean, prints `7` (was 6). 4 MD5s byte-identical. Corpus FAIL 9→8.

- [ ] **Step 5: Commit**

```bash
git add sf/src/lower.zig [sf/src/semantic_analyzer.zig]
git commit -m "fix(P2): comptime-folded intcast consts carry target type (array_tagged_union_read)"
```

---

### Task P2-3: Fix var_declared_void (sema void-var rejection)

**Files:** `sf/src/semantic_analyzer.zig:1615-1621`

**Pre-requisites:** None.

**Scope:** `var x = void_expr;` is never rejected by sema. The lowerer emits a VOID temp that c89_emit correctly suppresses → `'x' undeclared`. Root fix: sema should reject declaring a variable whose resolved type is VOID.

- [ ] **Step 1: Read the var_decl handler**

Read `sf/src/semantic_analyzer.zig:1581-1660` (var_decl resolution). After `var it = semanticAnalyzerResolveExpr(self, node.child_1);` at :1620, `decl_type` is either annotated or inferred from the init.

- [ ] **Step 2: Add void-var rejection**

After the init resolution (after :1621 `popExpectedType`), add:
```zig
                if (decl_type == type_mod.TYPE_VOID) {
                    var sp = node.span_start;
                    var ep = sp + @intCast(u32, node.span_len);
                    var vv_msg: []const u8 = "cannot declare variable of type void";
                    _ = diag_mod.diagnosticCollectorAdd(self.diag, @intCast(u8, 0), @intCast(u16, @enumToInt(diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH)), self.source_file_id, sp, ep, vv_msg);
                }
```
Use ERR_3000 (type mismatch) with a clear message. `ERR_3000_TYPE_MISMATCH` confirmed at diagnostics.zig:30.

- [ ] **Step 3: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p2v repro/mi_matrix/var_declared_void/main.zig 2>&1
```
Expected: dump rc=2 with `error[3000]: cannot declare variable of type void`, 0 .c emitted. This converts a gcc-FAIL into a frontend-gap FAIL (correct rejection). Reclassify the repro accordingly.

4 MD5s byte-identical. Corpus: `var_declared_void` moves from emission-defect to frontend-gap correct-rejection.

> **AMENDMENT P2-3 (operator ruling, 2026-08-04):** the unconditional void-var rejection ALSO flips `euvoid_val_catch` (`var r = h() catch {};` — void-typed init) from OK→FAIL — a latent void-var acceptance bug, semantically correct to reject (Zig forbids void variables). OPERATOR RULING: **accept + reclassify BOTH `var_declared_void` AND `euvoid_val_catch` as green-guards (correct rejections)** in EXPECTED_FAIL.md. Accounting after P2-3: **OK=188 / FAIL=7 / green-guards=2 / ICE=0 / CRASH=0 @197** (var_declared_void: FAIL→green-guard; euvoid_val_catch: OK→green-guard; FAIL 8→7). Add a "Green-guards (correct rejection)" section in EXPECTED_FAIL.md documenting both, mirroring the Plan 3 P3-1 convention. Note: use the file's existing `@intCast(u16, 3000)` diagnostic pattern (semantic_analyzer.zig:1664) — `@enumToInt(ERR_3000_TYPE_MISMATCH)` has implicit ordinal 19 and would emit `error[19]`, not `error[3000]`.

- [ ] **Step 4: Commit**

```bash
git add sf/src/semantic_analyzer.zig repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix(P2): reject void-typed variable declarations in sema (var_declared_void)"
```

---

### Task P2-4: Fix ptroint_arena_offset (per P2-1 investigation)

**Files:** per `.superpowers/sdd/P2-ptroint-report.md` recommended option

**Pre-requisites:** P2-1 (investigation report) + operator ruling on the option.

**Scope:** Implement the operator-approved root fix for the `@ptrToInt`/`@intToPtr` arena arithmetic undeclared-temp defect.

> **AMENDMENT P2-1 (operator ruling, 2026-08-04):** per `.superpowers/sdd/P2-ptroint-report.md`, implement **Option A + Option B** together:
> - **A (sema, root cause):** `semanticAnalyzerResolveArithmetic` (semantic_analyzer.zig:495, :498) — treat `TYPE_INT_LIT` as a valid pointer-arithmetic offset (`rhs_uint = typeRegistryIsUnsigned(self.registry, rhs) or rhs == type_mod.TYPE_INT_LIT`, and the symmetric lhs check). Covers `ptr ± lit` and `lit + ptr`. Zero blast radius.
> - **B (emission hardening):** `emitHoistedDecls` (c89_emit.zig:2727-2746) — use the `written_type` override whenever `written_flag == 1` (not only for TYPE_UNDEFINED), per Option B in the report. Defends the whole class of "VOID temp assigned in body".
> - **Gate:** because Option B widens the emission footprint, run the FULL corpus classifier + all 4 MD5 gates to prove no drift (the FAIL set must only lose `ptroint_arena_offset`; no OK→FAIL flips; MD5s byte-identical).
> - The 1-arg `@ptrToInt` wrong-type quirk (semantic_analyzer.zig:1253) is OUT of scope — documented follow-up.

> **AMENDMENT P2-4 (operator ruling, 2026-08-04):** the original Option B (override on `written_flag==1` unconditionally) REGRESSED the corpus (+3 FAIL, MD5 drift) — `written_type` (c89_emit.zig:2384-2668) is a per-arm heuristic trustworthy only when the hoisted `type_id == TYPE_UNDEFINED`; on non-UNDEFINED temps it disagrees (VOID overwrites skip needed decls; usize/U32 overwrites corrupt `Mode` payload temps). Investigation (`.superpowers/sdd/P2-optB-report.md`) re-scoped B: apply the override ONLY when the hoisted temp's `type_id ∈ {TYPE_VOID, TYPE_UNDEFINED}` AND `written_type` is a valid non-VOID, non-0xFFFFFFFF type. Verified empirically (zero blast radius): corpus `ptroint_arena_offset` FAIL→OK only, whole-corpus byte-diff = 1 file, 4 MD5s byte-identical. **P2-4 = Option A + scoped B.**

- [ ] **Step 1: Apply the approved fix**

Per the P2-1 report's chosen option, make the file:line edits.

- [ ] **Step 2: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p2p repro/mi_matrix/ptroint_arena_offset/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p2p/*.c
gcc -m32 /tmp/p2p/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p2p/prog
/tmp/p2p/prog
```
Expected: gcc-clean, correct arena offset behavior. 4 MD5s byte-identical. Corpus FAIL 9→8 (or 8→7 counting the var_declared_void reclassification).

- [ ] **Step 3: Commit**

```bash
git add <fixed files>
git commit -m "fix(P2): ptroint arena offset undeclared temp (P2-1 investigation)"
```

---

## Amendments Record

- **AMENDMENT P2-0 (2026-08-04, operator ruling):** Global Constraints corpus baseline updated from the stale pre-Plan-1 `184/8/0/0 @192` to the post-Plan-1 **`188/9/0/0 @197`** (Plan 1 added 5 repros; xmod became OK). FAIL expectations in P2-2/P2-4 renumbered accordingly (9→8 / 9→8-or-8→7). MD5 baselines unchanged and current.
- **AMENDMENT P2-1 (2026-08-04, operator ruling):** P2-4 implements **Option A + Option B** from the P2-1 report (sema ptr±literal fix + emission written_type override), with a full corpus + 4-MD5 re-gate. See P2-4 scope note.
- **AMENDMENT P2-2 (2026-08-04, operator ruling):** P2-2 rewritten from an emitter-fallback fix to the ROOT-CAUSE fix. The first implementation (c4531c92, TU-payload integer-compat fallback) was REJECTED ("reject that fallback chain of doom"). Root cause: comptime fold at lower.zig:2451-2464 types `@intCast(i32,N)` folded consts as USIZE instead of the target type. Fix the fold typing; NO emitter fallback.
- **AMENDMENT P2-3 (2026-08-04, operator ruling):** P2-3 reclassifies BOTH `var_declared_void` and `euvoid_val_catch` as green-guards (correct rejections) — the unconditional void-var rejection also flips `euvoid_val_catch` OK→FAIL (latent void-var acceptance bug; Zig forbids void variables). Post-P2-3 accounting: OK=188 / FAIL=7 / green-guards=2 @197. Use `@intCast(u16, 3000)` not `@enumToInt` (ordinal-19 pitfall). See P2-3 note.
- **AMENDMENT P2-4 (2026-08-04, operator ruling):** P2-4 = Option A + SCOPED B. Original B regressed corpus (+3 FAIL, MD5 drift); re-scoped to apply the written_type override ONLY when hoisted type_id ∈ {TYPE_VOID,TYPE_UNDEFINED} AND written_type valid non-VOID/non-0xFFFFFFFF. Zero blast radius verified. See P2-4 note.
