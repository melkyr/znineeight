# union_emission_layout_xmod — Defect-E repro (bare-union C emission layout)  [Task R4, 2026-08-13]

## What it tests
A **bare (untagged) union's C89 emission layout**: `Data = union { I: i64, S:
[]const u8, F: f64 }` nested in `Value = struct { tag: Tag, data: Data }`.
`@sizeOf(Data)` folds to the union-max (8 on 32-bit: i64/double/Slice all 8B)
while the emitted C type is the corruption vector. The gate is the **gap
between `@sizeOf` (comptime union-max) and the C runtime size of the emitted
type**: arena allocators sized by `@sizeOf` overflow when the runtime stores a
larger C struct (lisp_interpreter / json_parser_workaround SEGFAULT).
Prints `v.data.I` (reads back `7`), `@sizeOf(Data)`, and `@sizeOf(Value)`.

## The compiler gap
`emitUnionType` (`sf/src/c89_emit.zig:1528-1553`) writes `"struct "` at line
1536 instead of `"union "` — all union members are **STACKED** into a C struct
(8+8+8 = 24B for `Data`; `Value` = tag 4 + pad 4 + Data 24 = 28B) instead of a
C `union` (max member = 8B). `@sizeOf(Data)` = 8 and `@sizeOf(Value)` = 16 are
folded correctly (union-max / post-Defect-D layout), so the emitted-C size
**exceeds** `@sizeOf` by 3x / 1.75x → arena overflow → memory corruption →
SEGFAULT. zig0 emits a real `union`, proving the C-level layout is the defect.

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- Emitted `zig_special_types.h` (guard name `ZIG_UNION_zT_3F5279C5_Data` but
  body is a struct):
  ```c
  struct zT_3F5279C5_Data {      /* STACKED, not a union */
      zT_C69B2266_i64 I;                        /* 8  */
      zT_8F083A69_Slice_zT_0B42B2F8_u S;        /* 8  */
      double F;                                 /* 8  */
  };                                            /* = 24 */
  struct zT_D147F96A_Value {
      zT_F8835433_Tag tag;                      /* 4  */
      zT_3F5279C5_Data data;                    /* 24 */
  };                                            /* = 28 */
  ```
- **C runtime sizes (throwaway C `sizeof`, gcc -m32): `sizeof(struct Data)` =
  24, `sizeof(struct Value)` = 28.**
- **`@sizeOf(Data)` = 8, `@sizeOf(Value)` = 16** (comptime-folded, emitted as
  constants in `main.c`). **Mismatch = 24-vs-8 (3x) and 28-vs-16 (1.75x)** — the
  red state (allocator sized by `@sizeOf` under-allocates the C struct).
- **run rc=0 — prints `7816`** (`7` = `v.data.I` reads back OK because the
  stacked layout preserves the first field, then `8` = `@sizeOf(Data)`, then
  `16` = `@sizeOf(Value)`).
- Corpus classification: **FAIL** (emission defect — real compiler gap; runs but
  the emitted struct layout is 3x larger than `@sizeOf`).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (zig0 uses `__bootstrap_print_int` — no
`@putChar`/`@stdoutWrite` builtins; links `/workspace/znineeight/src/runtime/
zig_runtime.c`). zig0 rc=0, emits **a real C union**:
```c
union zS_46b3f0f3_c838099e_Data {
    i64 I;
    Slice_u8 S;
    double F;
};
struct zS_46b3f0f3_267500bf_Value {
    enum zS_46b3f0f3_d295e55e_Tag tag;
    union zS_46b3f0f3_c838099e_Data data;
};
```
gcc rc=0, run rc=0 prints **`7816`**. C `sizeof(union Data)` = **8 — matches
`@sizeOf(Data)` = 8, no mismatch for the union itself** (the 24B-vs-8B gap is
zig1-only). Secondary note: oracle `struct Value` = 12 vs `@sizeOf(Value)` = 16
— a residual enum-tag-representation gap (C `enum` = int 4B vs Z98 u-tag 1B),
present in zig0 too, orthogonal to Defect E.

## Expected classification
**FAIL pre-fix → OK post-fix** (F6 must make `emitUnionType` write `"union "`
at c89_emit.zig:1536 so the emitted C layout matches `@sizeOf`'s union-max; the
`Data`-size gate 24→8 is the green condition).
