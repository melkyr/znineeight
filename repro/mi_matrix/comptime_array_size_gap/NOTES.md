# comptime_array_size_gap — OK (runtime gap RESOLVED by F6)  [comptime arithmetic folding plan, Task P0, operator ruling P0-E, 2026-08-06; annotation cleared F9 2026-08-06]

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

## Expected classification (operator ruling P0-E, 2026-08-06)
- **Class: OK with runtime-gap annotation** — under the QUICK_REF gcc-exit
  classifier the emission is gcc-clean (rc=0), so this is **OK**, NOT FAIL.
  The gap is a **silent semantic miscompile**: real Zig yields
  4000/40/2-byte arrays; zig1 silently emits uninitialized `int` globals
  with no diagnostic. Counted OK following the
  `comptime_neg_int`/`load_global_array_copy` runtime-gap precedent (the
  gcc-exit classifier reports OK; the miscompile is tracked as a runtime
  gap, not as a compile FAIL).
- The earlier FAIL classification (AMENDMENT P0-B) is superseded by the
  P0-E operator ruling; the predicted `error: ISO C forbids zero-size
  array` does not materialize. See
  `.superpowers/sdd/task-P0-report.md` for the discrepancy + ruling.
- **Post-fix (F6, verified at F9):** gcc-clean with correct array sizes
  4000, 40, 2 — the runtime gap closes. Measured 2026-08-06 (F9): emitted
  `typedef unsigned char …[4000];` / `…[40];` / `…[2];` — `CELLS`/`HALF`/`REM`
  are real `u8[N]` storage globals. **Annotation cleared — plain OK.**
