# Corpus-RED Remaining — 3-Plan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve the remaining corpus-RED work: deferred items + defensive repros + full runtime battery (Plan 1), the 3 emission defects (Plan 2), and the frontend gaps + reclassifications (Plan 3).

**Architecture:** Three independent plans executed in order. Plan 1 creates defensive repros for deferred items and runs the full 18-example runtime battery. Plan 2 investigates and fixes the 3 emission defects. Plan 3 reclassifies green-guards, defers import-gaps, and investigates the anon-set comparison + catch-block gaps.

**Design spec:** `docs/superpowers/specs/2026-08-04-corpus-red-remaining-design.md`

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
- Repro convention: every new repro needs `main.zig` (+ optional `main_green.zig`), `NOTES.md` documenting classification, and a row in `repro/mi_matrix/EXPECTED_FAIL.md`.
- Example runtime battery: link against `sf/src/include/zig_runtime.c` + `zig_pal.c` (mud_server adds `net_runtime.c`; json_parser uses legacy `src/runtime/zig_runtime.c` compiled to `/tmp/rt.o` + needs `test.json` in CWD).

---

# PLAN 1: Deferred Items + Defensive Repros + Runtime Battery

### Task P1-1: Create 5 Defensive Repros

**Files:**
- Create: `repro/mi_matrix/xmod_global_field_access/main.zig`, `lib.zig`, `main_green.zig`, `NOTES.md`
- Create: `repro/mi_matrix/self_embed_optional_cycle/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/load_global_array_copy/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/anon_errset_comparison/main.zig`, `main_green.zig`, `NOTES.md` (Plan 1 placeholder — investigation is Plan 3 Task P3-3)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add rows + update totals)

**Scope:** Five defensive repros, one per deferred item. Document current classification honestly — some are expected FAIL/ICE today, some OK-with-optimization-note.

- [ ] **Step 1: Create `xmod_global_field_access`**

Files:
`lib.zig`:
```zig
pub var counter: i32 = 0;
pub fn bump() void {
    counter = counter + 1;
}
```
`main.zig` (RED — cross-module global field access):
```zig
const lib = @import("lib.zig");
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    lib.bump();
    lib.bump();
    __bootstrap_print_int(lib.counter);
}
```
`main_green.zig` (GREEN — same-module control):
```zig
var counter: i32 = 0;
fn bump() void {
    counter = counter + 1;
}
extern fn __bootstrap_print_int(n: i32) void;
pub fn main() void {
    bump();
    bump();
    __bootstrap_print_int(counter);
}
```
`NOTES.md`: Document expected classification — RED likely FAIL gcc (or warning[3023] + uninit read) because `lower.zig:1850-1871` module field-access path handles `type_alias`/`function` but NOT `SymbolKind.global`. GREEN should be OK (module-local global via F-7 `load_global`).

- [ ] **Step 2: Create `self_embed_optional_cycle`**

`main.zig`:
```zig
const X = struct {
    next: ?X,
};
pub fn main() void {
    var x: X = undefined;
    x.next = null;
    _ = x;
}
```
`NOTES.md`: Document this as the F-8 residual — infinite-size C type (struct X { struct X next; int has_value; } recursion). Expected: either ICE on topo 2-cycle or gcc incomplete-type. This repro GUARDS the documented residual, not a fix.

- [ ] **Step 3: Create `load_global_array_copy`**

`main.zig`:
```zig
extern fn __bootstrap_print_int(n: i32) void;
pub var buf: [16]i32 = undefined;
pub fn main() void {
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        buf[i] = @intCast(i32, i);
    }
    __bootstrap_print_int(buf[3]);
    __bootstrap_print_int(buf[15]);
}
```
`NOTES.md`: Expected OK — values 3 and 15 print correctly. Optimization note: F-7's `load_global` emits a dead copy-loop (temp_global_map redirection) that is correct but wasteful for large arrays. This repro GUARDS correctness; the optimization is a separate future task.

- [ ] **Step 4: Create `anon_errset_comparison` (repro only, investigation deferred to P3-3)**

