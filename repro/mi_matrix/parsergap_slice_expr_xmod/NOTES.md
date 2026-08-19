# parsergap_slice_expr_xmod — error[3043] unsupported slice_expr base ICE repro  [R-ICE, 2026-08-19]

## Purpose
Task R-ICE of the VOID-decl family plan (docs/superpowers/plans/2026-08-18-voiddecl-family-plan.md,
lines 415-417). Durable RED repro of the `error[3043]: internal: unsupported slice_expr
form/base` ICE at `sf/src/lower.zig:722-739` (`iceSliceUnsupported`). This is the self-compile
blocker exposed after F1+F2 cleared all `error[3000]` VOID-decl errors (recorded at self-compile
as node 172203). F-ICE must turn this RED fixture GREEN.

## Fixture
`main.zig` — bare `@import("std")`, Z98 dialect (no anytype/@Type):
```zig
const std = @import("std");

pub fn main() void {
    var n: u32 = 7;
    var s = n[1..];
    std.io.printInt(@intCast(i32, s.len));
}
```

## Why this ICEs (lower.zig:3849-3921, slice_expr lowering)
The lowering supports only TWO base classes:
- **slice_type** base (`remaining[cut..]`, `data[0..len]`) → loads ptr+len fields, then computes
  ptr+start / len-start for the open-ended form.
- **array_type** base (`buf[0..]`, `buf[1..]`, `buf[0..2]`) → ptr_cast + int_const len.

For an open-ended form `base[start..]` (`node.child_1 != 0`, `node.child_2 == 0`) the len is taken
from `se_slice_len_box`, which is only set when the base type is slice/array. A **scalar** base
(here `u32`) sets no len box, the `node.child_1 != 0` branch cannot complete the `make_slice`, and
the function falls through to `iceSliceUnsupported` (lower.zig:3919-3921) → `error[3043]` via
`@enumToInt(ERR_9001_ICE)`, `flushAndExit(3)`.

The `[a..b]` two-bound form is exempt (it computes `len = end - start` directly, so it never
reaches the ICE). Only the open-ended `[a..]`/`[0..]` forms on a non-array/non-slice base (or an
undefined base, or a missing resolved-type entry) hit this path.

## RED baseline (2026-08-19, /tmp/fx_subfolder/zig1, run FROM fixture dir)
```
timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 --output-dir /tmp/rice/out main.zig
```
- **dump rc=3** (flushAndExit exit code 3).
- stderr (verbatim):
```
error[3043]: internal: unsupported slice_expr form/base (node 9)
```
- **0 .c files emitted** (`/tmp/rice/out` empty). Frontend-valid program (parses + passes sema +
  analyzers); the ICE fires in the lowering phase. RED.

## GREEN control (NOT committed — kept in /tmp/rice)
Same `[a..]` open-ended form, but on a SUPPORTED array base (only the base type differs):
```zig
const std = @import("std");

pub fn main() void {
    var buf = [3]u8{ 1, 2, 3 };
    var s = buf[1..];
    std.io.printInt(@intCast(i32, s.len));
}
```
```
dump rc=0 | gcc rc=0 | run rc=0 | stdout: "2"   ✓ GREEN
```
Also verified supported: array `buf[0..2]` (two-bound, prints `2`) and slice base
`rem = rem[cut..]` (open-ended slice-of-slice, prints `3`). This pins the class to the
**base type**, not the `[a..]` form itself.

## Post-F-ICE expectation
After the slice_expr lowering gap is fixed (per I-ICE/F-ICE), this fixture compiles GREEN: the
scalar-base open-ended slice no longer falls through to `iceSliceUnsupported`, `.c` is emitted,
and the run prints `6` (`7 - 1` = slice length). The ICE path at lower.zig:722-739 must not fire
for any base form. Same fixture, same recipe.

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
