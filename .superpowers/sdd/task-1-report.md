### Task 1 Report: Capture rename edge-case RED repro suite

**Status:** DONE

**Commit:** `2bc17580` — `test(repro): RED capture rename edge-case repros (switch, catch, for, nested, shadow)`

**Files created:**
- `repro/capture_rename/main.zig` — 6 test cases covering switch, catch, for-in, nested, and shadow captures
- `repro/capture_rename/NOTES.md` — expected vs actual output, root cause analysis

**Gate evidence:**
- `=== [release] Done: sf/build/out_release/zig1 ===` — build succeeded
- `dump rc=0` — zig1 compiled repro successfully
- `gcc rc=0` — C output compiled successfully
- `timeout 3 /tmp/capr` → `77542630` with rc=124 (timeout from for-in infinite loop)

**RED cases identified:**

| Case | Pattern | Expected | Actual | Root Cause |
|------|---------|----------|--------|------------|
| **CASE 2** | catch same-name same-type | 99 | **77** | `maybeDisambiguateCapture` not called for catch captures (lower.zig:2446-2447). Second `\|err\|` aliases first catch's error code temp. |
| **CASE 3** | for-in same-name | 30 | **(infinite loop)** | General codegen bug: missing loop counter update in C for for-in over slice. Not capture-specific. |

**Cases that PASSED (no RED):**
- CASE 1: switch same-name same-type — switch captures are scoped (local_decl_count restored after prong lowering at lower.zig:2848/:3469)
- CASE 4: switch diff-type — maybeDisambiguateCapture correctly renames
- CASE 5: catch shadow var_decl — no ICE, compiles
- CASE 6: nested captures (switch + while) — works correctly

**Key finding for CASE 2:** The catch lowering code at lower.zig:2441-2448 directly uses `addLocalDecl` with the raw capture name without calling `maybeDisambiguateCapture`. This causes duplicate local decl entries with the same name but different temps. `findLocalTemp` returns the first match, so the second catch body references the wrong error code.

**Adaptations needed from brief:**
- Brief used plain `enum` switch — zig1 only supports `union(enum)` switch with captures
- Brief used `for (a_arr[0..3])` — zig1 only supports `for (array)`
- Brief used `print_nl` with `std`/`pal` — used `__bootstrap_print_int` instead
- Brief used `if (false) { }` blocks — removed, unnecessary for the test
- For-in tests use slice for-in (compiles but infinite loops) instead of array for-in (gcc compile error)
- Cases reordered so CASE 3 (for-in infinite loop) runs last, allowing earlier cases to produce output
