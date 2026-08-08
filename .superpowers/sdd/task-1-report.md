# Task 1 Report — Battery A1-A4: Basic stmt-switch char_literal repros

**Status:** DONE
**Commit:** `0dc4f594` — repro: char_literal stmt-switch case labels dropped (single/multi/nodefault/mixed)
**Date:** 2026-08-07
**Branch:** `zig1_start`

## What I implemented

Created 4 repro dirs under `repro/mi_matrix/`, each with `main.zig` (source
verbatim from the task brief — no changes) + `NOTES.md`:

- `switch_char_single` — two single-value char prongs + else. Expect `000` pre-fix / `120` post-fix.
- `switch_char_multi` — multi-value prong `'a','b'` + `'c'` + else. Expect `0000` pre-fix / `1120` post-fix.
- `switch_char_nodefault` — two char prongs, NO else, r init 9. Expect `99` pre-fix / `19` post-fix.
- `switch_char_mixed_kinds` — char prong `'a'` + INT prong `98` + else. Expect `020` pre-fix / `120` post-fix. Key discriminator: proves the bug is char-specific (int case works, char case drops).

All `NOTES.md` follow the `repro/mi_matrix/xmod_pub_const_global/NOTES.md`
format: what it tests, defect site (`lower.zig:3920` stmt-switch
`else { continue; }` drops char_literal), pre-fix emitted-C symptom, pre-fix
runtime output, expected post-fix output, oracle verification, classification
(FAIL — runtime gap).

## Defect site (verified against source)

`sf/src/lower.zig` stmt-switch case-collection loop `:3907-3921`: checks
`int_literal` / `enum_literal` / `error_literal`, then `else { continue; }`
at `:3920` — `char_literal` (kind 13) hits the `else` and is dropped.
Expr-switch twin at `:3183`. Both confirmed by direct read.

## Gate evidence

Compiled + run with the QUICK_REF recipe (zig1 = `sf/build/out_release/zig1`,
gcc links `zig_runtime.c` + `zig_pal.c` with `-I sf/src/include`; work dir
`/tmp/t1r`).

| repro | dump rc | gcc rc | run rc | runtime output | `case ` count in emitted C | `switch (` count | zig0 oracle rc |
|---|---|---|---|---|---|---|---|
| switch_char_single | 0 | 0 | 0 | `000` | 0 | 1 | 0 |
| switch_char_multi | 0 | 0 | 0 | `0000` | 0 | 1 | 0 |
| switch_char_nodefault | 0 | 0 | 0 | `99` | 0 | 1 | 0 |
| switch_char_mixed_kinds | 0 | 0 | 0 | `020` | **1** (`case 98:`) | 1 | 0 |

Emitted-C structure per repro:
- single/multi/nodefault: `switch (c) { default: goto z_bb_3; }` — NO case labels (pre-fix symptom).
- mixed_kinds: `switch (c) { case 98: goto z_bb_2; default: goto z_bb_3; }` — the INT case `98` IS emitted (it works); the char case `'a'` is absent. This matches the brief's note "the INT case 98 DOES work" — so the strict "0 case labels" assertion does NOT hold for mixed_kinds by design; the discriminating symptom is that the char case is dropped while the int case survives. Runtime `020` confirms.

Oracle (zig0) — copies in /tmp (zig0 writes output alongside source, ignores `-o`): all 4 rc=0, and each oracle `main.c` contains the char `case` labels that zig1 drops (2/3/2/2 respectively), confirming valid Z98 + genuine compiler gap.

## Files changed

- `repro/mi_matrix/switch_char_single/main.zig`, `.../NOTES.md` (new)
- `repro/mi_matrix/switch_char_multi/main.zig`, `.../NOTES.md` (new)
- `repro/mi_matrix/switch_char_nodefault/main.zig`, `.../NOTES.md` (new)
- `repro/mi_matrix/switch_char_mixed_kinds/main.zig`, `.../NOTES.md` (new)

No compiler source changes (repros-only plan). 8 files, 203 insertions, commit `0dc4f594`.

## Self-review

- Source in all 4 `main.zig` is byte-verbatim from the task brief.
- All runtime outputs match the brief's expected pre-fix table exactly: `000`, `0000`, `99`, `020`.
- `NOTES.md` files reference the correct defect site (`lower.zig:3920`), verified against current source (line numbers still valid).
- Only the 4 target dirs were staged/committed (5 other untracked dirs are prior-task artifacts and were left alone).

## Concerns

1. **mixed_kinds `case ` count is 1, not 0.** The brief's Step 5 blanket assertion "emitted C has NO case labels" does not strictly apply to mixed_kinds — the INT case `98` is correctly emitted. The pre-fix symptom there is that the CHAR case is dropped while the INT case survives (and runtime `020` confirms). I documented this nuance in `NOTES.md`. Not a defect in the repro — expected behavior per the brief's own "VERIFIED" note.
2. **nodefault emits a `default:` target** even though the source has no else prong — a synthesized default with no prong body (r stays 9). Harmless and expected; the no-else fall-through is what the repro gates (no crash, r=9).
