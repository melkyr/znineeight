# switch_char_while — FAIL (runtime gap, char_literal stmt-switch case labels dropped in while loop)  [I-task: char_literal switch repro battery A6, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` inside an ITERATION-bounded `while`
loop (`i < 3`). `c` starts `'a'` and advances `'a'→'b'→'c'` across the 3
iterations; the `'a'` prong increments `count`, else is a no-op. Prints
`run()`'s return. Targets the stmt-switch case-collection gap at
`sf/src/lower.zig:3920`.

## Rework rationale (iteration-bounded loop — NO pre-fix infinite hang)
The original draft looped `while (c == 'a')` (count-dependent condition).
Pre-fix the char prong is dead, so `c` never advances, the condition stays
true forever, and the binary would hang. The repro was reworked so the loop
condition (`i < 3`) does NOT depend on the switch result: it terminates
regardless of the defect, printing `0` pre-fix instead of hanging.

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — every `char_literal` (kind 13) case value hits the `else` and is
dropped. The emitted C switch has NO `case` labels, only a `default:`
target, so the `'a'` prong never fires and `count` stays 0.

## Measured result (2026-08-07, /tmp, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0 (within `timeout 5` — no hang).
- Emitted C has `switch (c) { default: goto z_bb_6; }` and NO `case `
  labels (pre-fix symptom).
- Runtime output: `0` (expected pre-fix: char case dropped → count stays 0
  → prints 0).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0 (oracle output `1`), emits `main.c`
with 1 `case` label (`'a'` — the char case IS emitted) — valid Z98, genuine
compiler gap.

## Expected post-fix output
`1` (only `c='a'` at iteration 0 increments count → prints 1).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
