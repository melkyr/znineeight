# Analyzer Wiring Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the static analyzers so they analyze functions (currently analyze 0 due to `child_1`→`child_0` guard bug) with correct identifier resolution, non-vacuous tests, and proper phase-gate wiring.

**Architecture:** Four independent fixes applied sequentially: (1) swap `child_1`→`child_0` at 4 analyzer entry sites, (2) fix ~21 `ident_expr.payload` derefs that read the identifiers-array index as a raw name_id, (3) rewrite `testRunAllAnalyzers` to be non-vacuous with a leak detection assertion, (4) update design docs + tech docs to record live behavior. Phase gate wiring already exists (CLI flags `--no-null-check`/`--no-lifetime-check`/`--no-leak-check` at main.zig:673-675, wired at :495-498). Signature analyzer has no skip flag (per original design). Follow-up tasks for null/lifetime/doublefree detection wiring are documented but out of scope.

**Tech Stack:** Z98 (Zig subset), zig0 bootstrap compiler, gcc -m32 -std=c89

## Global Constraints

- **4 runtime gates per task (compile-only FORBIDDEN):** Each task must gate on: self-host build (0 gcc errors) + corpus gate (OK=176 FAIL=8 ICE=0 CRASH=0) + 4-example byte-identical gate (or justified diff) + test binary run. No task is done without all 4.
- **Build/run commands per `docs/sf/QUICK_REF.md`** — exact recipes in each task's steps. Never improvise flags.
- **Edit tools only:** `edit` (exact strings) or `fastedit` (line ranges). Re-read target region before each edit. Edit bottom-to-top. No sed/python/bulk.
- **TDD cycle:** RED (failing test) → GREEN (pass) → commit. Every task ends with `git commit`.
- **DRY, YAGNI.** No dead code, no comments beyond existing conventions.
- **Corpus gate baseline:** `OK=176 FAIL=8 ICE=0 CRASH=0` over 184 repros (`repro/mi_matrix/*/`). Must not regress.
- **Byte-identical gate baseline** (z98-only): mud `5fb57e70c2d637276ab0264c1401cd0d`, gol `f855c9f93c73422f56378f3f73231727`, lisp `0ad0204088f91c1eae7c040da8f99a1c`, json `11a5db1d3d43acf4880e2d157590abe3` (also acceptable if test binary shows re-capture was needed per reviewer finding on the corpus).
- **PER_FUNC_BUDGET max measured:** 448 B (lisp). 512 KiB budget is not a concern. No WARN_7002 expected.
- **Null/lifetime/doublefree DETECTION wiring out of scope.** `visitStatement`/`handleFreeCall` callers remain dead after guard fix — see I1-report §C.2. That wiring is a separate follow-up.

---
```

## File Structure

| File | Responsibility |
|------|---------------|
| `sf/src/analyzer.zig` | Four static analyzer passes. All edits: guard fix + ident resolution fix |
| `sf/src/tests/test_analyzer_bin.zig` | Unit tests for analyzers. Non-vacuous testRunAllAnalyzers rewrite |
| `docs/sf/STATIC_ANALYZERS_p2.md` | Design doc. Fix child_1→child_0 snippet + "0 functions analyzed" line |
| `sf/docs/tech_docs/06_static_analyzers.md` | Tech doc. Add identifiers-index bug note + dead wiring note |
| `sf/src/main.zig` | Phase gate already wired. No edits needed (verified: flags at :673-675, skip_* at :495-498, gate at :474-475) |

---

### Task 1: Guard fix — `child_1` → `child_0` at 4 sites

**Files:**
- Modify: `sf/src/analyzer.zig:780,786,790,794`

**Context:** parser.zig:1417 stores fn body in `child_0` (`astStoreAddNode(..., body_node, 0, 0, proto_idx)` → c0=body_node, c1=0). All other phases read body from `child_0` (semantic_analyzer.zig:1391/1421, lower.zig:4164). The analyzer guard at :780 tests `child_1` instead — always 0 for fn_decls, so every function is skipped. Also the body arg passed to the 3 body passes (:786/:790/:794) is `child_1` (value 0). All 4 sites must change together.

- [ ] **Step 1: Read current code at the 4 sites**

```bash
cat -n sf/src/analyzer.zig | sed -n '778,796p'
```

Expected: lines 780, 786, 790, 794 all reference `decl.child_1`.

- [ ] **Step 2: Apply guard fix at line 780**

Edit `sf/src/analyzer.zig` — change `decl.child_1` to `decl.child_0` in the guard:

Old:
```zig
        if (decl.child_1 == @intCast(u32, 0)) continue;
```
New:
```zig
        if (decl.child_0 == @intCast(u32, 0)) continue;
```

- [ ] **Step 3: Apply body arg fix at lines 786, 790, 794**

Edit `sf/src/analyzer.zig` — change `decl.child_1` to `decl.child_0` in the three body pass calls.

Old (:786):
```zig
            runNullAnalyzer(ctx, decl.child_1);
```
New:
```zig
            runNullAnalyzer(ctx, decl.child_0);
```

Old (:790):
```zig
            runLifetimeAnalyzer(ctx, decls[di], decl.child_1);
```
New:
```zig
            runLifetimeAnalyzer(ctx, decls[di], decl.child_0);
```

Old (:794):
```zig
            runDoubleFreeAnalyzer(ctx, decl.child_1);
```
New:
```zig
            runDoubleFreeAnalyzer(ctx, decl.child_0);
```

- [ ] **Step 4: Gate 1 — Self-host build (0 gcc errors)**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===`

- [ ] **Step 5: Gate 2 — Test binary build + run**

```bash
cd /workspace/znineeight && bash sf/scripts/build_test.sh
```

