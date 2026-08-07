# switch_char_single — FAIL (runtime gap, char_literal stmt-switch case labels dropped)  [I-task: char_literal switch repro battery A1-A4, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` with two `char_literal` prongs
(`'a' => r = 1`, `'b' => r = 2`) and an `else` default. `classify('a')`,
`classify('b')`, `classify('z')` are printed. This is the minimal repro:
single-value `char_literal` case labels in a switch that otherwise
lower/emit/run cleanly.

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — `char_literal` (kind 13) hits the `else` and is dropped from the
case table. The emitted C switch therefore has NO `case` labels, only a
`default:` target, so every input takes the else body. (Expr-switch twin:
`lower.zig:3183`.)

## Measured result (2026-08-07, /tmp/t1r, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0.
- Emitted C has `switch (c)` and NO `case ` labels (`default: goto z_bb_3;`
  only) — pre-fix symptom.
- Runtime output: `000` (expected pre-fix: all char cases dropped → else
  always taken).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 2 `case` labels
(the char cases ARE emitted) — valid Z98, genuine compiler gap.

## Expected post-fix output
`120` (post-fix: `'a'`→1, `'b'`→2, `'z'`→else→0).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
