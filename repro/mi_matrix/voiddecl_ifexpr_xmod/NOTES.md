# voiddecl_ifexpr_xmod — RED trigger: untyped module consts in value-position if

**Status: DONE** (2026-08-19, amended brief). Reproduces `error[3000] cannot declare
variable of type void` for the value-position `if (bool) A else B` shape at
`lower.zig:4410` (`var cmp_op = if (pattern.kind == AstKind.range_inclusive)
BIN_LE else BIN_LT;`). Trigger = **untyped module-level consts** referenced in an
inferred var-init; literals do NOT trigger (see the ctl fixture).

## Purpose
Task R1 (amended) of the voiddecl-family plan. Minimal RED repro + type-kind matrix
for the value-position if-expr void collapse. Two fixtures:
- `voiddecl_ifexpr_xmod/` — module-const RED trigger (this dir)
- `voiddecl_ifexpr_ctl_xmod/` — literal GREEN control (negative)

## Fixture (main.zig, committed, md5 `e00ef06e5ca559fc3b523c1fe0a33413`)
```zig
const std = @import("std");
const BIN_LT = @intCast(u8, 12);
const BIN_LE = @intCast(u8, 13);
pub fn main() void {
    var kind: u32 = 0;
    var cmp_op = if (kind == 1) BIN_LE else BIN_LT;
    std.io.printInt(cmp_op);
}
```
NOTE on form: brief Step 1 wrote the consts with `: u8` annotations. Verified BOTH
forms (below); the **annotated** form is GREEN, the **truly-untyped** form is RED.
Committed fixture uses the untyped form — which also matches real `lower.zig:50-51`
(`const BIN_LT = @intCast(u8, 12);`, no annotation). `@enumToInt`/`@intCast` only
in probes, not in the committed fixture (Z98 dialect: no anytype, no @Type).

## RED baseline (Step 2)
Recipe (from fixture dir):
`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
```
rc = 2
stderr:
main.zig:6:4: error[3000]: cannot declare variable of type void
    var kind: u32 = 0;
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```
- stdout (the `.c`) = 0 bytes — compile aborts, nothing emitted.
- Diagnostic points at `var kind: u32 = 0;` (line 6) with caret 52 wide; the actual
  poisoned statement is `var cmp_op = if (kind == 1) BIN_LE else BIN_LT;` (line 7).
  Same off-by-one diagnostic display quirk seen on self-compile (`lower.zig:4410`
  showed line 4409) — reported in the prior BLOCKED report.

## Form verification (which const form reproduces RED)
| form | shape | dump rc | verdict |
|------|-------|---------|---------|
| annotated const | `const BIN_LT: u8 = @intCast(u8, 12);` + `: u8` on both | 0 | GREEN |
| **untyped const** | `const BIN_LT = @intCast(u8, 12);` (committed) | 2 | **RED** |

## GREEN control (Step 3, /tmp only)
`var cmp_op: u32 = 13;` (rest of program identical) → dump rc=0; gcc rc=0; run
prints `13`, run rc=0.

## Type-kind matrix (Step 6) — probes in /tmp, bare @import("std") + printInt
| # | variant | shape | dump rc | .c bytes | verdict |
|---|---------|-------|---------|----------|---------|
| 1 | module-const both branches | `if (kind==1) BIN_LE else BIN_LT` (untyped) | 2 | 0 | RED (trigger) |
| 2 | cond bool | `if (kind == 1)` | 2 | 0 | RED (this IS the trigger cond) |
| 3 | cond optional | `if (o) B else A`, `o: ?u32` | 2 | 0 | RED |
| 4 | single module-const + literal | `if (kind==1) A else 12` | 0 | 10927 | GREEN |
| 5 | bare module-const binary op | `var x = A + B;` | 2 | 0 | RED |
| 6 | bare module-const alone | `var x = A;` | 2 | 0 | RED |
| 7 | branches enum consts | `E.b` / `E.a` | 0 | 10823 | GREEN (prints 0) |
| 8 | branches bool consts | `true` / `false` | 0 | 10867 | GREEN |
| 9 | branches struct values | `S{.v=13}` / `S{.v=12}` | 0 | 10969 | GREEN |
| 10 | annotated const both branches | `const A: u8 = ...;` | 0 | 11082 | GREEN (prints 12) |
| 11 | annotated var | `var x: u32 = A;` | 0 | 10449 | GREEN — warning only |
| 12 | cross-module untyped const | `mod.B` / `mod.A` | 2 | 0 | RED |

## Blast-radius lead (feeds I-IFEXPR)
RED requires an **untyped module-level `const`** (`const X = <expr>;`, no type
annotation) referenced in an **inferred var-init** expression:
- bare (`var x = A;`), in a binary op (`var x = A + B;`), or as BOTH if-branches
  (`if (c) A else B`) → RED.
- Single module-const branch is GREEN when the OTHER branch is a literal
  (variants 4, p_p/p_f/p_g in the prior probe set).
- Annotating the const (`: u8`, variant 10) or the var (`: u32`, variant 11) →
  GREEN. Variant 11 emits `warning[3000]: type mismatch in variable declaration —
  initialization type may not be compatible with declared type` (note: source void,
  target u32) — the void collapse is still computed but downgraded by the explicit
  type.
- Cross-module untyped consts (`mod.A`/`mod.B`) also RED (variant 12).
- Enum/bool/struct branch VALUES are fine (variants 7-9) — the poison is the
  module-const reference, not the branch type per se.
- Local consts, module var (`var A: u32`), const-in-cond, const-as-fn-arg: all
  GREEN (prior 22-probe table, this fixture's NOTES predecessor).

Not the if-expr itself, not the bool cond, not u8 branches: the module-const
reference is the poison; the if-expr is the carrier. I-IFEXPR should investigate
const resolution (`const X = expr` untyped → void in value position).

## Post-fix expectation
`var cmp_op = if (kind == 1) BIN_LE else BIN_LT;` (this fixture) flips RED→GREEN:
dump rc=0, gcc rc=0, run prints `12`, run rc=0 — matching the literal control.
Same for binary-op and cross-module forms (variants 5, 6, 12).

## Cross-ref
Literal GREEN control: `repro/mi_matrix/voiddecl_ifexpr_ctl_xmod/`.
Prior BLOCKED attempt (same literal form): `.superpowers/sdd/task-R1-voiddecl-report.md`.