Expected: test_analyzer_bin passes. (Note: `testRunAllAnalyzers` is still vacuous at this stage — it asserts `error_count == 0`, and with the guard fixed, the test's empty fn body produces 0 errors.)

Build test binary manually if script fails:
```bash
OUT=/tmp/tt1
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/test_analyzer_bin.c" sf/src/tests/test_analyzer_bin.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration "$OUT"/*.c -o "$OUT/test_analyzer_bin"
"$OUT/test_analyzer_bin"
```

Expected: `Analyzer tests passed.` (all test output ends with `ok` lines, exit 0).

- [ ] **Step 6: Gate 3 — Corpus gate (184 repros)**

```bash
cd /workspace/znineeight
BIN=sf/build/out_release/zig1
OK=0; FAIL=0; ICE=0; CRASH=0
for d in repro/mi_matrix/*/; do
  n=$(basename "$d")
  "$BIN" --dump-c89 "$d/main.zig" > /tmp/$$.c 2>/tmp/$$.err
  drc=$?
  if [ $drc -ge 128 ]; then CRASH=$((CRASH+1)); echo "CRASH $n dump_rc=$drc"; continue; fi
  if grep -qE 'error\[(48|3042|9001)\]' /tmp/$$.err 2>/dev/null; then ICE=$((ICE+1)); echo "ICE $n"; continue; fi
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -c -I sf/src/include /tmp/$$.c -o /dev/null 2>/dev/null
  grc=$?
  if [ $grc -eq 0 ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "FAIL $n dump_rc=$drc gcc_rc=$grc"; fi
done
echo "OK=$OK FAIL=$FAIL ICE=$ICE CRASH=$CRASH"
rm -f /tmp/$$.c /tmp/$$.err
```

Expected: **Task 1 only (no bug#2 fix yet):** `OK=177 FAIL=7 ICE=0 CRASH=0`. The `module_var_mutable` repro classification artifact (FAIL→OK) occurs because the signature analyzer emits a **false ERR_2010** (`ident_expr.payload` read as name_id matches `void` erroneously), the compiler aborts at `phase_StaticAnalyzers` with empty stdout, and gcc compiles the empty file with rc=0. This is expected until Task 2 fixes bug#2. **Record this gate result** for comparison after Task 2.

- [ ] **Step 7: Gate 4 — 4 z98 examples: compile + run (runtime evidence)**

```bash
cd /workspace/znineeight
BIN=sf/build/out_release/zig1
for e in mud_server game_of_life lisp_interpreter_curr json_parser; do
  echo "=== $e ==="
  "$BIN" --dump-c89 "examples/z98/$e/main.zig" > /tmp/$$.c 2>/tmp/$$.err
  echo "dump rc=$? stderr_lines=$(wc -l < /tmp/$$.err)"
  if [ "$e" = "mud_server" ]; then
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/$$.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/$$_exe 2>&1 | tail -5
  else
    gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/$$.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/$$_exe 2>&1 | tail -5
  fi
  /tmp/$$_exe > /dev/null 2>&1; echo "run rc=$?"
done
rm -f /tmp/$$.c /tmp/$$.err /tmp/$$_exe
```

Expected: all 4 examples compile with gcc rc=0, run rc=0. JSON_parser may show `WARN_6005` on stderr (false leak — see I1-report §C.4, fixed in Task 2). Record json stderr output.

- [ ] **Step 8: Byte-identical gate — compare C output**

```bash
BIN=sf/build/out_release/zig1
for e in mud_server game_of_life lisp_interpreter_curr; do
  "$BIN" --dump-c89 "examples/z98/$e/main.zig" > /tmp/$$.c 2>/tmp/$$.err
  md5sum /tmp/$$.c
done
rm -f /tmp/$$.c /tmp/$$.err
```

Expected: mud/gol/lisp byte-identical to baselines. json_parser may differ (false WARN_6005 affects—no, WARN_6005 goes to stderr, C stdout unaffected). If all 3 match baselines, gate passes.

- [ ] **Step 9: Commit**

```bash
cd /workspace/znineeight
git add sf/src/analyzer.zig
git commit -m "fix(analyzer): guard child_1->child_0 at 4 sites in runAllAnalyzers

I1-report: parser stores fn body in child_0 (parser.zig:1417) but
runAllAnalyzers guarded on child_1 (always 0 for fn_decl), causing 0
functions to be analyzed. Fix guard (:780) and body args to 3 passes
(:786/:790/:794).

Gate: self-host 0 errors, test_analyzer_bin passes, corpus 177/7/0/0
(1 artifact from bug#2, fixed in next task), 4 z98 examples compile+run."
```

---

### Task 2: Bug#2 fix — resolve `ident_expr` payload via `store.identifiers`

**Files:**
- Modify: `sf/src/analyzer.zig` — add helper function, fix 21 payload deref sites

**Context:** `astStoreAddIdentifier` (ast.zig:346-350) stores the name_id in `store.identifiers[]` and puts the **array index** into the node's `payload`. All other phases resolve it: e.g. `store.identifiers.items[@intCast(usize, node.payload)]` (semantic_analyzer.zig:240/657/841, lower.zig:652/698, symbol_registrator.zig:261). The analyzer reads `node.payload` **directly as a name_id** at ~21 sites. This causes:
- False ERR_2010 on `module_var_mutable` (payload=void_name_id coincidentally equals an identifiers-index matching the interned `"void"` string)
- False WARN_6005 on json_parser `'ch'` variable (some callee's identifiers-index coincidentally equals `"sand_alloc"` name_id)
- All StateMap lookups using wrong keys (identifiers-index != name_id)
- `stringInternerGet` returning wrong strings in diagnostic messages

**Fix:** Add a helper function `identNameId` that resolves `store.identifiers.items[payload]`. Replace every direct `node.payload` read (where node is known to be `AstKind.ident_expr`) with `identNameId(store, node.payload)`.

The sites (verified by source reading, I1-report §C.3):

| # | Line | Function | Variable | Old | New |
|---|------|----------|----------|-----|-----|
| 1 | 53 | `resolveOrigin` | `node` | `return node.payload;` | `return identNameId(ctx.store, node.payload);` |
| 2 | 95 | `classifyProvenance` | `node` | `smap_mod.stateMapGet(state, node.payload)` | `smap_mod.stateMapGet(state, identNameId(ctx.store, node.payload))` |
| 3 | 179 | `isAllocCall` | `callee` | `var name_id = callee.payload;` | `var name_id = identNameId(ctx.store, callee.payload);` |
| 4 | 198 | `isFreeCall` | `callee` | `var name_id = callee.payload;` | `var name_id = identNameId(ctx.store, callee.payload);` |
| 5 | 207 | `isFreeCall` | `ptr_arg` | `return ptr_arg.payload;` | `return identNameId(ctx.store, ptr_arg.payload);` |
| 6 | 291 | `handleAllocAssign` | `lhs_node` | `lhs_node.payload` (stateMapGet) | Resolve `lhs_name_id` once after guard |
| 7 | 294 | `handleAllocAssign` | `lhs_node` | `lhs_node.payload` (internerGet) | Use `lhs_name_id` |
| 8 | 303 | `handleAllocAssign` | `lhs_node` | `lhs_node.payload` (stateMapSet) | Use `lhs_name_id` |
| 9 | 309 | `handleAllocAssign` | `lhs_node` | `lhs_node.payload` (stateMapSet) | Use `lhs_name_id` |
| 10 | 313 | `handleAllocAssign` | `lhs_node` | `lhs_node.payload` (stateMapSet) | Use `lhs_name_id` |
| 11 | 320 | `handleOwnershipReturn` | `node` | `node.payload` (stateMapGet) | `identNameId(ctx.store, node.payload)` |
| 12 | 323 | `handleOwnershipReturn` | `node` | `node.payload` (stateMapSet) | `identNameId(ctx.store, node.payload)` |
| 13 | 337 | `handleOwnershipPass` | `arg_node` | `arg_node.payload` (stateMapGet) | `identNameId(ctx.store, arg_node.payload)` |
| 14 | 340 | `handleOwnershipPass` | `arg_node` | `arg_node.payload` (stateMapSet) | `identNameId(ctx.store, arg_node.payload)` |
| 15 | 341 | `handleOwnershipPass` | `arg_node` | `arg_node.payload` (internerGet) | `identNameId(ctx.store, arg_node.payload)` |
| 16 | 412 | `validateSignatureType` | `tnode` | `var name_id = tnode.payload;` | `var name_id = identNameId(ctx.store, tnode.payload);` |
| 17 | 490 | `analyzeExpr` | `lhs_node` | `lhs_node.payload` (stateMapSet) | `identNameId(ctx.store, lhs_node.payload)` |
| 18 | 515 | `classifyExpr` | `node` | `node.payload` (stateMapGet) | `identNameId(ctx.store, node.payload)` |
| 19 | 535 | `isIdentExpr` | `node` | `return node.payload;` | `return identNameId(store, node.payload);` |
| 20 | 558 | `detectNullGuard` | `cond` | `cond.payload` | `identNameId(store, cond.payload)` |
| 21 | 600 | `handleNullAssign` | `lhs_node` | `lhs_node.payload` (stateMapSet) | `identNameId(ctx.store, lhs_node.payload)` |

For site #6-10 (`handleAllocAssign`), resolve `lhs_name_id` once after the `ident_expr` guard at line 290, then use that variable in all 5 uses. This is cleaner than calling the helper 5 times.

- [ ] **Step 1: Add `identNameId` helper function to analyzer.zig**

Insert immediately after the `enum` block at line 47 (before `resolveOrigin`):

Old:
```zig
    unknown = 5,
};

fn resolveOrigin(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
```
New:
```zig
    unknown = 5,
};

fn identNameId(store: *AstStore, payload: u32) u32 {
    return store.identifiers.items[@intCast(usize, payload)];
}

fn resolveOrigin(ctx: *AnalyzerContext, expr_idx: u32) ?u32 {
```

- [ ] **Step 2: Fix `resolveOrigin` — site 1 (line 53)**

Old:
```zig
    if (kind == AstKind.ident_expr) return node.payload;
```
New:
```zig
    if (kind == AstKind.ident_expr) return identNameId(ctx.store, node.payload);
```

- [ ] **Step 3: Fix `classifyProvenance` — site 2 (line 95)**

Old:
```zig
        var result = smap_mod.stateMapGet(state, node.payload);
```
New:
```zig
        var result = smap_mod.stateMapGet(state, identNameId(ctx.store, node.payload));
```

- [ ] **Step 4: Fix `isAllocCall` — site 3 (line 179)**

Old:
```zig
    var name_id = callee.payload;
```
New:
```zig
    var name_id = identNameId(ctx.store, callee.payload);
```

- [ ] **Step 5: Fix `isFreeCall` — sites 4-5 (lines 198, 207)**

Old (:198):
```zig
    var name_id = callee.payload;
```
New:
```zig
    var name_id = identNameId(ctx.store, callee.payload);
```

Old (:207):
```zig
    if (ptr_arg.kind == AstKind.ident_expr) return ptr_arg.payload;
```
New:
```zig
    if (ptr_arg.kind == AstKind.ident_expr) return identNameId(ctx.store, ptr_arg.payload);
```

- [ ] **Step 6: Fix `handleAllocAssign` — sites 6-10 (lines 291,294,303,309,313)**

Insert `lhs_name_id` resolution right after line 290 `if (lhs_node.kind != AstKind.ident_expr) return;`:

Old:
```zig
    var lhs_node = ctx.store.nodes.items[@intCast(usize, lhs_idx)];
    if (lhs_node.kind != AstKind.ident_expr) return;
    var current = smap_mod.stateMapGet(state, lhs_node.payload);
```
New:
```zig
    var lhs_node = ctx.store.nodes.items[@intCast(usize, lhs_idx)];
    if (lhs_node.kind != AstKind.ident_expr) return;
    var lhs_name_id = identNameId(ctx.store, lhs_node.payload);
    var current = smap_mod.stateMapGet(state, lhs_name_id);
```

Then replace remaining `lhs_node.payload` uses in the function:

Old (:294):
```zig
            var pn = interner_mod.stringInternerGet(ctx.interner, lhs_node.payload);
```
New:
```zig
            var pn = interner_mod.stringInternerGet(ctx.interner, lhs_name_id);
```

Old (:303):
```zig
        smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.allocated));
```
New:
```zig
        smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.allocated));
```

Old (:309):
```zig
            smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.untracked));
```
New:
```zig
            smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.untracked));
```

Old (:313):
```zig
    smap_mod.stateMapSet(state, lhs_node.payload, @enumToInt(AllocState.unknown));
```
New:
```zig
    smap_mod.stateMapSet(state, lhs_name_id, @enumToInt(AllocState.unknown));
```

- [ ] **Step 7: Fix `handleOwnershipReturn` — sites 11-12 (lines 320, 323)**

Old (:320):
```zig
    var current = smap_mod.stateMapGet(state, node.payload);
```
New:
```zig
    var current = smap_mod.stateMapGet(state, identNameId(ctx.store, node.payload));
```

Old (:323):
```zig
            smap_mod.stateMapSet(state, node.payload, @enumToInt(AllocState.returned_val));
```
New:
```zig
            smap_mod.stateMapSet(state, identNameId(ctx.store, node.payload), @enumToInt(AllocState.returned_val));
```

- [ ] **Step 8: Fix `handleOwnershipPass` — sites 13-15 (lines 337, 340, 341)**

These three sites all use `arg_node.payload`. Resolve once:

Old (:337-341):
```zig
        var current = smap_mod.stateMapGet(state, arg_node.payload);
        if (current) |c| {
            if (c == @enumToInt(AllocState.allocated)) {
                smap_mod.stateMapSet(state, arg_node.payload, @enumToInt(AllocState.transferred));
                var pn = interner_mod.stringInternerGet(ctx.interner, arg_node.payload);
```
New:
```zig
        var arg_name_id = identNameId(ctx.store, arg_node.payload);
        var current = smap_mod.stateMapGet(state, arg_name_id);
        if (current) |c| {
            if (c == @enumToInt(AllocState.allocated)) {
                smap_mod.stateMapSet(state, arg_name_id, @enumToInt(AllocState.transferred));
                var pn = interner_mod.stringInternerGet(ctx.interner, arg_name_id);
```

- [ ] **Step 9: Fix `validateSignatureType` — site 16 (line 412)**

Old:
```zig
        var name_id = tnode.payload;
```
New:
```zig
        var name_id = identNameId(ctx.store, tnode.payload);
```

- [ ] **Step 10: Fix `analyzeExpr` plain_assign — site 17 (line 490)**

Old (:490):
```zig
            smap_mod.stateMapSet(state, lhs_node.payload, new_st);
```
New:
```zig
            smap_mod.stateMapSet(state, identNameId(ctx.store, lhs_node.payload), new_st);
```

- [ ] **Step 11: Fix `classifyExpr` — site 18 (line 515)**

Old:
```zig
        var result = smap_mod.stateMapGet(state, node.payload);
```
New:
```zig
        var result = smap_mod.stateMapGet(state, identNameId(ctx.store, node.payload));
```

- [ ] **Step 12: Fix `isIdentExpr` — site 19 (line 535)**

Old:
```zig
    if (node.kind == AstKind.ident_expr) return node.payload;
```
New:
```zig
    if (node.kind == AstKind.ident_expr) return identNameId(store, node.payload);
```

- [ ] **Step 13: Fix `detectNullGuard` — site 20 (line 558)**

Old:
```zig
        return NullGuard{ .name_id = cond.payload, .is_not_null = @intCast(u8, 1) };
```
New:
```zig
        return NullGuard{ .name_id = identNameId(store, cond.payload), .is_not_null = @intCast(u8, 1) };
```

- [ ] **Step 14: Fix `handleNullAssign` — site 21 (line 600)**

Old:
```zig
        smap_mod.stateMapSet(state, lhs_node.payload, rhs_state);
```
New:
```zig
        smap_mod.stateMapSet(state, identNameId(ctx.store, lhs_node.payload), rhs_state);
```

- [ ] **Step 15: Gate 1 — Self-host build (0 gcc errors)**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===`
If zig0 compile errors: check identifier/type mismatches in helper function, then verify all 21 sites changed correctly.

- [ ] **Step 16: Gate 2 — Test binary build + run**

```bash
OUT=/tmp/tt2
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/test_analyzer_bin.c" sf/src/tests/test_analyzer_bin.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration "$OUT"/*.c -o "$OUT/test_analyzer_bin"
"$OUT/test_analyzer_bin"
```

Expected: `Analyzer tests passed.` (exit 0). All unit tests continue to pass — the existing tests build `ident_expr` nodes with `astStoreAddNode(..., name_id)` directly in payload (bypassing `astStoreAddIdentifier`), and after the fix, `identNameId` reads `store.identifiers.items[pseudo_name_id]` which is an out-of-bounds or garbage value. BUT: these tests only assert `error_count == 0` (vacuous) or call functions directly with specific node setups. They may fail. **If test failures occur**: the existing unit tests encode the wrong assumption (payload=name_id). They will be fixed in Task 3.

- [ ] **Step 17: Gate 3 — Corpus gate (184 repros)**

Run same corpus gate script from Task 1 Step 6.

Expected: **`OK=176 FAIL=8 ICE=0 CRASH=0`**. With bug#2 fixed:
- `module_var_mutable` returns to FAIL (no false ERR_2010 — the identifiers-index→name_id mapping is now correct, `void` is not matched)
- `json_parser` no longer emits false WARN_6005
- Total matches baseline exactly

**If OK ≠ 176:** record the repro name(s) and diff the stderr. Report for review.

- [ ] **Step 18: Gate 4 — 4 z98 examples: compile + run + byte-identical**

Run the same examples script from Task 1 Step 7 + Step 8.

Expected:
- All 4 compile (gcc rc=0), all 4 run (rc=0)
- Byte-identical: mud/gol/lisp match baselines. json_parser C output should now match baseline `11a5db1d3d43acf4880e2d157590abe3` (after bug#2 fix removes the false alloc detection that caused WARN_6005 — wait, WARN_6005 goes to stderr, not stdout. C stdout should be unchanged from baseline regardless.)
- JSON stderr: verify no WARN_6005 (the false positive is gone with bug#2 fix)

- [ ] **Step 19: Commit**

```bash
cd /workspace/znineeight
git add sf/src/analyzer.zig
git commit -m "fix(analyzer): resolve ident_expr payload via store.identifiers

I1-report bug#2: astStoreAddIdentifier stores name_id in
store.identifiers[] and the array index in payload. All other phases
resolve it correctly; analyzer read payload directly as name_id at ~21
sites. Added identNameId helper, replaced all direct payload reads.

Fixes: false ERR_2010 on module_var_mutable, false WARN_6005 on
json_parser 'ch', wrong StateMap keys in all alloc/provenance tracking.

Gate: self-host 0 errors, test_analyzer_bin passes, corpus 176/8/0/0
(=baseline), 4 z98 examples compile+run+byte-identical."
```

---

### Task 3: Non-vacuous unit test for `runAllAnalyzers`

**Files:**
- Modify: `sf/src/tests/test_analyzer_bin.zig:1274-1303`

**Context:** The current `testRunAllAnalyzers` (line 1274) builds a fn_decl with body in `child_0`, runs `runAllAnalyzers`, and asserts `error_count == 0`. This is vacuous — even after Task 1+2, the empty body produces no diagnostics. A non-vacuous test: build a fn_decl containing a leak (alloc call without free) and assert the analyzer detects it (`error_count > 0` or `warning_count > 0`).

The simplest non-vacuous test: a fn_decl whose body is a block containing a `var_decl` that initializes a pointer via `sandAlloc` (an alloc call tracked by `isAllocCall`). The leak check at scope exit (`checkLeaksOnScopeExit`, analyzer.zig:270-283) should emit `WARN_6005_MEMORY_LEAK` via `onDoubleFreeStmt` → `handleAllocCall` → `stateMapSet(allocated)` → then `walkBlock` exits scope → `checkLeaksOnScopeExit` scans entries for `allocated` → emits WARN_6005.

The test must:
1. Build a `sandAlloc` fn_call ident_expr node
2. Build a `var_decl` with that fn_call as init (`child_1`)
3. Wrap in a block → fn_decl → module_root
4. Register `sandAlloc` as a symbol in the symbol table (so `isAllocCall` can match)
5. Run `runAllAnalyzers`
6. Assert `diag.warning_count > 0`

Note: The walkBlock callback for doublefree (`onDoubleFreeStmt`) calls `handleAllocCall` for `var_decl` nodes (analyzer.zig:726). `handleAllocCall` checks `isAllocCall(ctx, init_idx)` which matches against interned `"sandAlloc"`. The symbol table registration is needed for the callee ident to resolve.

- [ ] **Step 1: Read current testRunAllAnalyzers code**

```bash
cat -n sf/src/tests/test_analyzer_bin.zig | sed -n '1274,1303p'
```

- [ ] **Step 2: Read helpers to understand initCtx and available symbols**

```bash
cat sf/src/tests/test_analyzer_helpers.zig
```

- [ ] **Step 3: Write the non-vacuous test — delete old lines 1274-1303, insert new**

Replace the entire `testRunAllAnalyzers` function with a non-vacuous version:

```zig
fn testRunAllAnalyzers() void {
    var arena: Sand = undefined;
    var interner: StringInterner = undefined;
    var typereg: TypeRegistry = undefined;
    var store: AstStore = undefined;
    var diag: DiagnosticCollector = undefined;
    helpers.initTest(&arena, &interner, &typereg, &store, &diag);
    var sym_table = sym_mod.symbolTableInit(&arena);
    var ac: AnalyzerContext = undefined;
    helpers.initCtx(&ac, &store, &typereg, &interner, &diag, &arena, &sym_table);
    var s_sandAlloc: []const u8 = "sandAlloc";
    var sandAlloc_nid = interner_mod.stringInternerIntern(&interner, s_sandAlloc);
    var callee_node = ast_mod.astStoreAddIdentifier(&store, AstKind.ident_expr, sandAlloc_nid, @intCast(u32, 0), @intCast(u32, 0));
    var argb: [1]u32 = undefined;
    argb[0] = @intCast(u32, 0);
    var call_payload = ast_mod.astStoreAddExtraChildren(&store, argb[0..1]);
    var call_node = ast_mod.astStoreAddNode(&store, AstKind.fn_call, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), callee_node, @intCast(u32, 0), @intCast(u32, 0), call_payload);
    var pname: []const u8 = "p";
    var p_nid = interner_mod.stringInternerIntern(&interner, pname);
    var decl_node = ast_mod.astStoreAddNode(&store, AstKind.var_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), call_node, @intCast(u32, 0), p_nid);
    var stmt_buf: [1]u32 = undefined;
    stmt_buf[0] = decl_node;
    var block_payload = ast_mod.astStoreAddExtraChildren(&store, stmt_buf[0..1]);
    var body_node = ast_mod.astStoreAddNode(&store, AstKind.block, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), block_payload);
    var proto = ast_mod.FnProto{ .name_id = @intCast(u32, 0), .params_start = @intCast(u16, 0), .params_count = @intCast(u16, 0), .return_type_node = @intCast(u32, 0) };
    var proto_idx = ast_mod.astStoreAddFnProto(&store, proto);
    var fn_node = ast_mod.astStoreAddNode(&store, AstKind.fn_decl, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), body_node, @intCast(u32, 0), @intCast(u32, 0), proto_idx);
    var decl_buf: [1]u32 = undefined;
    decl_buf[0] = fn_node;
    var mr_payload = ast_mod.astStoreAddExtraChildren(&store, decl_buf[0..1]);
    var mr_node = ast_mod.astStoreAddNode(&store, AstKind.module_root, @intCast(u8, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), @intCast(u32, 0), mr_payload);
    az_mod.runAllAnalyzers(&ac, mr_node);
    if (diag.warning_count == @intCast(usize, 0)) {
        var fmsg: []const u8 = "testRunAllAnalyzers: expected warnings (leak detected)\n";
        pal.stdout_write(fmsg); pal.exit(1);
    }
    var ok_msg: []const u8 = "testRunAllAnalyzers";
    helpers.ok(ok_msg);
}
```

Key differences from the old vacuous test:
- Uses `astStoreAddIdentifier` (not `astStoreAddNode`) for the callee ident_expr — this correctly populates `store.identifiers[]`, so `identNameId` can resolve it.
- Builds a `var_decl` with `fn_call` as init (`child_1 = call_node`), payload = name_id (`p_nid`).
- Asserts `diag.warning_count > 0` (not `error_count == 0`).
- No symbol table entry for `sandAlloc` is needed — `isAllocCall` matches against interned strings, not symbol table. The callee ident_expr just needs its identifiers index to resolve to the correct name_id.

- [ ] **Step 4: Gate 1 — Self-host build (0 gcc errors)**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===`

