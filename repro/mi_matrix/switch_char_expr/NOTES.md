# switch_char_expr — FAIL (runtime gap, char_literal EXPR-switch case labels dropped)  [I-task: char_literal switch repro battery A5, 2026-08-07]

## What it tests
An EXPR-position `return switch (c: u8) { ... }` — the value is returned
directly from a `score(c)` fn. `'a'`→1, `'b'`→2, `else`→0; calls
`score('a')`, `score('b')`, `score('q')` are printed. Targets the
expr-switch case-collection gap at `sf/src/lower.zig:3183` (the twin of the
stmt-switch gap at `:3920`).

## The compiler gap
The expr-switch case-collection loop in `sf/src/lower.zig:3170-3184` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3183` — every `char_literal` (kind 13) case value hits the `else` and is
dropped. The emitted C switch has NO `case` labels, only a `default:`
target, so every input takes the else body.

## Measured result (2026-08-07, /tmp, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0 (within `timeout 5` — no hang).
- Emitted C has `switch (c) { default: goto z_bb_3; }` and NO `case `
  labels (pre-fix symptom).
- Runtime output: `000` (expected pre-fix: both char prongs dropped → all
  inputs take else → 0,0,0).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 2 `case` labels
(`'a'`, `'b'` — the char cases ARE emitted) — valid Z98, genuine compiler gap.

## Expected post-fix output
`120` (`'a'`→1, `'b'`→2, `'q'`→else→0).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
expr-switch case-collection loop at `lower.zig:3183`.
