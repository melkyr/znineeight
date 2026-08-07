# switch_char_nested — FAIL (runtime gap, char_literal stmt-switch case labels dropped, nested switches)  [I-task: char_literal switch repro battery A8, 2026-08-07]

## What it tests
NESTED stmt-position switches: `switch (outer)` whose `'a'` prong body is
itself a `switch (inner)` with an `'x'` prong + `else`. Calls
`nested('a','x')`, `nested('a','y')`, `nested('z','x')`. Targets the
stmt-switch case-collection gap at `sf/src/lower.zig:3920` with a compound
(block-body, nested) pattern.

## The compiler gap
Both stmt-switch case-collection loops (inner and outer) hit
`else { continue; }` at `sf/src/lower.zig:3920` for every `char_literal`
(kind 13) case value. The emitted C outer switch has NO `case` labels, only
a `default:` target, so `nested('a', ...)` always takes the outer else
(`r = 9`) and the inner switch is never reached.

## Measured result (2026-08-07, /tmp, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0 (within `timeout 5` — no hang).
- Emitted C has `switch (outer) { default: goto z_bb_2; }` AND
  `switch (inner) { default: goto z_bb_6; }`, NO `case ` labels anywhere
  (pre-fix symptom).
- Runtime output: `999` (expected pre-fix: outer switch 'a' case dropped →
  else r=9; inner never reached).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0, emits `main.c` with 2 `case`
labels (`'a'` in the outer switch, `'x'` in the inner — the char cases ARE
emitted) — valid Z98, genuine compiler gap.

## Expected post-fix output
`109` (`nested('a','x')`→1, `nested('a','y')`→inner else→0,
`nested('z','x')`→outer else→9).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
