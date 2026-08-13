# sizeof_struct_union_xmod — Defect-D repro (sizeOf/alignOf struct-with-union layout ordering)  [Task R3, 2026-08-13]

## What it tests
A struct that embeds a **bare union by value** where the union type is declared
AFTER the struct (`Value` after `Data`, `Tag` before both): `@sizeOf(Value)` +
`@alignOf(Value)` summed and printed. Correct layout: `Value` = 16 bytes /
align 8 (`tag: Tag` enum = 4 bytes; `data: Data` union = 8 bytes — i64/f64 =
8, `[]const u8` slice = 8 on this 32-bit target → union max 8, align 8; struct
= 4 + pad(4) + 8 = 16). `compute(0)` returns `16 + 8 = 24`. Declaration order
(union AFTER the struct) is deliberate: the layout topological-sort LIFO
worklist pops `Value` FIRST, before its `Data` union field type is sized — the
exact Defect-D ordering symptom (lisp `Value`=1/1, `JsonValue`=8).

## The compiler gap
The dependency graph driving layout ordering carries **dummy edges**:
`addTypeDependencies` (`sf/src/symbol_registrator.zig:78`) adds `0 -> tid` for
every field of a struct/union decl (the graph is built during symbol
registration, when field `type_id`s are still `TYPE_VOID` placeholders — so a
real `field_type -> container_tid` edge CANNOT be added yet; the field types
are resolved later by `resolveAggregateFieldTypesAll`,
`sf/src/type_resolver.zig:1078-1096`). With no real dependency edge from
`Value` to `Data`, the topological sort emits `Value` first (LIFO), its layout
runs while `Data`'s size is still 0/1 → `typeResolverResolveLayout`
(`sf/src/type_resolver.zig:104-131`) computes the struct with a 0-byte union
field, then clamps `size==0 → 1/1` at :130. The readers (`comptimeEvalBuiltin`,
`sf/src/comptime_eval.zig:120/129`) then fold `@sizeOf(Value)` = 1,
`@alignOf(Value)` = 1.

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 4 modules emit (main, lib, std, std_io).
- **gcc -c rc=0**, link rc=0.
- **run rc=0** — prints **`2`** (size 1 + align 1; expected pre-fix: collapsed
  1/1). NOT `24`.
- Emitted `lib_36FB2E32.c`: `zT_7 = 1; s = zT_7;` (@sizeOf) and
  `zT_9 = 1; a = zT_9;` (@alignOf) — both folded to constant 1.
- Corpus classifier: **FAIL** (runtime-gap-tracked — compiles and runs, prints
  the wrong `2`; NOT counted as a raw corpus FAIL).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy (oracle main.zig uses the `__bootstrap_print_int`
convention — zig0 cannot parse the post-F4 `@putChar`/`@stdoutWrite` std_io
builtins). zig0 rc=0, emits lib.c/main.c; gcc -c rc=0, link rc=0; **run rc=0
prints `24`** — the CORRECT value. Emitted `lib.c`: `usize s = 16; usize a = 8;`
(Value 16/8; the brief's `32` prediction assumed a 24-byte union — the union is
8 bytes on this target, so the honest oracle value is 24). This is the
post-fix reference.

## Expected classification
FAIL pre-fix (layout ordering: struct laid out before its union field type is
sized → size/align 1/1) → OK post-fix (prints `24`). Guards Defect D (F5 gate) —
`typeResolverBuildDependencyGraph` must add real `field_type -> container_tid`
edges after field-type resolution so `Value` is laid out AFTER `Data`.
