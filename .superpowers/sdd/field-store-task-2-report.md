# Task 2 Report: RED Repro - Field Store Dropping Bug

## Status: Complete

## Files Created

- `repro/field_store_drop/main.zig` — Minimal Z98 repro for the findLocalTemp temp-0 collision
- `repro/field_store_drop/NOTES.md` — Detailed analysis of the bug, evidence, and root cause

## Build & Dump

- zig1 built successfully via `sf/scripts/build_release.sh`
- C89 dumped to `/tmp/fsd.c` with zero errors (exit code 0)

## Evidence

### Bug Confirmed by Code Analysis

`lower.zig:926` — `findLocalTemp` returns `0` as "not found" sentinel:
```zig
fn findLocalTemp(self: *LirLowerer, name_id: u32) u32 {
    ...
    return @intCast(u32, 0);
}
```

`lower.zig:322-358` — `nextTemp` starts counter at `0`, returns it, then increments:
```zig
pub fn nextTemp(self: *LirLowerer, type_id: TypeId) u32 {
    var tid = self.temp_counter;  // starts at 0
    ...
    self.temp_counter += @intCast(u32, 1);
    ...
    return tid;
}
```

`lower.zig:4011` — First function parameter gets `nextTemp` → temp 0:
```zig
var p_temp: u32 = nextTemp(self, type_mod.TYPE_UNDEFINED);
```

`lower.zig:1375-1378` — `plain_assign` drops store when src==0:
```zig
var src = lowerExpr(self, node.child_1);
if (src == @intCast(u32, 0)) {
    return @intCast(u32, 0);  // store dropped!
}
```

### Symptom in C89 Output

In `make` function C89, first param `a` (temp 0) requires extra `load_local`:
```c
zT_5 = a;     // load_local — arr_temp==0 fails check at lower.zig:1677
t.a = zT_5;   // store via intermediate temp
t.b = b;      // param b (temp 1) used directly
t.c = c;      // param c (temp 2) used directly
```

Second and third params return temp directly (line 1677 path), first param takes the fallback path (line 1678) creating unnecessary load_local. This is the direct symptom of the `findLocalTemp`/`nextTemp` sentinel collision.

### Latent Bug

The `plain_assign` store-drop at line 1376 is currently masked because the ident_expr handler at line 1678 creates a `load_local` when `arr_temp == 0`. However, ANY code path change that directly returns temp 0 from `lowerExpr` would trigger silent store dropping.

## Compilation Status

The C89 for `main` contains undeclared variable references (zT_11, zT_16, zT_20, etc.) — likely a related temp-0 collision in function pointer lowering. This prevents the binary from compiling, but is a separate (related) issue from the field store bug.

## Root Cause

Three overlapping sentinels on value 0:
1. `findLocalTemp` returns 0 = "not found"
2. `nextTemp` can return 0 = valid temp ID
3. `plain_assign` treats src==0 = "skip store"

## Recommended Fix

Move `nextTemp` to start at 1 (`temp_counter` initial value = 1), or change `findLocalTemp` sentinel to `0xFFFFFFFF`.
