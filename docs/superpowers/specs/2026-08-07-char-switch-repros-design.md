# char_literal Switch-Case Labels + opt_slice Null Payload — Design Spec

**Date:** 2026-08-07
**Status:** Draft
**Predecessor:** `2026-08-07-rogue-emission-defects-design.md` (complete at HEAD e220676c, READY TO MERGE)

## Goal

Create 15 defensive repros covering two out-of-scope follow-up defects documented
during the rogue_mud emission-defects plan closeout, with mandatory cross-module
variants. Repro-first, so a subsequent fix plan has gated evidence to work from.

## Background

The rogue_mud plan F5 closeout documented two latent/out-of-scope defects:

1. **char_literal switch `case` labels are dropped.** Both switch case-collection
   loops in the lowerer handle `int_literal`, `enum_literal`, `error_literal` only;
   `char_literal` (kind 13) falls through to `else { continue; }` → every char case
   is silently skipped → the emitted C has `switch(c) { default: ... }` with no
   `case` labels → char-prong bodies are unreachable at runtime. Gap sites:
   `sf/src/lower.zig:3183` (expr switch) and `:3920` (stmt switch). A dedicated
   audit (`.superpowers/sdd/I-char-literal-gaps-report.md`) confirmed char_literal is
   **only** broken for switch cases — if/for/while, var init, fn args, array index,
   binary ops, comptime, and C89 emission all handle it correctly.

2. **opt_slice_null_return — typeless null payload temp (latent).** `catch return
   null` in a function returning `?[]T` emits the null payload temp as `int`
   (`zT_3 = NULL; zT_4.has_value = 0;`) instead of the slice-struct type. Compiles
   with `-Wint-conversion` warnings only (OK by the gcc-exit-code gate); would FAIL
   under `-Werror`. Existing guard repro: `repro/mi_matrix/opt_slice_null_return/`.

## The 2 defects

| # | Defect | Root cause | Symptom |
|---|--------|-----------|---------|
| 1 | char_literal switch-case labels dropped | case-collection chains at `lower.zig:3183`/`:3920` have no `AstKind.char_literal` branch → `else { continue; }` drops the case | emitted `switch(c){default:...}`, char prongs unreachable |
| 2 | optional-of-slice null payload temp typed `int` | null-construction lower emits scalar `int` temp for the payload regardless of real type; valid for `?*T`, wrong for `?[]T` | gcc `-Wint-conversion` warning, type-incorrect C |

## Architecture

Two independent repro batteries, then (later) fix tasks. This plan creates **only
repros** — the fix is a follow-up plan after the repros gate the bug.

```
Battery A (char_literal switch, 12 repros)  ─┐
   ├ 4 same-module stmt-switch (gap :3920)   │
   ├ 1 expr-switch (gap :3183)               │
   ├ 4 compound patterns                     │
   └ 4 cross-module (both gaps)              ├─ gate on emitted C + runtime
Battery B (opt_slice null payload, 3 repros)─┘
   ├ 1 same-module (mirror of guard repro)
   ├ 1 cross-module
   └ 1 multi-path
```

## Repro conventions (all batteries)

- **Location:** `repro/mi_matrix/<name>/`. Same-module = `main.zig` only.
  Cross-module = `main.zig` + `lib.zig` (or named module file), imported via
  `const lib = @import("lib.zig");`.
- **Each repro compiles** via the QUICK_REF recipe: `zig1 --dump-c89` rc=0, gcc
  per-file `-c` rc=0, link rc=0, run rc=0.
- **Each repro prints a distinctive value** so runtime output is a single string
  check. `NOTES.md` documents: what it tests, the expected runtime output, the
  pre-fix emitted-C symptom (no `case` labels / `int` null-payload temp), and
  expected classification (FAIL for battery A until the lowerer gap is fixed; OK
  for battery B but type-incorrect/latent).
- **Corpus accounting:** battery A repros are FAIL until fixed (gcc-clean but
  runtime-wrong — they compile and run but print wrong output because char prongs
  are dead). Battery B repros are OK-by-gate (gcc warning only) but guarded
  latent, mirroring the existing `opt_slice_null_return` convention.

---

# Battery A: char_literal switch-case repros (12)

## A1-A4: Basic stmt-switch (gap `lower.zig:3920`)

- `switch_char_single` — `switch(c) { 'a' => print("A"), else => print("?") }`
- `switch_char_multi` — `'a','b' => r=1; 'c' => r=2; else => r=0` (multi-value
  prong + separate cases)
