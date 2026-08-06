# comptime_const_chain — ident_expr const-chain folding  [comptime arithmetic folding plan, Task F8, 2026-08-06; classification confirmed OK F9 2026-08-06]

## What it tests
`comptimeEvalEvaluate` resolves `ident_expr` operands by following const
chains, so a const whose init references another const folds at comptime.
`const B: i32 = A + 5;` (where `const A: i32 = 30;`) folds to 35 and
`const C: i32 = B * 2;` folds to 70 — the emitted `__module_init` stores
`int_const 35` / `int_const 70` with no runtime `+` / `*` instructions.

## Upstream gap (pre-F8)
`comptimeEvalEvaluate` (comptime_eval.zig) had no `ident_expr` branch, so a
const init referencing another const returned null → the binop/unary comptime
fold (F1-F7) silently bailed → `B`/`C` lowered to runtime arithmetic even
though every operand was comptime-known. The array-size const-chain path
(`evalConstU32Full`, type_resolver.zig:579-598) already followed
symbol → `(flags & 0x01) == 0` (const) → `decl.child_1` recursion; F8 mirrors
that in `comptimeEvalEvaluateDepth` with a depth-16 guard so const cycles
(`const A = B + 1; const B = A + 1;`) cannot infinitely recurse.

## Expected classification
- **Pre-fix: FAIL (gcc error, NOT OK-with-runtime-gap).** The earlier draft
  claim that this was "OK with a runtime-gap annotation" was WRONG — measured
  pre-fix, the lowerer emits `load_global` for `A` in `A + 5`, and `A` (a
  non-storage const with a literal init) gets **no C storage-global decl** →
  `zG_..._A undeclared` → **gcc FAIL**. This is the same class of failure
  documented in the P0 source-note (`const A`/`const B` referenced only from
  other const initializers never receive storage-global decls). It is a real
  compile FAIL, not merely a fold-coverage gap.
- **Post-fix (F8):** emitted `__module_init` stores `int_const` 35 and 70;
  prints `3570` with the arithmetic fully folded away — a genuine FAIL→OK flip.
- F9 note (2026-08-06): classification **OK**, annotation cleared — see
  EXPECTED_FAIL.md F9 section.
