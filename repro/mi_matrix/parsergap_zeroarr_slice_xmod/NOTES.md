# parsergap_zeroarr_slice_xmod — zero-length array `[0]u32` slice ICE repro  [F-ICE, 2026-08-20]

## Purpose
Task F-ICE (RE-SCOPED) of the VOID-decl family plan (docs/superpowers/plans/2026-08-18-voiddecl-family-plan.md,
AMENDMENT 4, lines 449-453). Durable RED→GREEN repro of the **zero-length array** sub-class of the
`error[3043]: internal: unsupported slice_expr form/base` ICE (`iceSliceUnsupported`, lower.zig:722-739).
This is the recorded self-compile blocker node 172203 = `source_manager.zig:135/137`. I-ICE mapped it:
the `arr_len != 0` guard at `type_resolver.zig:1002` drops `[0]u32` arrays → the `dummy` symbol never
registers → the ident resolves VOID → the open-ended slice lowering finds no len box → `error[3043]`.

## Fixture
`main.zig` — bare `@import("std")`, Z98 dialect (no anytype/@Type). Mirrors
`source_manager.zig:135/137` verbatim: `var dummy: [0]u32 = undefined; return dummy[0..];` inside an
`if`, wrapped in a `sourceManagerGetLineOffsets`-style fn. The `[0..]` open-ended form is required:
the two-bound `[a..b]` form is exempt (it computes `len = end - start` and can never reach the ICE).

## RED baseline (2026-08-20, /tmp/fx_subfolder/zig1 PRE-FIX binary, run FROM fixture dir)
```
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rice/out main.zig
```
- **dump rc=3** (flushAndExit(3)).
- stderr (verbatim):
```
error[3043]: internal: unsupported slice_expr form/base (node 19)
```
- **0 .c files emitted** (`/tmp/rice/out` empty). RED.

Note on the fixture form: the `var s = dummy[0..]` assignment form (top-level var, no return) does
NOT reach the ICE — sema infers `var s` as VOID (unregistered `dummy` → VOID base → VOID slice) and
aborts earlier with `error[3000] cannot declare variable of type void` (rc=2). The `return dummy[0..]`
form (as in source_manager.zig:135/137) has no var to infer, so it survives sema and reaches lowering
→ `error[3043]` rc=3. This fixture pins the ICE locus exactly as recorded.

## GREEN (post-fix expectation, verified 2026-08-20)
After the F-ICE 3-loci fix (zero-length array type resolution + array-init element resolution + temp
sentinel), the construct compiles and runs:
```
dump rc=0 | gcc rc=0 | run rc=0 | stdout: "0"
```
(`sourceManagerGetLineOffsets(0)` returns `dummy[0..]`, length 0.)

## Recipe
```bash
cd repro/mi_matrix/parsergap_zeroarr_slice_xmod
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rice/out main.zig
for f in /tmp/rice/out/*.c; do gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
  -I /workspace/znineeight/sf/src/include -c "$f" -o /dev/null || exit 1; done
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign \
  -I /workspace/znineeight/sf/src/include \
  /tmp/rice/out/*.c /workspace/znineeight/sf/src/include/zig_runtime.c \
  /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/rice/out/x
timeout 60 /tmp/rice/out/x
```