- `switch_char_nodefault` — `switch(c) { 'a' => r=1, 'b' => r=2 }` (no else;
  verify no fallthrough crash when c is unmatched)
- `switch_char_mixed_kinds` — one switch on `u8` with a char case in one prong
  (`'a' => r=1`) and an int case in a different prong (`98 => r=2`) — verifies
  char and int case values coexist across prongs without duplicate C labels
  (`'a'`==97 ≠ 98)

## A5: expr-switch (gap `lower.zig:3183`)

- `switch_char_expr` — `return switch(c) { 'a' => 1, 'b' => 2, else => 0 }`

## A6-A8: Compound patterns

- `switch_char_while` — char switch inside `while(true)`: `'q' => break, 'a' =>
  count += 1, else => {}`; loop runs fixed iterations, verify count
- `switch_char_labeled` — `game_loop: while(true) { switch(c) { 'q' => break
  :game_loop, else => {} } }` — labeled-break through switch
- `switch_char_nested` — `switch(outer) { 'a' => switch(inner) { 'x' => r=1, else
  => r=0 }, else => r=9 }`

## A9-A12: Cross-module (both gaps, 2-file modules)

- `switch_char_xmod` — `lib.zig` fn `classify(c: u8) u8` stmt-switches on char,
  returns result. `main.zig` calls with `'a'`, prints
- `switch_char_xmod_expr` — `lib.zig` fn `score(c: u8) i32` uses expr-switch
  (`return switch(c) { ... }`). `main.zig` calls, prints
- `switch_char_xmod_while` — `lib.zig` fn `run(c: u8) u8` has switch inside
  while (counts iterations until `'q'`). `main.zig` calls, prints count
- `switch_char_xmod_nodefault` — `lib.zig` fn with char switch, no default.
  `main.zig` calls with a valid char, verifies no fallthrough crash

## Pre-fix expected symptom (all A repros)

Emitted C: `switch (c) { default: goto Z; }` — no `case` labels. Repro compiles,
links, runs rc=0 but prints the WRONG output (char prongs dead → else/default
taken). Classification: **FAIL** (runtime gap).

## Post-fix expected C (for the future fix plan to target)

`case 'a': case 97: ... default: ...` — case labels present, char prongs reachable,
runtime output matches the expected string.

---

# Battery B: opt_slice null payload repros (3)

## B1: same-module

- `opt_slice_null` — mirrors existing guard `opt_slice_null_return` content:
  `fn findPath() ?[]Point { _ = fail() catch return null; return null; }`, `main`
  calls and verifies null.

## B2: cross-module

- `opt_slice_null_xmod` — `lib.zig` fn `findPath() ?[]Path` with `catch return
  null`. `main.zig` imports, calls, verifies null.

## B3: multi-path

- `opt_slice_null_multi` — one fn returning `?[]Point` with multiple `catch
  return null` on different error paths.

## Expected classification (all B repros)

**OK-by-gate** (gcc rc=0, `-Wint-conversion` warnings on the null-payload temp),
matching the existing guard. Latent/type-incorrect — documented, not counted as
FAIL. Would flip to FAIL under `-Werror` or a strictness fix.

---

## Gates (all repros)

- Build: zig0 → zig1 bootstrap in /tmp, 0 gcc errors (QUICK_REF recipe)
- Each repro: `--dump-c89` rc=0; gcc per-file `-c` rc=0; link rc=0; run rc=0
- Each repro's `NOTES.md` documents expected runtime output; the report verifies
  it matches
- Corpus manifest `EXPECTED_FAIL.md`: battery A repros ADDED as FAIL (expected),
  battery B repros ADDED as OK-by-gate (latent note) — totals updated
- No source changes to the compiler. Repro dirs stay untracked per existing
  convention (F1-F4 precedent)
- fastedit/edit only. Read region before each edit. Bottom-to-top. NO scope creep
- The plan is the ONLY authority

---

## Follow-ups (NOT this plan)

- **char_literal switch-case fix** after repros gate the bug: add
  `AstKind.char_literal` branch to both case-collection loops
  (`lower.zig:3183`/`:3920`), reading `store.int_values` like `int_literal`
  does. Verify all 12 battery-A repros flip FAIL→OK and print expected output.
- **opt_slice null payload temp typing fix** after repros gate the bug: emit the
  null payload temp at the optional's payload type, not `int`. Verify gcc
  warnings disappear for battery B.
- Whether battery-B fix requires a mud/gol/lisp/json re-baseline is assessed in
  the fix plan (emitFieldAssign-style blast radius).
