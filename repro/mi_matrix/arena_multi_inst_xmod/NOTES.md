# arena_multi_inst_xmod — FAIL (emission defect: `_N` module-instance suffix on struct typedef but not fn-signature type refs)  [Task R1 amended, 2026-08-14]

## What it tests
A `std_arena`-style struct type imported via **two different resolved paths** (`a/std_arena.zig` and `b/std_arena.zig`, byte-identical), each used by a distinct sibling module (`mod_a` / `mod_b`). This forces `module_registry` to create **two module instances** for the same source, so the emitter applies its `_N` module-instance suffix to the struct typedef. This is the exact shape of the D2 defect (std-lib final review Imp-2): the struct typedef gets the `_N` suffix but the fn-signature type references do not, so the instance-≥1 consumer emits C that gcc rejects as `return type is an incomplete type`.

Same-dir sibling imports would NOT trigger this — `module_registry.zig:266-272` dedups `@import` by **resolved full path**, so `mod_a`/`mod_b` both `@import("std_arena.zig")` would collapse to a single instance (no `_N` suffix). Hence the two-subdir layout (Option A).

## The compiler gap
The emitted C splits the struct typedef name and the fn-signature type-ref name. Instance-1 module `std_arena_38F3EE28.h` declares the struct as `zT_F22A6288_Arena_1` (suffixed) but declares the function with the **unsuffixed** type `zT_F22A6288_Arena`:

```c
struct zT_F22A6288_Arena_1 { ... };              /* typedef suffixed with _1 */
zT_F22A6288_Arena zF_26BB595D_create(void);       /* fn ref UNSUFFIXED -> incomplete */
```

The unsuffixed typedef is never defined in this module, so gcc reports an incomplete type. The mismatch lands on whichever module carries the `_N` instance suffix; the sibling instance (`std_arena_D7A6DF65.h`) is self-consistent (both suffixed-free) and compiles clean.

## Measured result (2026-08-14, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 7 modules emit (main, mod_a, mod_b, std, std_io, std_arena ×2).
- **gcc -c rc=1** — 3 files fail, the exact D2 error class:
  ```
  mod_b_2C00A0A0.c:3:21: error: return type is an incomplete type
  mod_b_2C00A0A0.c:3:21: error: conflicting types for 'zF_FCECD717_makeB'; have 'void(void)'
  mod_b_2C00A0A0.c:4:25: error: storage size of 'zT_0' isn't known
  std_arena_38F3EE28.c:3:19: error: return type is an incomplete type
  std_arena_38F3EE28.c:3:19: error: conflicting types for 'zF_26BB595D_create'; have 'void(void)'
  std_arena_38F3EE28.c:4:23: error: storage size of 'zT_0' isn't known
  mod_a_9C875CFD.c:6:12: error: invalid use of incomplete typedef 'zT_F22A6288_Arena'
  ```
- Corpus classification: **FAIL** (emission defect — real compiler gap).

## Oracle verification (zig0)
**Oracle: N/A** — zig0 lacks `@putChar` and rejects struct-literal returns; RED evidence is the gcc error class only. (Per operator ruling 2026-08-14: skip the zig0 run; do not attempt it.)

## Expected classification
**FAIL pre-fix → OK post-fix** (I1/F1 must apply the `_N` module-instance suffix consistently to BOTH the struct typedef and the fn-signature type references in instance-≥1 modules).
