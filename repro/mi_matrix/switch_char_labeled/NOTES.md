# switch_char_labeled — FAIL (runtime gap, char_literal stmt-switch case labels dropped in labeled-break loop)  [I-task: char_literal switch repro battery A7, 2026-08-07]

## What it tests
A stmt-position `switch (c: u8)` inside a LABELED `game_loop: while (true)`
loop. `c` starts `'a'`; `'q'` prong does `break :game_loop`, `'a'` prong
increments `count`, else is a no-op. A `guard > 100` `break :game_loop` is
the iteration-bounded exit. Prints `run()`'s return. Targets the
stmt-switch case-collection gap at `sf/src/lower.zig:3920`.

## Rework rationale (iteration-bounded loop — NO pre-fix infinite hang)
A `while (true)` loop bounded only by the switch-driven `'q'` break would
hang pre-fix (the char prong is dead, so `c` never advances and `'q'` never
fires). The `guard > 100` break keeps the loop iteration-bounded: it always
terminates pre-fix (at guard=101), printing `0`, instead of hanging.

## The compiler gap
The stmt-switch case-collection loop in `sf/src/lower.zig:3907-3921` checks
`int_literal`/`enum_literal`/`error_literal`, then `else { continue; }` at
`:3920` — every `char_literal` (kind 13) case value hits the `else` and is
dropped. The emitted C switch has NO `case` labels, only a `default:`
target, so neither `'a'` (count increment) nor `'q'` (labeled break) ever
fires.

## Measured result (2026-08-07, /tmp, sf/build/out_release/zig1)
- dump rc=0, gcc rc=0, run rc=0 (within `timeout 5` — no hang).
- Emitted C has `switch (c) { default: goto z_bb_9; }` and NO `case `
  labels (pre-fix symptom).
- Runtime output: `0` (expected pre-fix: labeled break on 'q' never fires;
  guard-break at 100 terminates; count never increments → prints 0).
- Classification: **FAIL** (runtime gap; compiles and runs, wrong value).

## Oracle verification (zig0)
`sf/build/zig0` on a copy in /tmp rc=0 (oracle output `1`), emits `main.c`
with 2 `case` labels (`'q'`, `'a'` — the char cases ARE emitted) — valid
Z98, genuine compiler gap.

## Expected post-fix output
`1` (c='a' at iteration 0 increments count to 1; c advances past 'a'; the
'q' break fires at c='q' before guard-100 → count=1).

## Expected classification
FAIL (runtime gap) until `char_literal` case nodes are collected in the
stmt-switch case-collection loop at `lower.zig:3920`.
