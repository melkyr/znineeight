# Capture Rename Edge-Case RED Repro

Commit: (to be filled after commit)
Status: RED - Case 2 catch same-name same-type produces wrong output

## Test Cases

### CASE 1: Switch capture same-name same-type (cross-switch)
- **Expected:** 5 (from s1=2, s2=3, sum=5)
- **Actual:** 5
- **Is RED?** No - switch captures are scoped (local_decl_count restored after prong lowering at lower.zig:2848 and :3469). Cross-switch same-name captures don't conflict.

### CASE 2: Catch capture same-name same-type (cross-catch)
- **Expected:** 99 (second catch body uses er=error.Other, sets c_err=99)
- **Actual:** 77 (second catch body uses er from FIRST catch, which is error.OutOfMemory)
- **Is RED?** YES - RED
- **Root cause:** lower.zig:2446-2447 does `addLocalDecl(capture_name, ...)` without calling `maybeDisambiguateCapture`. When two catch expressions in the same function both capture `|err|`, the second `addLocalDecl` creates a duplicate entry. `findLocalTemp` (lower.zig:927) returns the first entry's temp, so `err` in the second catch body references the first catch's error code. The first catch has error.OutOfMemory, so `err == error.Other` is false, setting c_err=77 instead of 99.
- **Classification:** maybeDisambiguateCapture not called for catch captures

### CASE 3: For-in capture same-name as previous for-in
- **Expected:** 30 (24 + 6)
- **Actual:** No output (infinite loop in generated C)
- **Is RED?** YES - RED (separate codegen bug)
- **Root cause:** For-in over slice generates C with missing loop counter update: `zT_26 = zT_21 + zT_25; goto z_bb_1;` — `zT_21` is never assigned `zT_26`. This is a codegen bug in the C89 emitter, not specific to capture renaming. Happens even with single for-loops.

### CASE 4: Switch capture same-name different-type
- **Expected:** 42 (5 + 37)
- **Actual:** 42
- **Is RED?** No - maybeDisambiguateCapture correctly renames when types differ (existing behavior works).

### CASE 5: Catch capture same-name as var_decl
- **Expected:** 6 (placeholder — success if no ICE)
- **Actual:** 6
- **Is RED?** No - zig1 compiles and runs without ICE for this case.

### CASE 6: Nested captures (for-in inside switch prong)
- **Expected:** 30 (10 + 20)
- **Actual:** 30
- **Is RED?** No - nested captures work correctly. Uses while loop to avoid for-in infinite loop bug.

## Summary

| Case | Description | Expected | Actual | RED? |
|------|-------------|----------|--------|------|
| 1 | Switch same-name same-type | 5 | 5 | No |
| 2 | Catch same-name same-type | 99 | 77 | **YES** |
| 3 | For-in same-name | 30 | (infinite loop) | **YES** |
| 4 | Switch diff-type | 42 | 42 | No |
| 5 | Catch shadow var_decl | 6 | 6 | No |
| 6 | Nested captures | 30 | 30 | No |

## RED Cases Identified

1. **Case 2 (catch capture):** `maybeDisambiguateCapture` is not called for catch captures in lower.zig:2446-2447. Second catch with same capture name aliases first catch's decl. Fix: call `maybeDisambiguateCapture(self, capture_node.payload, type_mod.TYPE_I32)` before `addLocalDecl` in the catch lowering.

2. **Case 3 (for-in capture):** General codegen bug in C89 emitter — loop counter assignment missing in generated C for for-in over slice. Fix: add `zT_index = zT_next;` before `goto` in the for-loop lowering. This is not capture-specific.
