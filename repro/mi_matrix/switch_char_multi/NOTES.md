# switch_char_multi — FAIL (runtime gap, char_literal stmt-switch case labels dropped)  [I-task: char_literal switch repro battery A1-A4, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` with a MULTI-VALUE `char_literal` prong
(`'a', 'b' => r = 1`), a single-value prong (`'c' => r = 2`), and an `else`
default. `classify('a')`, `classify('b')`, `classify('c')`, `classify('q')`
are printed. Tests that a multi-value `char_literal` prong — where the
case-collection loop would need to handle a comma-separated list of case
values — is dropped too.

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — every `char_literal` (kind 13) case value hits the `else` and is
dropped, including all values of the multi-value prong `'a', 'b'`. The
emitted C switch has NO `case` labels, only a `default:` target, so every
input takes the else body. (Expr-switch twin: `lower.zig:3183`.)

## Measured result (2026-08-07, /tmp/t1r, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0.
- Emitted C has `switch (c)` and NO `case ` labels (`default: goto z_bb_3;`
  only) — pre-fix symptom.
- Runtime output: `0000` (expected pre-fix: `'a','b'` multi-prong AND `'c'`
  all dropped → else always taken).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value), NOT counted as a corpus FAIL (OK-by-compile / runtime-gap-tracked).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 3 `case` labels
(`'a'`, `'b'`, `'c'` — the char cases ARE emitted) — valid Z98, genuine
compiler gap.

## Expected post-fix output
`1120` (post-fix: `'a'`→1, `'b'`→1, `'c'`→2, `'q'`→else→0).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
