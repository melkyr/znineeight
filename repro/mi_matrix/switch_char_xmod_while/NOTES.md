# switch_char_xmod_while — FAIL (lowerer: char_literal switch case labels dropped)  [Task 3 battery A11, 2026-08-07]

## What it tests
Cross-module stmt-style `char_literal` switch INSIDE a `while` loop
(`lower.zig:3920` site). `lib.zig` `run()` loops 3 times (`i < 3`), each
iteration switching on a rolling `c` (`'a'` → `'b'` → `'c'`), incrementing
`count` only on the `'a'` arm. The loop condition does NOT depend on the
switch result — deliberately bounded so the pre-fix program terminates
(a `while` conditioned on a dropped-case result would hang pre-fix).

## The compiler gap
`lower.zig` drops `char_literal` switch `case` labels in BOTH case-collection
loops:
- `lower.zig:3183` — expr-switch case collection.
- `lower.zig:3920` — stmt-switch case collection (`else { continue; }` for
  `char_literal`). This is the site exercised by the in-loop stmt switch.

The `switch` is emitted with only `default:` — no `case` labels — so the
`'a'` arm never fires and `count` stays `0`.

## Measured result (2026-08-07, sf/build/out_release/zig1)
- dump rc=0; 2 `.c` emitted (`lib_*.c`, `main_*.c`).
- gcc per-file `-c` rc=0 (both modules); link rc=0.
- `timeout 5 ./prog` rc=0 (no hang — loop bounded by `i < 3`), output `0`.
- Emitted C: `grep "case " *.c` = 0 matches in both modules; the lib `.c`
  contains `switch (c) { default: goto ... }` with no `case` labels.
- Classification: **FAIL** (runtime gap — stmt-switch in a loop emits switch without cases), NOT counted as a corpus FAIL (OK-by-compile / runtime-gap-tracked).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/t3r/switch_char_xmod_while repro/mi_matrix/switch_char_xmod_while/main.zig`
→ rc=0; oracle `lib.c` has 1 `case` label; running the oracle output yields
`1` — valid Z98, genuine compiler gap.

## Expected post-fix output
`1` (only `c='a'` at iteration 0 fires the `'a'` arm; `'b'`/`'c'` hit `else`).

## Expected classification
FAIL until `lower.zig:3920` emits `case` labels for `char_literal` stmt-switch
prongs. Runtime symptom disappears once labels are restored.
