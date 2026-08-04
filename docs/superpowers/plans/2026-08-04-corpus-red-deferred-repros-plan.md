# Corpus-RED Deferred Items + Defensive Repros — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create defensive repros for the deferred items exposed by F-1..F-9, fix the cross-module global field-access gap, and run the full 18-example runtime battery including lisp stressed.

**Architecture:** Three tasks. P1-1 creates 4 defensive repros (one per deferred item) with documented current classifications. P1-2 fixes the cross-module global field-access gap in `lower.zig`. P1-3 runs all 18 examples through dump→gcc→link→run, plus the lisp stressed battery.

**Design spec:** `docs/superpowers/specs/2026-08-04-corpus-red-remaining-design.md` (Plan 1 section)

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
- Corpus: 184/8/0/0 baseline over 192 repros. FAIL count must not increase.
- test_analyzer_bin PASS. build_test.sh identical to baseline (5/4). test_semantic_bin KNOWN pre-existing broken (operator ruling A).
- fastedit/edit only for source edits. Read region before each edit. Bottom-to-top. NO scope creep.
- Z98 idioms: `@intCast` everywhere, `var msg: []const u8 = "text";` before PAL, if/else-if chains.
- QUICK_REF.md reference mandatory for all gates.
- Repro convention: every new repro needs `main.zig` (+ optional `main_green.zig`), `NOTES.md` documenting classification, and a row in `repro/mi_matrix/EXPECTED_FAIL.md`.
- Example runtime battery: link against `sf/src/include/zig_runtime.c` + `zig_pal.c` (mud_server adds `net_runtime.c`; json_parser uses legacy `src/runtime/zig_runtime.c` compiled to `/tmp/rt.o` + needs `test.json` in CWD).

---

### Task P1-1: Create 4 Defensive Repros

**Files:**
- Create: `repro/mi_matrix/xmod_global_field_access/main.zig`, `lib.zig`, `main_green.zig`, `NOTES.md`
- Create: `repro/mi_matrix/self_embed_optional_cycle/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/load_global_array_copy/main.zig`, `NOTES.md`
- Create: `repro/mi_matrix/anon_errset_comparison/main.zig`, `main_green.zig`, `NOTES.md` (repro only — investigation is Plan 3 Task P3-3)
- Modify: `repro/mi_matrix/EXPECTED_FAIL.md` (add rows + update totals)

**Scope:** Four defensive repros, one per deferred item. Document current classification honestly — some are expected FAIL/ICE today, some OK-with-optimization-note.

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

- [ ] **Step 4: Create `anon_errset_comparison` (repro only, investigation deferred to Plan 3 P3-3)**

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