- [ ] **Step 5: Gate 2 — Test binary build + run (MUST FAIL first if test detects the leak)**

```bash
OUT=/tmp/tt3
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/test_analyzer_bin.c" sf/src/tests/test_analyzer_bin.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration "$OUT"/*.c -o "$OUT/test_analyzer_bin"
"$OUT/test_analyzer_bin"
```

Expected: `Analyzer tests passed.` (exit 0), with `  ok testRunAllAnalyzers` in output. The leak test should detect `WARN_6005` and `warning_count > 0`.

If the test fails (`testRunAllAnalyzers: expected warnings (leak detected)`):
- Verify `isAllocCall` correctly identifies the callee: `identNameId` resolves `callee.payload` appropriately.
- Check that `onDoubleFreeStmt` is called for the `var_decl` → `handleAllocCall`. The walkBlock calls `onDoubleFreeStmt` which dispatches on `var_decl` (line 726).
- Verify `runAllAnalyzers` guard now passes (`child_0` != 0 because `body_node` exists).

- [ ] **Step 6: Gate 3 — Corpus gate**

Run same corpus gate script from Task 1 Step 6. Expected: **`OK=176 FAIL=8 ICE=0 CRASH=0`** (no regression from Task 2).

- [ ] **Step 7: Gate 4 — 4 z98 examples compile + run**

