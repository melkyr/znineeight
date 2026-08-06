# comptime_u64_fold_overflow — u64 const fold >2^32 masking bug  [comptime arithmetic folding plan, Task F7, 2026-08-06]

## What it tests
A u64-annotated const whose folded value exceeds 2^32 must be stored and
printed at its declared width (u64). `const X: u64 = 3000000000 * 2;` folds
to 6000000000 and `const Z: u64 = 4294967295 + 1;` folds to 4294967296, but
the F4/F5 lowerer guard types the folded temp from the binop's resolved type
(TYPE_INT_LIT → remapped I32), so the `int_const` emitter masks the value to
32 bits → **wrong value** (1705032704 and 0). `const Y: u32 = 3000000000;`
(literal init, below 2^32) is the control and works.

## Why hi:lo printing instead of a single u64 printf
On the -m32 target, `%lu` is `unsigned long` = 32 bits, so it can never show
a value > 2^32 even after the fix (and `%llu` reads adjacent varargs slots
pre-fix because the arg is a 4-byte int). The repro therefore prints each u64
as two i32 halves computed at runtime: `hi = @intCast(u64, X) >> 32`,
`lo = @intCast(u64, X) & @intCast(u64, 4294967295)`.
- Correct X = 6000000000 = 0x1_65A0BC00 → prints `1:1705032704`.
- Correct Z = 4294967296 = 0x1_00000000 → prints `1:0`.
- Masked (pre-fix) X = 1705032704 → prints `0:1705032704`.
- Masked (pre-fix) Z = 0 → prints `0:0`.
The `& @intCast(u64, 4294967295)` form is used (not a bare `& 4294967295`)
so the mask constant is emitted as a u64 literal, avoiding the C int-wrap to
`-1` that would corrupt the low-32 extraction.

## Upstream gap (F4/F5 guard types the folded temp I32 for INT_LIT nodes)
In `lower.zig` the comptime_values guard on the 10 binary + 2 unary handlers
computes the temp type from `resolvedTypeTableGet(node_idx)` (the binop
node). A bare binop init resolves to TYPE_INT_LIT (19), so the guard remaps
to TYPE_I32. The declared u64 type lives on the var_decl node, not the binop,
and `resolved_types[var_decl]` is additionally clobbered to the init type
(main.zig:428-430), so both the folded temp AND the storage global end up
typed `int` → the value is masked to 32 bits at emission and at the store.

## Measured result (pre-fix, /tmp/f7base/zig1)
- dump rc=0, 1 `.c` emitted, gcc-clean (rc=0), links, runs.
- Prints `0:1705032704 3000000000 0:0` — X and Z masked to 32 bits (WRONG;
  correct values are 6000000000 = `1:1705032704` and 4294967296 = `1:0`).
- Emitted `__module_init`: `int zG_DD0C1E27_X; int zG_DF0C214D_Z;` and
  `zT_0 = 6000000000;` / `zT_1 = 4294967296;` into `int` temps — gcc
  truncates both to 32 bits with `[-Woverflow]` warnings.

## Expected classification
- **Pre-fix: OK with runtime-gap annotation** — gcc-clean with wrong runtime
  output, counted OK per the `load_global_array_copy`/`comptime_neg_int`
  precedent (gcc-exit classifier).
- **Post-fix (F7):** storage globals + folded temps typed u64; prints
  `1:1705032704 3000000000 1:0` — now OK with fully correct runtime output.
