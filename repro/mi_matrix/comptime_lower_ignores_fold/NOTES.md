# comptime_lower_ignores_fold — OK with emission-gap annotation  [comptime arithmetic folding plan, Task P0, 2026-08-06]

## What it tests
Identical source to `comptime_binop_not_folded` (12 bare binary/unary
const-fold operations at module scope). Same expected runtime print:
`40 20 300 3 0 -30 10 30 20 120 7 -31`. This repro isolates Gap 2: even if
Gap 1 were fixed and `comptime_values` were populated for binary/unary
nodes, the LOWERER would still ignore the fold.

## Source note (deviation from plan's verbatim source — see task report)
Same corrections as `comptime_binop_not_folded`: `;` after `@cInclude`,
fixed-arity `printf` (varargs `...` unparseable), literal operands inlined
(`const A`/`const B` referenced only from const inits never get C storage
globals → gcc `undeclared` error). See that NOTES.md for the full rationale.

## Upstream gap (Gap 2 — lowerer binary/unary handlers never consult comptime_values)
The lowerer's binary handlers (`lower.zig:1218-1306` — add/sub/mul/div/
mod_op/bit_and/bit_or/bit_xor/shl/shr) and unary handlers (`lower.zig:
1426-1439` — negate/bool_not/bit_not) emit `BIN_*`/`UN_*` LIR
unconditionally — they lower both operands and emit the operator without
any `comptime_values` lookup. Contrast the `builtin_call` handler
(`lower.zig:2456`) which DOES consult `comptime_values` and emits an
`int_const` when a folded value is present.

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
  `load_global_array_copy`/`comptime_neg_int` precedent.
- **Post-fix (F2):** binary/unary handlers consult `comptime_values`
  (like `builtin_call` at `lower.zig:2456`) and emit `int_const` —
  `grep -c '[\*\/\%]'` in the emitted C → 0.
