# switch_char_xmod — FAIL (lowerer: char_literal switch case labels dropped)  [Task 3 battery A9, 2026-08-07]

## What it tests
Cross-module stmt-style `char_literal` switch. `lib.zig` `classify()` has a
`switch (c)` over `'a'`/`'b'`/`else`; `main.zig` calls it 3 times
(`'a'`, `'b'`, `'z'`) via `@import`. The switch sits in a NON-root module —
proves the case-collection bug manifests identically across a module boundary.

## The compiler gap
`lower.zig` drops `char_literal` switch `case` labels in BOTH case-collection
loops:
- `lower.zig:3183` — expr-switch case collection (`else { continue; }` for
  `char_literal`).
- `lower.zig:3920` — stmt-switch case collection (`else { continue; }` for
  `char_literal`).

The `switch` is still emitted, but with NO `case` labels — only `default:`
(taking the `else`/fall-through path) plus the per-case bodies that are now
unreachable. So `classify('a')` returns `0` instead of `1`.

## Measured result (2026-08-07, sf/build/out_release/zig1)
- dump rc=0; 2 `.c` emitted (`lib_*.c`, `main_*.c`).
- gcc per-file `-c` rc=0 (both modules); link rc=0.
- `timeout 5 ./prog` rc=0 (no hang), output `000`.
- Emitted C: `grep "case " *.c` = 0 matches in both modules; the lib `.c`
  contains `switch (c) { default: goto ... }` with no `case` labels.
- Classification: **FAIL** (runtime gap — lowerer emits switch without cases), NOT counted as a corpus FAIL (OK-by-compile / runtime-gap-tracked).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/t3r/switch_char_xmod repro/mi_matrix/switch_char_xmod/main.zig`
→ rc=0; oracle `lib.c` has 2 `case` labels; running the oracle output yields
`120` — valid Z98, genuine compiler gap.

## Expected post-fix output
`120` (case labels restored: `classify('a')=1`, `classify('b')=2`, `classify('z')=0`).

## Expected classification
FAIL until `lower.zig:3183`/`:3920` emit `case` labels for `char_literal`
switch prongs. Runtime symptom disappears once labels are restored.
