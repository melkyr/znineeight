# parsergap_slice_expr_xmod — GREEN-GUARD: scalar-base slice `n[1..]` correctly rejected (F-REJECT)

## What it tests
Slicing a **scalar** base with an open-ended `[a..]` form must be a **clean frontend
diagnostic**, not an internal-compiler error. Real Zig rejects it: `var n: u32 = 7;
var s = n[1..];` is a compile-time type error (expected array/slice/pointer, found u32).

```zig
const std = @import("std");

pub fn main() void {
    var n: u32 = 7;
    var s = n[1..];
    std.io.printInt(@intCast(i32, s.len));
}
```

Reclassified **GREEN-GUARD** (correct rejection, oracle-governed): 0 `.c` emitted,
`error[2000]` diagnostic only (plus two downstream cascades from `s` resolving to VOID),
no ICE, no crash.

## Fix (F-REJECT, commit `838935ce` — clean-reject non-sliceable slice base)
`sema` now rejects a slice base whose type is not array / slice / many-pointer / pointer
before lowering is reached (`sf/src/semantic_analyzer.zig:2168-2173`,
`semanticAnalyzerResolveSliceExpr`). The lowering `iceSliceUnsupported` fall-through
(`sf/src/lower.zig:4145` / `:820-837`, `error[9001]` "internal: unsupported slice_expr
form/base") is therefore unreachable for scalar/unsupported bases and remains only as a
defensive backstop for genuine internal bugs. This was the voiddecl-family F-REJECT task
(2026-08-20); Task 5.4 of the residual closeout plan verified and reclassified the fixture.

## Measured baseline — GREEN-GUARD (2026-08-24, `/tmp/fx_subfolder/zig1` rebuilt at HEAD `3000e96b`)
Run from the repro dir (CWD = repro dir; bare `@import("std")` resolves via the
installed std lib):
```
mkdir -p /tmp/rice && timeout 60 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rice main.zig
```
- **dump rc=2** (clean frontend rejection, exit code 2 — no flushAndExit(3)).
- stderr (verbatim):
```
main.zig:1:9: error[2000]: cannot slice base type: expected array, slice, or many-pointer
const std = @import("std");
         ^
main.zig:5:4: error[3000]: cannot declare variable of type void
    var n: u32 = 7;
    ^^^^^^^^^^^^^^^
main.zig:6:34: error[20]: identifier 's' is not declared or imported in this module
    var s = n[1..];
                                  ^
```
- **0 .c files emitted** (`/tmp/rice` empty). No `error[3043]`, no `error[9001]`, no ICE,
  no crash.
- The two trailing errors are the standard downstream cascade: because the slice resolves
  to VOID, `var s = ...` is a void-decl (`error[3000]`) and `s` never registers
  (`error[20]`). This matches the sibling green-guard fixtures' cascade class.
- Note: the `error[2000]` span points at `main.zig:1:9` (the `@import` region) — the
  F-REJECT guard passes the AST node index rather than the node's source span. Cosmetic
  (pre-existing, tracked in the residual closeout GATE-FINAL reconciliation).

## GREEN controls (supported bases unchanged, verified 2026-08-24)
Same `[a..]`/`[a..b]` forms on SUPPORTED bases all still compile and run correctly
(dump rc=0 | gcc rc=0 | run rc=0):
- array open-ended `var s = buf[1..];` → stdout `2`
- array two-bound `var s = buf[0..2];` → stdout `2`
- slice-of-slice open-ended `rem = rem[cut..];` (cut=1 over a 5-len slice) → stdout `3`

This pins the rejection class to the **base type** (scalar), not the `[a..]` form itself.

## Recipe
```bash
cd repro/mi_matrix/parsergap_slice_expr_xmod
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rice/out main.zig
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
  -I /workspace/znineeight/sf/src/include \
  /tmp/rice/out/*.c /workspace/znineeight/sf/src/include/zig_runtime.c \
  /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/rice/out/x
/tmp/rice/out/x
```
Expected: dump rc=2, clean `error[2000]` (0 `.c` → the gcc/link steps are not reached for
the fixture itself; the GREEN controls above use the same recipe and DO link/run).