`main.zig` (RED):
```zig
extern fn __bootstrap_print_int(n: i32) void;
fn f() !i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        if (err == error.Bad) { __bootstrap_print_int(@intCast(i32, 1)); }
        else { __bootstrap_print_int(@intCast(i32, 0)); }
        return;
    };
    _ = r;
}
```
`main_green.zig`:
```zig
const E = error{ Bad };
extern fn __bootstrap_print_int(n: i32) void;
fn f() E!i32 {
    return error.Bad;
}
pub fn main() void {
    var r = f() catch |err| {
        if (err == error.Bad) { __bootstrap_print_int(@intCast(i32, 1)); }
        else { __bootstrap_print_int(@intCast(i32, 0)); }
        return;
    };
    _ = r;
}
```
`NOTES.md`: RED tests bare-`!` error-set comparison (`err == error.Bad` on anonymous set). GREEN is the explicit-error-set control. Classification: document measured result (likely OK* runtime gap — raw name_id may miscompare) — the root-cause investigation is Plan 3 Task P3-3. This repro's existence here is the Plan 1 deliverable.

- [ ] **Step 5: Update EXPECTED_FAIL.md**

Add all 4 new repros to the classification table with measured classifications (run each through the QUICK_REF corpus classifier first). Update the totals line to reflect +4 repros (192 → 196). Add a "Defensive repros (Plan 1, 2026-08-04)" section documenting each as guarding a deferred item.

- [ ] **Step 6: Verify gates**

```bash
# Classify each new repro with the QUICK_REF corpus classifier
for d in xmod_global_field_access self_embed_optional_cycle load_global_array_copy anon_errset_comparison; do
  /tmp/zb/zig1 --dump-c89 --output-dir /tmp/p1/$d repro/mi_matrix/$d/main.zig
  echo "$d: dump rc=$? files=$(ls /tmp/p1/$d/*.c 2>/dev/null | wc -l)"
done
```
Expected: `xmod_global_field_access` → likely FAIL or warning+uninit (document actual); `self_embed_optional_cycle` → ICE or incomplete-type (document actual); `load_global_array_copy` → OK, prints 3 and 15 when linked+run; `anon_errset_comparison` → document measured result (gcc-clean or runtime gap).

4 MD5s byte-identical. Corpus totals updated to 196 repros.

- [ ] **Step 7: Commit**

```bash
git add repro/mi_matrix/
git commit -m "repro(P1): 4 defensive repros for deferred items + EXPECTED_FAIL update"
```

---

### Task P1-2: Fix Cross-Module Global Field Access

**Files:** `sf/src/lower.zig:1850-1871`

**Pre-requisites:** P1-1 (repro exists).

**Scope:** Add a `SymbolKind.global` branch to the module field-access path so `lib.counter` reads the actual global via `load_global`.

- [ ] **Step 1: Read the module field-access path**

Read `sf/src/lower.zig:1840-1875`. The `if (s.kind == sym_mod.SymbolKind.module)` block at :1850-1871 handles `type_alias` (:1854-1859) and `function` (:1860-1869) but falls through for `global`.

- [ ] **Step 2: Add the global branch**

Inside the `if (res_sym) |ts| {` block, after the `function` branch (:1860-1869), ADD:

```zig
                        } else if (ts.kind == sym_mod.SymbolKind.global) {
                            var gbl_type = resolved_mod.resolvedTypeTableGet(self.ctx.resolved_types, ts.decl_node);
                            var gbl_tid = if (gbl_type) |gt| gt else type_mod.TYPE_UNDEFINED;
                            var gtemp = nextTemp(self, gbl_tid);
                            emitInst(self, LirInst{ .load_global = .{ .name_id = ts.name_id, .module_id = target_mod, .result = gtemp } });
                            return gtemp;
```

- [ ] **Step 3: Build + gate**

```bash
OUT=/tmp/p1b
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
```
Expected: 0 gcc errors.

```bash
# Repro gate: cross-module global now reads the real global
"$OUT/zig1" --dump-c89 --output-dir /tmp/p1g repro/mi_matrix/xmod_global_field_access/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/p1g/*.c
gcc -m32 /tmp/p1g/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p1g/prog
/tmp/p1g/prog
```
Expected: gcc-clean, prints `2` (two bumps → counter=2).

