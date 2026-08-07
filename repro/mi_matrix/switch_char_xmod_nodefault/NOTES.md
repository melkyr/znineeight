# switch_char_xmod_nodefault — FAIL (lowerer: char_literal switch case labels dropped)  [Task 3 battery A12, 2026-08-07]

## What it tests
Cross-module stmt-style `char_literal` switch WITHOUT an `else` prong.
`lib.zig` `classify()` has `switch (c) { 'a', 'b' }` (no else) over a
`var r: u8 = 9` initializer; `main.zig` calls it 2 times (`'a'`, `'q'`).
Exercises the no-default path at the `lower.zig:3920` stmt-switch site: when
all case labels are dropped, every input falls through and `r` keeps its
initializer `9`.

## The compiler gap
`lower.zig` drops `char_literal` switch `case` labels in BOTH case-collection
loops:
- `lower.zig:3183` — expr-switch case collection (`else { continue; }` for
  `char_literal`).
- `lower.zig:3920` — stmt-switch case collection (`else { continue; }` for
  `char_literal`).

The `switch` is emitted with only `default:` — no `case` labels — and with
no user `else`, the pre-initialized `r` (`9`) is returned for every input.

## Measured result (2026-08-07, sf/build/out_release/zig1)
- dump rc=0; 2 `.c` emitted (`lib_*.c`, `main_*.c`).
- gcc per-file `-c` rc=0 (both modules); link rc=0.
- `timeout 5 ./prog` rc=0 (no hang), output `99`.
- Emitted C: `grep "case " *.c` = 0 matches in both modules; the lib `.c`
  contains `switch (c) { default: goto ... }` with no `case` labels.
- Classification: **FAIL** (runtime gap — switch without default emits switch without cases).

## Oracle verification (zig0)
`./sf/build/zig0 -o /tmp/t3r/switch_char_xmod_nodefault repro/mi_matrix/switch_char_xmod_nodefault/main.zig`
→ rc=0; oracle `lib.c` has 2 `case` labels; running the oracle output yields
`19` — valid Z98, genuine compiler gap.

## Expected post-fix output
`19` (`classify('a')=1`; `classify('q')` falls through the no-else switch,
returning the initializer `9`).

## Expected classification
FAIL until `lower.zig:3920` emits `case` labels for `char_literal` stmt-switch
prongs (incl. the no-default form). Runtime symptom disappears once labels are
restored.
