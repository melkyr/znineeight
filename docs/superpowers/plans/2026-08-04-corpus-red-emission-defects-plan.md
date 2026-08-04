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
- Corpus: 184/8/0/0 baseline over 192 repros. FAIL count must not increase. Emission-defect fixes decrease FAIL.
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

**Scope:** `.undefined_const` array initialization for tagged-union elements writes only `[_i].tag = 0;` — the payload is never zeroed/copied. This leaves the array-of-TU with an uninitialized payload, so `switch(arr[i])` reads garbage. Fix: for tagged-union elements, also zero the payload union (or emit a per-element zero-init that covers the full union size).

- [ ] **Step 1: Read the handler**

Read `sf/src/c89_emit.zig:3719-3765` (`.undefined_const`). The tagged-union element case at :3740-3743 emits `result[_i].tag = 0; _i++;` — nothing touches the payload.

- [ ] **Step 2: Verify root cause**

Confirm the repro (`array_tagged_union_read`, prints 6 not 7) is caused by this. Check whether the array is initialized via `.undefined_const` or via explicit array-literal copy. If the repro uses an explicit `[2]Command{ Command{.Go=3}, Command{.Go=4} }` literal, the path may be different (array-copy, not undefined_const). Investigate which path actually fires before editing.

**If `.undefined_const` fires:** the fix zeroes the whole element. For a tagged union, emit a byte-level zero-init loop, OR emit `.tag = 0;` plus zero the payload. Simplest correct C89: loop over bytes of the element:
```c
result[_i].tag = 0;
```
must become something that also covers the payload — since C89 can't `memset` a union member easily, consider emitting a nested zero for each non-void TU variant field, or falling back to `result[_i] = *result; /* self */` (invalid). **Investigate the actual emission path first; if the array is populated by per-element store_field (not undefined_const), the fix is in the array-copy path (`emitBaseIdxAccess` element copy) instead.** Do NOT edit until the firing path is confirmed.

- [ ] **Step 3: Implement the confirmed fix**

Implement per the confirmed root cause. Provide exact old→new code in the report.

- [ ] **Step 4: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p2a repro/mi_matrix/array_tagged_union_read/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p2a/*.c
gcc -m32 /tmp/p2a/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p2a/prog
/tmp/p2a/prog
```
Expected: gcc-clean, prints `7` (was 6). 4 MD5s byte-identical. Corpus FAIL 8→7.

- [ ] **Step 5: Commit**

```bash
git add sf/src/c89_emit.zig
git commit -m "fix(P2): array-of-tagged-union element zero-init copies payload (I-R4 Bug2)"
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

4 MD5s byte-identical. Corpus: var_declared_void moves from emission-defect to frontend-gap (still FAIL, but correct-rejection category — reclassify in EXPECTED_FAIL.md).

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
Expected: gcc-clean, correct arena offset behavior. 4 MD5s byte-identical. Corpus FAIL 8→7 (or 7→6 counting the var_declared_void reclassification).

- [ ] **Step 3: Commit**

```bash
git add <fixed files>
git commit -m "fix(P2): ptroint arena offset undeclared temp (P2-1 investigation)"
```
