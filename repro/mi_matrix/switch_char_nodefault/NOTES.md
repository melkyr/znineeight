# switch_char_nodefault — FAIL (runtime gap, char_literal stmt-switch case labels dropped)  [I-task: char_literal switch repro battery A1-A4, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` with two `char_literal` prongs
(`'a' => r = 1`, `'b' => r = 2`) and NO `else` prong. `r` is initialized to
`9`. `classify('a')`, `classify('q')` are printed. Tests the no-default
shape: with all char cases dropped, an unmatched value must fall through
cleanly (r stays 9), not crash or return garbage.

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — `char_literal` (kind 13) hits the `else` and is dropped from the
case table. The emitted C switch has NO `case` labels, so no prong body is
ever taken; `r` retains its init value 9. (Expr-switch twin: `lower.zig:3183`.)

## Measured result (2026-08-07, /tmp/t1r, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0.
- Emitted C has `switch (c)` and NO `case ` labels (default target only) —
  pre-fix symptom.
- Runtime output: `99` (expected pre-fix: no else; char cases dropped → r
  stays 9; no crash on unmatched `'q'`).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 2 `case` labels
(`'a'`, `'b'` — the char cases ARE emitted) — valid Z98, genuine compiler gap.

## Expected post-fix output
`19` (post-fix: `'a'`→1, `'q'`→unmatched→9).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
