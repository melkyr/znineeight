# comptime_binop_not_folded — OK with emission-gap annotation  [comptime arithmetic folding plan, Task P0, 2026-08-06]

## What it tests
12 bare binary/unary const-fold operations at module scope, one per op:
`30 + 10`, `30 - 10`, `30 * 10`, `30 / 10`, `30 % 10`, `-30`, `30 & 10`,
`30 | 10`, `30 ^ 10`, `30 << 2`, `30 >> 2`, `~30`. All operands are
comptime-known, so zig1 SHOULD fold each to a comptime `int_const` in
`__module_init`. Expected runtime print: `40 20 300 3 0 -30 10 30 20 120 7 -31`.

## Source note (deviation from plan's verbatim source — see task report)
The plan's draft source (`@cInclude("<stdio.h>")` without `;`, `extern fn
printf(..., ...)` varargs, separate `const A`/`const B`) does not compile on
the current compiler: (1) the parser requires `;` after `@cInclude(...)`;
(2) varargs `...` in `extern fn` params is NOT parseable (`error[2000]`
`expected identifier but found token`); (3) `A`/`B` module consts referenced
ONLY from other const initializers never get C storage-global decls
(`zG_..._A` undeclared in `__module_init` → gcc error). The literal operands
are therefore inlined. This preserves the tested gap exactly (bare binary/
unary arithmetic that must fold) and additionally matches the plan's
post-fix expectation: `comptimeEvalEvaluate` handles `int_literal` operands
but not `ident_expr`, so the literal form is the one that turns GREEN after
the F1/F2 fixes.

## Upstream gap (Gap 1 — comptime evaluation only visits builtin_call)
`phase_ComptimeEvaluation` (main.zig:339-352) iterates every AST node but
only calls `comptimeEvalEvaluate` for `AstKind.builtin_call`. Bare binary /
unary arithmetic nodes (`add`, `sub`, `mul`, `div`, `mod_op`, `negate`,
`bit_and`, `bit_or`, `bit_xor`, `shl`, `shr`, `bit_not`) are never
evaluated, so `comptime_values` never receives their folded values →
`__module_init` emits runtime arithmetic instead of `int_const`.

## Measured result (pre-fix, /tmp/z1/zig1)
- dump rc=0, 1 `.c` emitted, gcc-clean (rc=0), links, runs — prints
  `40 20 300 3 0 -30 10 30 20 120 7 -31` (gcc folds the emitted runtime ops).
- Emission gap proven by `grep -c '[\*\/\%]'` in the emitted C = **11 > 0**:
  `__module_init` carries real operators, e.g. `zT_8 = zT_6 * zT_7;`,
  `zT_11 = zT_9 / zT_10;`, `zT_14 = zT_12 % zT_13;` (plus `+`, `-`, `&`,
  `|`, `^`, `<<`, `>>`, `~`) instead of `int_const` literals.

## Expected classification
- **Pre-fix: OK with emission-gap annotation** — gcc-clean, runtime output
  correct, but the GAP is visible in C89 inspection (runtime arithmetic
  emitted, not `int_const`). Counted OK per the
  `load_global_array_copy`/`comptime_neg_int` precedent of counting
  runtime/emission-gap repros as OK.
- **Post-fix (F2):** `__module_init` should contain `int_const` values
  (folded) — `grep -c '[\*\/\%]'` in the emitted C → 0.
