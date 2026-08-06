# comptime_array_size_gap — FAIL  [comptime arithmetic folding plan, Task P0, 2026-08-06]

## What it tests
Array sizes computed with comptime arithmetic on module-scope `const`
values: `[ROWS * COLS]u8` (=4000), `[ROWS / 2]u8` (=40), `[ROWS % 6]u8`
(=2). zig1 should resolve all three to concrete array types.

## Upstream gap (Gap 3 — type_resolver array-size handler misses mul/div/mod)
The array-size handler in `resolveTypeExprFull` (type_resolver.zig:869-911)
evaluates the size node for `int_literal`, `add`/`sub` (lines 879-887), and
`ident_expr` (lines 888-893) — but NOT `mul`, `div`, or `mod_op`. For
`[ROWS * COLS]u8` the size node is a `mul` node → falls through all
branches → `arr_len` stays 0 → `if (arr_len != 0)` (line 899) is false →
`TYPE_UNDEFINED` (line 911).

## Measured result (pre-fix, /tmp/z1/zig1) — SILENT TYPE-DROP, gcc-clean
The predicted `error: ISO C forbids zero-size array` does **NOT** occur.
The array type resolves `TYPE_UNDEFINED`, so the three `const` decls degrade
to uninitialized scalar globals and the array storage is dropped entirely:
- dump rc=0, 1 `.c` emitted.
- Emitted C: `int zG_..._CELLS;` / `int zG_..._HALF;` / `int zG_..._REM;`
  — plain `int` globals, NO `u8[N]` arrays, NO `[0]` anywhere, no
  `__module_init` assignment.
- gcc-clean (rc=0). **A silent semantic miscompile**: real Zig yields
  4000/40/2-byte arrays; zig1 emits uninitialized `int`s.

## Expected classification
- **Pre-fix: FAIL** per AMENDMENT P0-B (real semantic gap — the array
  declarations are silently dropped; counted FAIL until F3 fixes it). NOTE:
  the classifier (gcc exit code) reports OK because the emission is
  gcc-clean; the FAIL classification follows the operator ruling, not the
  predicted zero-size-array gcc error, which does not materialize. See
  `.superpowers/sdd/task-P0-report.md` for the discrepancy.
- **Post-fix (F3):** OK — gcc-clean with correct array sizes 4000, 40, 2.
