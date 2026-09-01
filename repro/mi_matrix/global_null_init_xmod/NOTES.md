# global_null_init_xmod — FAIL (sema emission defect: module-scope optional global `= null`)  [Task R, 2026-08-13]

## What it tests
A **module-scope optional global initialized to `null`**:
```zig
const Node = struct { v: i32, next: ?*Node };
var g: ?*Node = null;
```
This is the exact shape of `examples/z98/lisp_interpreter` `parser.zig:12`
`var global_symbol_list: ?*SymbolNode = null;` — the construct that emits
`incompatible types when assigning to type 'zT_..._Opt_...' from type 'int'`
in lisp_interpreter.

## The compiler gap
The **global-init sema path** (`sf/src/main.zig:400-441`, the module-scope
`var_decl` `phase_ComptimeEvaluation` loop) resolves the init expression with
`pushExpectedType(decl_type)` but **never records the `wrap_optional_null`
coercion** — the `null_literal` init resolves to `TYPE_INT_LIT`/`int`, so the
lowerer emits a plain `int` temp for the null and assigns it to the
`Opt_...`-typed global. The `null` → `?*T` coercion branch that exists in the
local-var path is absent here. Emitted C is:

```c
void zF_780653D2___module_init(void) {
    int zT_0;
    z_bb_0:
    zT_0 = NULL;
    zG_E20C2606_g = zT_0;   /* Opt_26 := int — incompatible */
    return;
}
```

The lisp_interpreter original is identical
(`parser_F707FD5C.c:809` `incompatible types when assigning to type
'zT_2FE68298_Opt_49' from type 'int'`).

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- **gcc -c rc=1** — 1 error, the exact lisp error class:
  ```
  lib_5C71CE4C.c:16:21: error: incompatible types when assigning to type 'zT_AEEBC7B3_Opt_26' from type 'int'
     16 |     zG_E20C2606_g = zT_0;
  ```
  (plus a tolerated `-Wint-conversion` warning at line 15 for `zT_0 = NULL;`).
- Post-fix expected: print `1` (`get()` returns null → `p == null`), run rc=0.
- Corpus classification: **FAIL** (emission defect — real compiler gap).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (with the zig0-compatible
`__bootstrap_print_int` main variant): dump rc=0, emits `lib.c`/`main.c`;
gcc -c rc=0; **link+run rc=0, prints `1`**. zig0 emits
`static Optional_..._g = {0};` — the null global is a valid static init, no
`int` temp — proving the construct is valid Z98 and the missing
wrap_optional_null coercion is a genuine zig1 sema gap.

## Expected classification
**FAIL pre-fix → OK post-fix** (F1/F2 must type the global-init null temp as
the optional type, emitting a null-optional construction instead of `int`).