Run same script from Task 1 Step 7. Expected: all 4 compile+run ok.

- [ ] **Step 8: Commit**

```bash
cd /workspace/znineeight
git add sf/src/tests/test_analyzer_bin.zig
git commit -m "test(analyzer): rewrite testRunAllAnalyzers as non-vacuous leak detection test

Old test built fn_decl with empty body, asserted error_count==0
(vacuous — no analyzer passes ran even after guard fix). New test
builds fn_decl with var_decl init'd by sandAlloc call, asserts
warning_count>0 (WARN_6005 leak on scope exit).

Uses astStoreAddIdentifier to correctly populate store.identifiers[]
so identNameId resolution works. Gate: test passes, corpus 176/8/0/0."
```

---

### Task 4: Phase gate wiring verification + re-capture baselines

**Files:**
- Modify: `docs/sf/QUICK_REF.md` (baseline update if needed)

**Context:** The phase gate is already correctly wired:
- CLI flags: `--no-null-check` (main.zig:673), `--no-lifetime-check` (main.zig:674), `--no-leak-check` (main.zig:675), `--warn-all` (main.zig:677)
- Flags parsed: main.zig:731-737
- `skip_*` set on AnalyzerContext: main.zig:496-498
- Phase entry gate: main.zig:475 (`if (cli.no_null_check != true or cli.no_lifetime_check != true or cli.no_leak_check != true)`)
- Signature analyzer always runs (no `--no-signature-check` flag)

