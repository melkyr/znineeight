# union_literal_nested_xmod — FAIL (lowerer emission defect: bare-union literal inside a struct literal)  [Task R, 2026-08-13]

## What it tests
A **bare union literal nested inside a struct literal**: `Wrapper{ .tag = Tag.A,
.data = Inner{ .Int = v } }` where `Inner` is a plain (untagged) union and `data`
is a struct field. This is the exact shape of `examples/z98/lisp_interpreter`
`token.zig`'s `Token{ .tag = ..., .data = TokenData{ .Int = ... } }` returns —
the construct that emits `'zT_N' undeclared` in lisp_interpreter and is the
sole gcc-FAIL in the 21-example matrix (20/21 end-to-end).

## The compiler gap
The struct-literal path never handles a **union** field-initializer. In
`semanticAnalyzerResolveStructInit` (`sf/src/semantic_analyzer.zig:1029`) the
field-loop dispatches on struct/tagged-union/payload member kinds but has **no
branch for a bare `union` type** (the `tgt.kind == TypeKind.tagged_union_type`
and struct branches exist; a plain `union_type` field falls through). The
lowerer's struct-init loop (`sf/src/lower.zig:3283-3423`) emits the field
assignment `zT_1.data = zT_3;` via `emitFieldAssign`
(`sf/src/c89_emit.zig:188`) but the **inner union temp (`zT_3`) is never
declared** — the union construction (which should set `zT_3.Int = v`) is
dropped. Emitted C is:

```c
zT_2 = zT_F8835433_Tag_A;
zT_1.tag = zT_2;
zT_1.data = zT_3;   /* zT_3 never declared */
return zT_1;
```

The lisp_interpreter originals are identical (`token_89A7AC30.c:293/317/334/468/499`).

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- **gcc -c rc=1** — 1 error, the exact lisp error class:
  ```
  lib_EEE8C47D.c:9:17: error: 'zT_3' undeclared (first use in this function); did you mean 'zT_2'?
      9 |     zT_1.data = zT_3;
  ```
- Post-fix expected: print `42` (`makeWrapper(42).data.Int`), run rc=0.
- Corpus classification: **FAIL** (emission defect — real compiler gap).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (with the zig0-compatible
`__bootstrap_print_int` main variant, since zig0 has no `@putChar`/`@stdoutWrite`
builtins): dump rc=0, emits `lib.c`/`main.c`; gcc -c rc=0; **link+run rc=0,
prints `42`**. zig0 emits `__return_val.data.Int = v;` directly — no dropped
temp — proving the construct is valid Z98 and the bare-union-in-struct-literal
construction is a genuine zig1 lowerer gap.

## Expected classification
**FAIL pre-fix → OK post-fix** (F1/F2 must emit the inner union construction —
declare the union-typed temp and set its member before the field assign).