```bash
# MD5 gate (all 4 byte-identical)
"$OUT/zig1" --dump-c89 examples/z98/lisp_interpreter_curr/main.zig | md5sum
"$OUT/zig1" --dump-c89 examples/z98/json_parser/main.zig | md5sum
"$OUT/zig1" --dump-c89 examples/z98/mud_server/main.zig | md5sum
"$OUT/zig1" --dump-c89 examples/z98/game_of_life/main.zig | md5sum
```
All match baselines.

- [ ] **Step 4: Commit**

```bash
git add sf/src/lower.zig
git commit -m "fix(P1): cross-module global field access via load_global"
```

---

### Task P1-3: Full 18-Example Runtime Battery

**Files:** none (verification only). Report to `.superpowers/sdd/P1-battery-report.md`.

**Pre-requisites:** P1-2 (compiler built).

**Scope:** Run all 18 z98 examples through dump → gcc -c → link → run. Capture current state, including the 3 BROKEN examples' current error counts (may have changed post-F-1..F-9).

- [ ] **Step 1: Build the compiler**

```bash
OUT=/tmp/p1c
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
```

- [ ] **Step 2: Standard examples (13)**

For each of: hello, prime, fibonacci, quicksort, heapsort, lzw, days_in_month, func_ptr_return, sort_strings, mandelbrot, game_of_life, lisp_interpreter_curr, mud_server — run:
```bash
"$OUT/zig1" --dump-c89 --output-dir /tmp/p1/<name> examples/z98/<name>/<ENTRY>.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/p1/<name>/*.c
gcc -m32 /tmp/p1/<name>/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c [net_runtime.c for mud_server] -o /tmp/p1/<name>/prog
timeout 10 /tmp/p1/<name>/prog
```
Note: mud_server adds `net_runtime.c`; game_of_life uses `system("cls")` (ignore `cls: not found` stderr). Record per-example: dump rc, gcc rc, run output/exit.

