# voiddecl_ifexpr_ctl_xmod — GREEN control: literal branches do NOT trigger

**Status: DONE** (2026-08-19, amended brief). The literal form (`if (kind == 1) 13
else 12`) does NOT reproduce the lower.zig:4410 void collapse. This fixture is the
negative control for the RED trigger in `voiddecl_ifexpr_xmod/`.

## Purpose
Task R1 (amended) of the voiddecl-family plan. The original brief fixture (literals
`13`/`12`) was GREEN — the reason the first R1 attempt was BLOCKED. The amended
brief re-purposes this literal form as the GREEN control documenting the negative,
alongside the module-const RED trigger.

## Fixture (main.zig, committed, md5 `eb24c825a12883aa26ae79303c7e7921`)
```zig
const std = @import("std");
pub fn main() void {
    var kind: u32 = 0;
    var cmp_op = if (kind == 1) 13 else 12;
    std.io.printInt(cmp_op);
}
```
Byte-exact to the original brief Step 1 / prior BLOCKED fixture (md5 matches).

## GREEN baseline (Step 5)
Recipe (from fixture dir):
`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
```
rc = 0
stderr = (empty)
stdout (.c) = 10640 bytes
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include /tmp/x.c /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o /tmp/x   → rc = 0
run: prints "12", run rc = 0
```
Emitted C fully correct: `int cmp_op;`, `if (zT_5) goto ...`, branches 13/12,
`printInt(cmp_op)`.

## Negative finding (literal-does-not-trigger)
The value-position `if (bool) A else B` shape alone is NOT the trigger:
- literals both branches → GREEN (this fixture).
- enum / bool / struct branch VALUES → GREEN (see trigger matrix variants 7-9).
- annotated module consts (`: u8`) → GREEN (trigger matrix variant 10).

RED requires an **untyped module-level `const`** (`const X = <expr>;`, no type
annotation) referenced in an inferred var-init — bare, in a binary op, or as BOTH
if-branches. The real `lower.zig:4410` statement's branches `BIN_LE`/`BIN_LT` are
such untyped module consts (`const BIN_LT = @intCast(u8, 12);`, lower.zig:50-51),
which is why self-compile errors there while this literal fixture compiles clean.

## Cross-ref
RED trigger: `repro/mi_matrix/voiddecl_ifexpr_xmod/` (full matrix + blast-radius
lead in its NOTES.md).
Prior BLOCKED report: `.superpowers/sdd/task-R1-voiddecl-report.md`.
