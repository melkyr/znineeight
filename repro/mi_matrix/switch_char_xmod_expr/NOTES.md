# switch_char_xmod_expr — FAIL (lowerer: char_literal switch case labels dropped)  [Task 3 battery A10, 2026-08-07]

## What it tests
Cross-module EXPR-style `char_literal` switch — the OTHER defect site.
`lib.zig` `score()` is `return switch (c) { 'a', 'b', else ... };`
`main.zig` calls it 3 times (`'a'`, `'b'`, `'q'`) via `@import`. Exercises
the expr-switch case collection at `lower.zig:3183` across a module boundary.

## The compiler gap
`lower.zig` drops `char_literal` switch `case` labels in BOTH case-collection
loops:
- `lower.zig:3183` — expr-switch case collection (`else { continue; }` for
  `char_literal`). This is the site exercised by an expr switch.
- `lower.zig:3920` — stmt-switch case collection (`else { continue; }` for
  `char_literal`).

The `switch` is emitted with only `default:` — no `case` labels — so the
expr-switch always evaluates the `else` arm, returning `0` for every input.

## Measured result (2026-08-07, sf/build/out_release/zig1)
- dump rc=0; 2 `.c` emitted (`lib_*.c`, `main_*.c`).
- gcc per-file `-c` rc=0 (both modules); link rc=0.
- `timeout 5 ./prog` rc=0 (no hang), output `000`.
- Emitted C: `grep "case " *.c` = 0 matches in both modules; the lib `.c`
  contains `switch (c) { default: goto ... }` with no `case` labels.
- Classification: **FAIL** (runtime gap — expr-switch emits switch without cases).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/t3r/switch_char_xmod_expr repro/mi_matrix/switch_char_xmod_expr/main.zig`
→ rc=0; oracle `lib.c` has 2 `case` labels; running the oracle output yields
`120` — valid Z98, genuine compiler gap.

## Expected post-fix output
`120` (case labels restored: `score('a')=1`, `score('b')=2`, `score('q')=0`).

## Expected classification
FAIL until `lower.zig:3183` emits `case` labels for `char_literal` expr-switch
prongs. Runtime symptom disappears once labels are restored.