**lzw specifically:** verify it compiles AND runs with correct LZW compression output (this was the operator's concern — lzw was never run between gates).

- [ ] **Step 3: Special examples (2)**

`json_parser` (legacy runtime + test.json):
```bash
"$OUT/zig1" --dump-c89 --output-dir /tmp/p1/json examples/z98/json_parser/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c /tmp/p1/json/*.c
gcc -m32 -c -std=c89 -Wno-long-long -Wno-pointer-sign /workspace/znineeight/src/runtime/zig_runtime.c -o /tmp/rt.o
gcc -m32 /tmp/p1/json/*.o /tmp/rt.o /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p1/json/prog
cd /workspace/znineeight/examples/z98/json_parser && cp test.json /tmp/p1/json/ && cd /tmp/p1/json && ./prog test.json
```

`lisp_interpreter_adv`:
```bash
"$OUT/zig1" --dump-c89 --output-dir /tmp/p1/lispadv examples/z98/lisp_interpreter_adv/main.zig
# standard gcc + run
```
Document the known define→call-returns-nil bug still present.

- [ ] **Step 4: Re-measure the 3 BROKEN**

For lisp_interpreter, json_parser_workaround, rogue_mud — run dump ONLY and capture the current error count:
```bash
"$OUT/zig1" --dump-c89 --output-dir /tmp/p1/<name> examples/z98/<name>/main.zig 2>&1 | head -5
echo "dump rc=$?"
```
Compare against the documented pre-fix error counts in their NOTES.md. Report any change (e.g., json_parser_workaround's error[3043] ICE may have changed post-F-3/F-8).

- [ ] **Step 5: lisp stressed battery**

Using `examples/z98/lisp_interpreter_curr/stress_expressions.md` (and the binary built for lisp_interpreter_curr in Step 2), run the stress expressions by piping them as REPL input:
```bash
printf '(+ 1 2)\n(fact 5)\n(fib 7)\n(even? 1000)\n(countdown 5000)\n(countdown 10000)\n' | timeout 15 /tmp/p1/lisp_interpreter_curr/prog
```
Expected: 3, 120, 13, true, 0, then OutOfMemory (arena limit at countdown 10000).

- [ ] **Step 6: Write report + commit**

Write `.superpowers/sdd/P1-battery-report.md` with the per-example table (dump rc / gcc rc / run output / BROKEN error counts) and the lisp stressed results. Update EXPECTED_FAIL.md and NOTES.md if any BROKEN example's error count changed materially.

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md examples/z98/*/NOTES.md
git commit -m "docs(P1): full 18-example runtime battery + lisp stressed verification"
```

---

# PLAN 2: 3 Emission Defects

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
Use ERR_3000 (type mismatch) with a clear message. Verify `diag_mod.ErrorCode.ERR_3000_TYPE_MISMATCH` is the correct enum name (grep diagnostics.zig first).

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

---

# PLAN 3: Frontend Gaps + Reclassifications

### Task P3-1: Reclassify 2 Green-Guard Repro Configurations

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Scope:** `eu_assign_incompat_payload` (error[3000] EU payload mismatch) and `field_access_optional` (error[3000] `.` on optional) are CORRECT rejections matching the zig0 oracle — green guards, not defects. Reclassify them out of the FAIL count into a distinct green-guard bucket.

- [ ] **Step 1: Verify both are correct rejections**

```bash
OUT=/tmp/p3
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3a repro/mi_matrix/eu_assign_incompat_payload/main.zig 2>&1 | head -3
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3b repro/mi_matrix/field_access_optional/main.zig 2>&1 | head -3
# Also verify zig0 oracle rejects identically:
./sf/build/zig0 -o /tmp/p3o1.c repro/mi_matrix/eu_assign_incompat_payload/main.zig 2>&1 | head -3
```
Confirm both zig1 and zig0 reject with error[3000] and emit 0 .c.

- [ ] **Step 2: Reclassify in EXPECTED_FAIL.md + QUICK_REF.md**

Move both to a new "Green-guards (correct rejection, not a defect)" section. Update the corpus accounting: 184 emission/sema OK + 2 green-guards + 2 import-gap FAIL + 3 emission-defect FAIL + 1 catch-block FAIL = 192. Document the classifier rule: green-guards are counted separately from FAIL (a green-guard moving to OK/FAIL is a regression).

- [ ] **Step 3: Verify + commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs(P3): reclassify eu_assign_incompat_payload + field_access_optional as green-guards"
```

---

### Task P3-2: Defer the 2 Import-Gap Repros (document only)

**Files:** `repro/mi_matrix/EXPECTED_FAIL.md`, `docs/sf/QUICK_REF.md`

**Scope:** `field_store_drop` (error[3048] cannot import `"pal"`) and `test_stub_0` (error[3048] cannot import `"std"`) fail because user programs cannot import compiler-internal modules — no std lib exists yet. Defer to the std-lib milestone.

- [ ] **Step 1: Document the deferral**

Add a "Deferred to std-lib" section in EXPECTED_FAIL.md and a note in QUICK_REF.md listing both with the error[3048] cause and "will pass when zig1 gains a real std lib." These remain FAIL but are tracked as std-lib-deferred, not compiler defects.

- [ ] **Step 2: Verify + commit**

```bash
git add repro/mi_matrix/EXPECTED_FAIL.md docs/sf/QUICK_REF.md
git commit -m "docs(P3): defer field_store_drop + test_stub_0 to std-lib milestone"
```

---

### Task P3-3: Investigate anon-set comparison (anon_errset_comparison)

**Files:** investigation → `.superpowers/sdd/P3-anonerr-report.md`; possible fix in `sf/src/` per findings.

**Pre-requisites:** P1-1 Step 4 (repro exists).

**Scope:** Determine whether `err == error.Bad` on a bare-`!` anonymous error set produces semantically correct results. F-1 stores the raw error name_id as the C error code; multiple error names may collide or miscompare.

- [ ] **Step 1: Read + reproduce**

Read the repro from P1-1. Build and run both RED and GREEN:
```bash
OUT=/tmp/p3
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/zig1.c" sf/src/main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign "$OUT"/*.c sf/src/include/zig_pal.c -o "$OUT/zig1"
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3r repro/mi_matrix/anon_errset_comparison/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p3r/*.c && gcc -m32 /tmp/p3r/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p3r/prog && /tmp/p3r/prog
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3g repro/mi_matrix/anon_errset_comparison/main_green.zig
# same gcc+run
```
Compare RED vs GREEN output. RED should print 1 (error.Bad == error.Bad) if `==` works; 0 if the raw code miscompares.

- [ ] **Step 2: Trace the error-code assignment**

Trace how the anonymous-set error code is assigned in lowering (lower.zig error_literal / wrap_error_err) and how `==` compares it in sema/coercion. Determine whether the raw name_id is a stable, unique code or collides across error sets.

- [ ] **Step 3: A/B/C options**

Options depend on findings:
- **A** (if `==` already correct): document, reclassify repro OK.
- **B** (if miscompare): add a per-program anonymous error-code registry — assign unique ints to distinct error names at sema/lowering, store in a map keyed by name_id.
- **C** (if only `!=` / exhaustiveness broken): partial fix + document.

Recommend the option with blast radius analysis. If a fix is needed, STOP for operator ruling before implementing.

- [ ] **Step 4: Report**

Write `.superpowers/sdd/P3-anonerr-report.md`. STOP for operator ruling on the recommended option if a fix is needed.

---

### Task P3-4: Investigate + Fix catch_block_value_producing (standalone I-task)

**Files:** investigation → `.superpowers/sdd/P3-catch-report.md`; fix in `sf/src/parser.zig` + verification in sema/lowerer.

**Pre-requisites:** None. Tech docs do NOT cover this gap (confirmed — parser/design docs imply blocks-as-catch-fallback works but never implement value-producing trailing expressions).

**Scope:** `catch |err| { _ = err; 99 }` fails error[2000] because `parserParseBlock` (parser.zig:1746) loops `parserParseStatement`, and `parserParseExprStmt` (:1256-1259) always requires a trailing `;`. The value-producing final expression `99` (no `;` before `}`) fails.

- [ ] **Step 1: Confirm root cause**

Read `sf/src/parser.zig:1746-1770` (parserParseBlock), `:1256-1260` (parserParseExprStmt), `:432-436` (parserParseCatchRHS). Confirm the exact failure: `99` parsed as expr-stmt then `parserExpect(semicolon)` fails on `}`.

- [ ] **Step 2: Design the value-producing block extension**

Determine how to allow a block's final statement to be a bare expression (no trailing `;`) that becomes the block's value. Investigate:
- How does `if`/`switch` handle value-producing blocks already (if any)?
- Does the AST/lowerer have a concept of "block with trailing value" (like `lowerExprOrBlock`)?
- What does the repro's expected semantics require (the block value `99` becomes the catch fallback)?

Provide A/B/C options:
- **A:** Parser-only — when the block is a catch-fallback (or any value context), allow the final expr-stmt to omit `;` and record it as the block value. Requires threading "value block" context.
- **B:** Parser + AST — add a `block_value` field/flag to block nodes; sema reads it as the block's type.
- **C:** Require explicit `return 99` (document as unsupported bare-value form) — matches the spec's divergent-only example.

Recommend an option. STOP for operator ruling.

- [ ] **Step 3: Implement the approved option**

Implement per the ruling. Include exact old→new parser code.

- [ ] **Step 4: Build + gate**

```bash
# Build /tmp compiler, then:
"$OUT/zig1" --dump-c89 --output-dir /tmp/p3c repro/mi_matrix/catch_block_value_producing/main.zig
gcc -m32 -std=c89 -I /workspace/znineeight/sf/src/include -c /tmp/p3c/*.c && gcc -m32 /tmp/p3c/*.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/p3c/prog && /tmp/p3c/prog
```
Expected: dump rc=0, gcc-clean, prints `99` on the error path (or correct per the repro's expected output). 4 MD5s byte-identical. Corpus: catch_block_value_producing FAIL→OK (or correct-rejection if the form is documented unsupported).

- [ ] **Step 5: Commit**

```bash
git add sf/src/parser.zig [sf/src/semantic_analyzer.zig] [sf/src/lower.zig] repro/mi_matrix/EXPECTED_FAIL.md
git commit -m "fix(P3): value-producing catch block fallback (catch_block_value_producing)"
```

---

## Execution Order

```
P1-1 → P1-2 → P1-3 → [P2-1 I-task → STOP] → P2-2 → P2-3 → [P2-4 after P2-1 ruling] → P3-1 → P3-2 → [P3-3 I-task → STOP] → [P3-4 I-task → STOP]
```

P1 first (repros + battery + cross-module fix). P2 emission defects with P2-1 investigation gating P2-4. P3 reclassifications + deferrals first (quick), then the two investigations (P3-3, P3-4) each with a STOP for operator ruling.
