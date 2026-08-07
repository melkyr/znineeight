# Task 1 Report: visitStatement plumbing (signature + recursive calls + test callers)

**Status:** DONE_WITH_CONCERNS
**Commit:** `7bc6e4d122a1cf33aecf549d16b57b3821530ffe`
**Branch:** `zig1_start`
**Date:** 2026-08-03

---

## What I implemented

All edits applied exactly per the brief (`/.superpowers/sdd/task-1-brief.md`), verbatim oldString→newString.

### `sf/src/analyzer.zig` — 6 edits
1. Line 643: added 5th param `visit_fn` to `visitStatement` signature.
2. Line 657: if_stmt/if_capture then-branch `walkBlock(..., on_stmt)` → `visit_fn`.
3. Line 658: if_stmt/if_capture else-branch `walkBlock(..., on_stmt)` → `visit_fn`.
4. Line 666: while_stmt/while_capture body `walkBlock(..., on_stmt)` → `visit_fn`.
5. Line 674: switch prong body `walkBlock(..., on_stmt)` → `visit_fn`.
6. Line 679: for_stmt body `walkBlock(..., on_stmt)` → `visit_fn`.

`walkBlock` stays 4 params (confirmed at analyzer.zig:624). The `on_stmt` direct-call sites inside `visitStatement` (return_stmt, var_decl, plain_assign, else branch) remain unchanged, and the other `walkBlock` entry points at 749/768/773 (onNullStmt/onLifetimeStmt/onDoubleFreeStmt) are untouched — plumbing only.

### `sf/src/tests/test_semantic_bin.zig` — 4 edits
- 1612, 1649: `branchVisitSet, branchVisitSet`
- 1758: `countVisitCb, countVisitCb`
- 1798: `deferVisitCb, deferVisitCb`

No other callers of `visitStatement` exist (grep verified).

## What I tested

### build_release.sh
```
=== [release] Done: sf/build/out_release/zig1 ===
```
Gate line present, script exited 0, 0 gcc errors (only harmless -Wall warnings).

### build_test.sh
```
  PASS: test_analyzer_bin
  PASS: test_memory_budget_bin
  PASS: test_lower_bin
  PASS: test_name_mangle_bin
  PASS: dump_ir_bin
  FAIL: could not read file: examples/hello/main.zig
=== [test] Results: 5 passed, 4 failed ===
```

**CONCERN — test_semantic_bin does not compile, PRE-EXISTING at HEAD, unrelated to Task 1:**
`sf/src/tests/test_semantic_bin.zig:61` calls `sa_mod.semanticAnalyzerInit(&arena, &rtt, &diag, &typereg, &symreg, &store, @intCast(u32, 0), &ct)` (8 args) but `semanticAnalyzerInit` now has a **13-parameter** signature (semantic_analyzer.zig:63). The type-mismatch errors repeat for every test fn (line 61/84/107/…), so the whole test binary fails to compile. These errors are at line ~61, far from my 4 call-site edits (1612/1649/1758/1798).

**Evidence it is pre-existing:** I `git stash`ed my two files, re-ran `build_test.sh`, and got the identical result (5 passed, 4 failed, test_semantic_bin compile errors). Restored my changes afterward (diff verified intact).

The `semanticAnalyzerInit` signature grew (13 params incl. `source_file_id`, `enum_val_tab`, `interner`, `cal_typs`, `cp_map`) without the test file being updated. Fixing that is out of scope for Task 1 (not in the brief, would touch dozens of test call sites). The brief's Step 6 expectation that "test_semantic_bin passes" is not met — the gate cannot be satisfied from this commit alone.

## Files changed

```
 sf/src/analyzer.zig                | 12 ++++++------
 sf/src/tests/test_semantic_bin.zig |  8 ++++----
 2 files changed, 10 insertions(+), 10 deletions(-)
```

## Self-review

- **Completeness:** All 6 analyzer.zig edits + 4 test_semantic_bin.zig edits applied exactly per brief. ✓
- **Discipline:** Only the two specified source files committed. No out-of-plan changes. `.superpowers/sdd/task-1-report.md` (this file) had pre-existing uncommitted edits from a prior task; I did not stage it. ✓
- **Testing:** build_release DONE, 0 errors. test_analyzer_bin PASS. test_semantic_bin compile gate NOT met — pre-existing `semanticAnalyzerInit` signature mismatch at HEAD, unrelated to and unfixable within Task 1 scope.

## Issues / concerns

1. **test_semantic_bin gate unmet (pre-existing).** The controller should either (a) dispatch a separate task to update the ~dozens of `semanticAnalyzerInit` call sites in test_semantic_bin.zig to the 13-param signature, or (b) rule that the test_semantic_bin gate is deferred. Task 1's own 4 call-site edits are correct and complete.
2. No runtime corpus / byte-identical gates run — not required by the Task 1 brief (plumbing only, no emission-path change).
