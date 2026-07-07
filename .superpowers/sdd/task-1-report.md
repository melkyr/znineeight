# Task 1 Report — Array-base slice honors explicit `[start..end]`

## Edit Made
**File:** `sf/src/lower.zig`, line 2710

**Before:**
```zig
                if (se_bty.kind == type_mod.TypeKind.array_type) {
```

**After:**
```zig
                if (se_bty.kind == type_mod.TypeKind.array_type and node.child_2 == @intCast(u32, 0)) {
```

## RED Output
`8` (slice repro with unpatched binary prints array length instead of `3`)

## GREEN Outputs
- `repro/bool_literal_lower` → `13` ✅ (prints `1` then `3`)
- `repro/slice_array_end` → **FAILS TO COMPILE**: `assignment to expression with array type` at `buf + zT_15`

## [release] Done Confirmation
Build prints `[release] Done` (zig1-dump errors are expected/pre-existing).

## Concerns
**BLOCKED**: The bounds-aware path (lines 2734-2748) produces invalid C for array-based slices. When `node.child_2 != 0` and the base is an array type, the code falls through to the bounds-aware path which computes `se_ptr = se_slice_ptr + se_start`. For array types, `se_slice_ptr` is `se_base` (the array temp), not a pointer. The emitted C attempts pointer arithmetic on an array-typed expression, which gcc rejects with `assignment to expression with array type`.

Per the brief instruction: "STOP-and-present if the bounds-aware path produces invalid C for an array base (e.g. base + start or make_slice on the array temp does not yield a valid decayed pointer / fails to gcc-compile)."
