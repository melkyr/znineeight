# switch_char_mixed_kinds — FAIL (runtime gap, char_literal stmt-switch case labels dropped)  [I-task: char_literal switch repro battery A1-A4, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` with MIXED case kinds: a `char_literal`
prong (`'a' => r = 1`), an `int_literal` prong (`98 => r = 2`), and an
`else` default. `classify('a')`, `classify('b')`, `classify('q')` are
printed. This is the KEY discriminating repro: within one switch, the INT
case works while the CHAR case is dropped — proving the defect is
char-specific. (`'a'`==97 ≠ 98, so no duplicate C labels.)

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — the `int_literal` case `98` IS collected and emitted as
`case 98:`, but the `char_literal` case `'a'` (kind 13) hits the `else` and
is dropped. The emitted C switch has only the `case 98` label. (Expr-switch
twin: `lower.zig:3183`.)

## Measured result (2026-08-07, /tmp/t1r, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0.
- Emitted C has `switch (c)`, exactly 1 `case ` label: `case 98: goto
  z_bb_2;` (the INT case), plus `default: goto z_bb_3;` — the char case
  `'a'` is absent. Pre-fix symptom.
- Runtime output: `020` (expected pre-fix, VERIFIED: INT case `98` works —
  `'b'`→2; CHAR case `'a'` dropped — `'a'`→else→0; `'q'`→0).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value), NOT counted as a corpus FAIL (OK-by-compile / runtime-gap-tracked).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 2 `case` labels
(`'a'`=97 and `98` — both case kinds ARE emitted) — valid Z98, genuine
compiler gap.

## Expected post-fix output
`120` (post-fix: `'a'`→1, `'b'`(=98)→2, `'q'`→else→0).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