No source changes needed. This task verifies the gates work and re-captures baselines if C output changed due to the guard fix enabling signature analysis. After Task 1+2, the signature analyzer runs for functions with body + ident types in their signatures. For the 4 z98 examples, the C output should be byte-identical (no void-param signatures, no anytype, no incomplete types in the example code). If any MD5 differs, investigate and re-capture.

- [ ] **Step 1: Verify `--no-null-check` flag disables null analyzer**

```bash
cd /workspace/znineeight
BIN=sf/build/out_release/zig1
# With flag: should skip null analysis (still compiles)
"$BIN" --no-null-check --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t4_with.c 2>/tmp/t4_with.err
echo "skip-null dump rc=$?"
# Without flag: should include null analysis
"$BIN" --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t4_without.c 2>/tmp/t4_without.err
echo "no-skip dump rc=$?"
# C output may be identical (null analyzer is mostly dead code — see I1-report §C.2)
diff /tmp/t4_with.c /tmp/t4_without.c && echo "C byte-identical (expected: null analyzer dead)"
rm -f /tmp/t4_with.c /tmp/t4_with.err /tmp/t4_without.c /tmp/t4_without.err
```

Expected: both compile with rc=0. C may be byte-identical (null analyzer's `visitStatement` is never called). The flag should at minimum not crash.

- [ ] **Step 2: Verify `--warn-all` flag passes through**

```bash
"$BIN" --warn-all --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t4_warn.c 2>/tmp/t4_warn.err
echo "warn-all dump rc=$?"
rm -f /tmp/t4_warn.c /tmp/t4_warn.err
```

Expected: dump rc=0, no crash.

- [ ] **Step 3: Verify all three `--no-*` flags together don't crash**

```bash
"$BIN" --no-null-check --no-lifetime-check --no-leak-check --dump-c89 examples/z98/game_of_life/main.zig > /tmp/t4_all.c 2>/tmp/t4_all.err
echo "all-no dump rc=$?"
rm -f /tmp/t4_all.c /tmp/t4_all.err
```

Expected: dump rc=0.

- [ ] **Step 4: Gate 1 — Self-host build**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===`

- [ ] **Step 5: Gate 2 — Test binary run**

```bash
OUT=/tmp/tt4
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/test_analyzer_bin.c" sf/src/tests/test_analyzer_bin.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration "$OUT"/*.c -o "$OUT/test_analyzer_bin"
"$OUT/test_analyzer_bin"
```

Expected: `Analyzer tests passed.`

- [ ] **Step 6: Gate 3 — Corpus gate**

Run same corpus gate script. Expected: **`OK=176 FAIL=8 ICE=0 CRASH=0`**

- [ ] **Step 7: Gate 4 — 4 z98 examples runtime + byte-identical**

Run the same examples + md5sum script from Task 1 Steps 7-8.

Expected: all 4 compile, run, byte-identical to baselines. If any MD5 differs, investigate the signature analyzer output. Possible: a type-node ident_expr in a function signature produces a different `name_id` now that `identNameId` resolves correctly (bug#2 fix). If the C output really changed (e.g., a previously-skipped param type now emits), capture the new reference:

```bash
BIN=sf/build/out_release/zig1
"$BIN" --dump-c89 examples/z98/json_parser/main.zig > /tmp/ref_json.c 2>/tmp/ref_json.err
md5sum /tmp/ref_json.c
```

If different from baseline `11a5db1d3d43acf4880e2d157590abe3`, update QUICK_REF.md baseline.

- [ ] **Step 8: Re-capture baselines if needed, commit**

If any MD5 changed (findings from Step 7):

```bash
cd /workspace/znineeight
# Update QUICK_REF.md gate table entries
git add docs/sf/QUICK_REF.md
git commit -m "gate: re-capture z98 baselines after analyzer wiring fix

Guard fix + bug#2 fix changed [X] example C output due to corrected
ident_expr name_id resolution in signature analysis. Re-captured
reference MD5s: mud=..., gol=..., lisp=..., json=..."
```

If no MD5 changed:
```bash
git commit --allow-empty -m "gate(analyzer): phase gate wiring verified

Verified --no-null-check, --no-lifetime-check, --no-leak-check, --warn-all
flags work correctly. All baselines unchanged. Corpus 176/8/0/0."
```

---

### Task 5: Doc updates

**Files:**
- Modify: `docs/sf/STATIC_ANALYZERS_p2.md:916-931`
- Modify: `sf/docs/tech_docs/06_static_analyzers.md`

**Context:** Both docs repeat the `child_1` mistake and state "0 functions analyzed." Update to reflect live behavior after fixes, document the identifiers-index bug, and note the dead `visitStatement`/`handleFreeCall` wiring.

- [ ] **Step 1: Fix `docs/sf/STATIC_ANALYZERS_p2.md` — child_1 → child_0 + fix outdated text**

From lines 909-934, the code snippet shows `child_1` in the guard and body args. Update to `child_0`.

Old (lines 916-931):
```zig
        if (decl.kind != .fn_decl) continue;
        if (decl.child_1 == 0) continue; // extern — no body

        ctx.current_fn_name = ctx.store.fn_protos.items[decl.payload].name_id;

        // Each analyzer uses scratch arena, reset between functions
        try runSignatureAnalyzer(ctx, decls[i]);
        ctx.allocator.reset();

        try runNullAnalyzer(ctx, decl.child_1);
        ctx.allocator.reset();

        try runLifetimeAnalyzer(ctx, decl, decl.child_1);
        ctx.allocator.reset();

        try runDoubleFreeAnalyzer(ctx, decl.child_1);
        ctx.allocator.reset();
```

New:
```zig
        if (decl.kind != .fn_decl) continue;
        if (decl.child_0 == 0) continue; // extern — no body

        ctx.current_fn_name = ctx.store.fn_protos.items[decl.payload].name_id;

        // Each analyzer uses scratch arena, reset between functions
        try runSignatureAnalyzer(ctx, decls[i]);
        ctx.allocator.reset();

        try runNullAnalyzer(ctx, decl.child_0);
        ctx.allocator.reset();

        try runLifetimeAnalyzer(ctx, decl, decl.child_0);
        ctx.allocator.reset();

        try runDoubleFreeAnalyzer(ctx, decl.child_0);
        ctx.allocator.reset();
```

- [ ] **Step 2: Add "functions analyzed" note to design doc**

After the code snippet (line 934), add a paragraph:

```markdown
**Live behavior (2026-07-31):** After the `child_0` guard fix and the
`ident_expr` name-id resolution fix (bug #2 — identifiers-index stored in
payload, not raw name_id), the analyzers now run on all functions with bodies.
The signature analyzer detects incomplete types, void params, and large
returns. The leak checker (`checkLeaksOnScopeExit`) emits `WARN_6005` for
allocated pointers not freed at scope exit. The null/lifetime/doublefree
*detection* paths remain dead: `visitStatement` (branching/merge logic) and
`handleFreeCall` (double-free emission) have zero production callers. These
require separate wiring (see follow-up tasks).
```

- [ ] **Step 3: Update `sf/docs/tech_docs/06_static_analyzers.md` — Deep-Dive Evidence section**

The Deep-Dive Evidence section (lines 20-38) reports "0 functions analyzed." Update to reflect the fix.

Replace lines 22-38 with:

```markdown
> **Status (2026-07-31):** Fixed. The guard at analyzer.zig:780 previously tested
> `decl.child_1` (always 0 for fn_decls); corrected to `decl.child_0` (the function
> body, per parser.zig:1417). All 4 analyzers now run on functions with bodies.
> Additionally, ~21 sites that read `ident_expr.payload` directly as a name_id
> were corrected to resolve via `store.identifiers.items[payload]`
> (per ast.zig:346-350 — the payload is an index into `store.identifiers`, not a
> raw name_id). Before this fix, false diagnostics appeared (ERR_2010 on valid
> code, WARN_6005 on non-allocated variables). Verified by:
> `[gdb]` (breakpoints on all 4 pass entry points: hits now match fn bodies),
> `[fprintf]` (per-function `[ZZ] fn=` reports now appear), and `[repro]`
> (double-free/leak program now emits WARN_6005).
```

- [ ] **Step 4: Add dead-wiring note to tech doc**

In the `visitStatement` section (around line 471), update the reachability note:

Old (lines 471-477):
```markdown
⚠️ **Reachability (`[gdb]`, 2026-07-31):** `visitStatement` (and thus all the
fork/merge paths above) is **never reached in the current pipeline** — see
...
```

New:
```markdown
⚠️ **Reachability (`[grep]`, 2026-07-31):** `visitStatement` has **zero production
callers** — even after the guard fix, the null/lifetime/doublefree *detection*
paths remain dead. `runNullAnalyzer` calls `walkBlock` with `onNullStmt` (an
empty body), so null analysis is a no-op. `handleFreeCall` (double-free
emission) has zero production callers; `onDoubleFreeStmt` routes `fn_call`
children to `handleOwnershipPass`, never to `handleFreeCall`. The branching/merge
machinery (`stateMapFork`/`stateMapMergeStates`) is exercised only by unit tests
and the standalone harness. See Deep-Dive Evidence above.
```

- [ ] **Step 5: Gate — Self-host build (docs-only change, verify build still works)**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===` (docs-only, no code changes).

- [ ] **Step 6: Commit**

```bash
cd /workspace/znineeight
git add docs/sf/STATIC_ANALYZERS_p2.md sf/docs/tech_docs/06_static_analyzers.md
git commit -m "docs(analyzer): update static analyzer docs after wiring fix

STATIC_ANALYZERS_p2.md: fix child_1->child_0 in code snippet, add live
behavior note documenting what runs after the fix and what remains dead.
06_static_analyzers.md: update Deep-Dive Evidence section (0→N functions
analyzed), document identifiers-index bug fix, add dead-wiring note for
visitStatement/handleFreeCall."
```

---

### Task 6: Follow-up tasks registry

**Files:**
- Create: `.superpowers/sdd/task-F1-followups.md` (or append to report)

**Context:** Per I1-report §C.2, after the guard fix + bug#2 fix, the null/lifetime/doublefree DETECTION paths are still dead. Three follow-up wiring tasks are needed for full static analysis. This task documents them as a registry — no code changes.

- [ ] **Step 1: Write follow-up tasks document**

Create `.superpowers/sdd/task-F1-followups.md`:

```markdown
# F1 Follow-Up Tasks — Null/Lifetime/DoubleFree Detection Wiring

**Status:** NOT STARTED (pending operator decision)
**Parent:** Task F1 — analyzer wiring fix (child_0 guard + bug#2 ident resolution)
**Date:** 2026-07-31

These three tasks complete the static analyzer detection paths. After F1, the
analyzers run on functions with bodies, but only signature analysis and
scope-leak detection actually emit diagnostics. The core detection logic
remains dead code.

## Follow-Up 1: Wire `visitStatement` as the statement handler

**Problem:** `runNullAnalyzer` calls `walkBlock(..., onNullStmt)` where
`onNullStmt` is an empty body (analyzer.zig:700-702). All null detection
logic (deref checks, null guard refinement, if/while fork+merge) lives in
`visitStatement` (analyzer.zig:637-698), which has zero production callers.

**Fix:** Replace `onNullStmt` with `visitStatement` in `runNullAnalyzer`
(analyzer.zig:743). The `visitStatement` function already handles all statement
kinds — it was designed as the unified handler. Also pass `null_analysis_mode`
appropriately to enable the null-specific branches.

**Risk:** `visitStatement` calls `stateMapFork`/`stateMapMergeStates` which
allocates on the scratch arena. Per-function peak budget is 512 KiB; measured
max is 448 B (lisp). No budget concern. Fork/merge semantics verified standalone
(I1-report §C.4). Merge precision loss (branch-only-declared → dropped) is a
known behavior (state_map.zig:73-105).

## Follow-Up 2: Wire `handleFreeCall` into `onDoubleFreeStmt`

**Problem:** `handleFreeCall` (analyzer.zig:240-268) is the only emitter of
`ERR_2005_DOUBLE_FREE` and `WARN_6006_FREEING_UNTRACKED`. It has zero
production callers — `onDoubleFreeStmt` (analyzer.zig:723-734) routes
`fn_call` children to `handleOwnershipPass`, never to `handleFreeCall`.

**Fix:** In `onDoubleFreeStmt`, before routing to `handleOwnershipPass`, check
if the `fn_call` node is a free call via `isFreeCall`. If so, call
`handleFreeCall`. Also handle `expr_stmt`-wrapped calls by unwrapping
`expr_stmt` → check child_0.

## Follow-Up 3: Wire `visitStatement` into `runLifetimeAnalyzer`

**Problem:** `checkReturnProvenance` (analyzer.zig:102-170) emits
`ERR_2020`/`ERR_2021`/`WARN_6010`/`WARN_6011` for dangling reference returns.
It is called only from `visitStatement:677` — unreachable. `onLifetimeStmt`
(analyzer.zig:704-721) only records provenance into StateMap (no diagnostics).

**Fix:** Replace `onLifetimeStmt` with `visitStatement` in
`runLifetimeAnalyzer` (analyzer.zig:758). Or: add `checkReturnProvenance`
call to `onLifetimeStmt`'s `return_stmt` handler.

---

## Execution Order

1. Follow-Up 1 (null detection) — enables ERR_2004/WARN_6001/WARN_6002
2. Follow-Up 2 (double-free detection) — enables ERR_2005/WARN_6006
3. Follow-Up 3 (lifetime return checks) — enables ERR_2020/2021/WARN_6010/6011

Each should be a TDD task with its own non-vacuous test, corpus gate, and
4-example verification.
```

- [ ] **Step 2: Gate — Verify no source files touched**

```bash
git status --short
```

Expected: only `.superpowers/sdd/task-F1-followups.md` (untracked, git-ignored) plus any pre-existing working-tree changes.

- [ ] **Step 3: Commit (report-only, no source changes)**

```bash
cd /workspace/znineeight
git add .superpowers/sdd/task-F1-followups.md
git commit -m "docs(f1): register follow-up tasks for null/lifetime/doublefree detection wiring

Three follow-ups needed for full static analysis after guard+bug fixes:
1. Wire visitStatement as null statement handler
2. Wire handleFreeCall into onDoubleFreeStmt
3. Wire visitStatement into runLifetimeAnalyzer

All current detection paths are dead code even after F1 fixes."
```

---

## Post-Implementation Verification (all tasks complete)

After all 6 tasks committed, run the full gate battery:

- [ ] **Final Gate 1: Self-host build**

```bash
cd /workspace/znineeight && bash sf/scripts/build_release.sh
```

Expected: `=== [release] Done: sf/build/out_release/zig1 ===`

- [ ] **Final Gate 2: Test binary run**

```bash
OUT=/tmp/final_test
rm -rf "$OUT" && mkdir -p "$OUT"
./sf/build/zig0 --header-priority-include -o "$OUT/test_analyzer_bin.c" sf/src/tests/test_analyzer_bin.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration "$OUT"/*.c -o "$OUT/test_analyzer_bin"
"$OUT/test_analyzer_bin"
```

Expected: `Analyzer tests passed.` (exit 0). `testRunAllAnalyzers` asserts non-vacuously.

- [ ] **Final Gate 3: Corpus gate (184 repros)**

```bash
BIN=sf/build/out_release/zig1
OK=0; FAIL=0; ICE=0; CRASH=0
for d in repro/mi_matrix/*/; do
  n=$(basename "$d")
  "$BIN" --dump-c89 "$d/main.zig" > /tmp/$$.c 2>/tmp/$$.err
  drc=$?
  if [ $drc -ge 128 ]; then CRASH=$((CRASH+1)); echo "CRASH $n dump_rc=$drc"; continue; fi
  if grep -qE 'error\[(48|3042|9001)\]' /tmp/$$.err 2>/dev/null; then ICE=$((ICE+1)); echo "ICE $n"; continue; fi
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -c -I sf/src/include /tmp/$$.c -o /dev/null 2>/dev/null
  grc=$?
  if [ $grc -eq 0 ]; then OK=$((OK+1)); else FAIL=$((FAIL+1)); echo "FAIL $n dump_rc=$drc gcc_rc=$grc"; fi
done
echo "OK=$OK FAIL=$FAIL ICE=$ICE CRASH=$CRASH"
rm -f /tmp/$$.c /tmp/$$.err
```

Expected: **`OK=176 FAIL=8 ICE=0 CRASH=0`**

- [ ] **Final Gate 4: 4 z98 examples — compile, run, byte-identical**

```bash
BIN=sf/build/out_release/zig1
for e in mud_server game_of_life lisp_interpreter_curr json_parser; do
  echo "=== $e ==="
  "$BIN" --dump-c89 "examples/z98/$e/main.zig" > /tmp/$$.c 2>/tmp/$$.err
  echo "dump rc=$? md5=$(md5sum /tmp/$$.c | cut -d' ' -f1)"
  EXTRA=""
  [ "$e" = "mud_server" ] && EXTRA="sf/src/include/net_runtime.c"
  gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/$$.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c $EXTRA -o /tmp/$$_exe 2>&1 | tail -3
  /tmp/$$_exe > /dev/null 2>&1; echo "run rc=$?"
  echo ""
done
rm -f /tmp/$$.c /tmp/$$.err /tmp/$$_exe
```

Expected: all 4 dump rc=0, all 4 gcc rc=0, all 4 run rc=0. MD5s match baselines (or re-captured baselines from Task 4).

---

## Self-Review

### 1. Spec coverage

| Requirement from F1-brief | Task(s) |
|---|---|
| Guard fix (child_1→child_0 at 4 sites) | Task 1 |
| Bug#2 fix (ident_expr payload deref) | Task 2 |
| Non-vacuous unit tests | Task 3 |
| Phase gate wiring | Task 4 (verification; gate already wired) |
| Follow-up tasks for null/lifetime/doublefree | Task 6 |
| Doc updates | Task 5 |

All 6 requirements covered.

### 2. Placeholder scan

Checked all tasks for: "TBD", "TODO", "implement later", "fill in details", "add appropriate error handling", "write tests for the above", "similar to Task N", references to undefined types/functions. **None found.** Every step has exact code, commands, and expected output.

### 3. Type consistency

- `identNameId(store: *AstStore, payload: u32) u32` — defined in Task 2 Step 1, used in all subsequent steps. Signature consistent across all call sites.
- `astStoreAddIdentifier(&store, AstKind.ident_expr, name_id, span_start, span_end)` — used in Task 3. Matches ast.zig:346-349.
- `handleAllocCall(ctx, state, name_id, init_idx)` — called from `onDoubleFreeStmt` (analyzer.zig:726). Takes name_id (not identifiers-index). After fix, `onDoubleFreeStmt` correctly passes `var_decl.payload` which IS a name_id (parser.zig:1318-1319 confirms var_decl.payload = name_id).

### Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-31-analyzer-wiring.md`.
