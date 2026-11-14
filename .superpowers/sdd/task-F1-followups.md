# F1 Follow-Up Tasks — Null/Lifetime/DoubleFree Detection Wiring

**Status:** NOT STARTED (pending operator decision)
**Parent:** Task F1 — analyzer wiring fix (child_0 guard + bug#2 ident resolution)
**Date:** 2026-08-03

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

**Expected diagnostics:** ERR_2004_NULL_DEREF, WARN_6001_POSSIBLE_NULL,
WARN_6002_NULL_GUARD_REDUNDANT.

**Risk:** `visitStatement` calls `stateMapFork`/`stateMapMergeStates` which
allocates on the scratch arena. Per-function peak budget is 512 KiB; measured
max is 448 B (lisp). No budget concern.

## Follow-Up 2: Wire `handleFreeCall` into `onDoubleFreeStmt`

**Problem:** `handleFreeCall` (analyzer.zig:240-268) is the only emitter of
`ERR_2005_DOUBLE_FREE` and `WARN_6006_FREEING_UNTRACKED`. It has zero
production callers — `onDoubleFreeStmt` (analyzer.zig:723-734) routes
`fn_call` children to `handleOwnershipPass`, never to `handleFreeCall`.

**Fix:** In `onDoubleFreeStmt`, before routing to `handleOwnershipPass`, check
if the `fn_call` node is a free call via `isFreeCall`. If so, call
`handleFreeCall`. Also handle `expr_stmt`-wrapped calls by unwrapping
`expr_stmt` → check child_0.

**Expected diagnostics:** ERR_2005_DOUBLE_FREE, WARN_6006_FREEING_UNTRACKED.

## Follow-Up 3: Wire `visitStatement` into `runLifetimeAnalyzer`

**Problem:** `checkReturnProvenance` (analyzer.zig:102-170) emits
`ERR_2020`/`ERR_2021`/`WARN_6010`/`WARN_6011` for dangling reference returns.
It is called only from `visitStatement:677` — unreachable. `onLifetimeStmt`
(analyzer.zig:704-721) only records provenance into StateMap (no diagnostics).

**Fix:** Replace `onLifetimeStmt` with `visitStatement` in
`runLifetimeAnalyzer` (analyzer.zig:758). Or: add `checkReturnProvenance`
call to `onLifetimeStmt`'s `return_stmt` handler.

**Expected diagnostics:** ERR_2020_RETURN_ADDR_LOCAL,
ERR_2021_RETURN_SLICE_LOCAL, WARN_6010_RETURN_ADDR_PARAM,
WARN_6011_RETURN_SLICE_PARAM.

---

## Execution Order

1. Follow-Up 1 (null detection) — enables ERR_2004/WARN_6001/WARN_6002
2. Follow-Up 2 (double-free detection) — enables ERR_2005/WARN_6006
3. Follow-Up 3 (lifetime return checks) — enables ERR_2020/2021/WARN_6010/6011

Each should be a TDD task with its own non-vacuous test, corpus gate, and
4-example verification.

## Current State (post-F1, 2026-08-03)

- Guard fix (child_1→child_0): analyzers now run on all fn_decls with bodies
- Bug#2 fix (ident_expr via store.identifiers): ident resolution correct
- Non-vacuous leak test: testRunAllAnalyzers asserts WARN_6005 on sandAlloc leak
- Corpus: 161/19/6/0 (4 new FAILs from working signature analyzer)
- MD5s: unchanged from post-TCO baselines
- Phase gate: correctly wired, all skip flags work
