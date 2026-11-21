# voiddecl_u64cast_xmod — RED trigger: untyped module-var field ref through u64 `&` + @intCast narrowing

**Status: DONE** (2026-08-19). Reproduces `error[3000] cannot declare variable of
type void` for the shape at `symbol_registrator.zig:357` — `var name_id: u32 =
@intCast(u32, node.payload & @intCast(u64, 0xFFFFFFFF));` (live :356). The poisoned
statement in this fixture is the **inferred** `var n = node.payload &
@intCast(u64, 0xFFFFFFFF);` whose value-type must be inferred from an **untyped
module-level var** (`var node = Node{...}`, no annotation) through a field access.
R1/R2 lesson holds again: the brief's literal/local fixture is GREEN; the real
trigger is the untyped module-level reference in value position, carried here by the
u64 `&` + `@intCast(u64, ...)` shape.

## Purpose
Task R3 of the voiddecl-family plan. Minimal RED repro + type-kind matrix for the
value-position u64 bitwise-and + @intCast narrowing void collapse. Self-contained
(single main.zig — the commit rule allows only main.zig + NOTES.md in this dir).

## Fixture (main.zig, committed, md5 `7eefe34e3a62c2520ee1174743b79915`)
```zig
const std = @import("std");
const Node = struct { payload: u64 };
var node = Node{ .payload = 0xFFFFFFFF00000000 };
pub fn main() void {
    var n = node.payload & @intCast(u64, 0xFFFFFFFF);
    std.io.printInt(@intCast(u32, n));
}
```
`var node = Node{ .payload = ... }` is a **truly-untyped module-level var** whose
`payload` field is u64 — the poison. `node.payload & @intCast(u64, 0xFFFFFFFF)` in
an **inferred** var-init (`var n`, no `: u64`) is the carrier, matching
symbol_registrator.zig:357's `node.payload & @intCast(u64, 0xFFFFFFFF)`. Z98 dialect
constraints respected (no anytype, no @Type).

## RED baseline (brief Step 2)
Recipe (from fixture dir):
`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
```
rc = 2
stderr:
main.zig:5:4: error[3000]: cannot declare variable of type void
pub fn main() void {
    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
```
- stdout (the `.c`) = 0 bytes — compile aborts, nothing emitted.
- Diagnostic caret sits on line 4's text (`pub fn main() void {`) while reported at
  5:4; actual poisoned statement is line 5 (`var n = node.payload & @intCast(u64,
  0xFFFFFFFF);`). Same off-by-one caret/line display quirk as R1/R2 (the span's own
  line is reported; the caret prints the line above — diagnostics.zig:419 + :455).

## Escalation table (brief Step 1 ladder + extras, all probed in /tmp)
| # | form | shape | dump rc | verdict |
|---|------|-------|---------|---------|
| 1 | **brief literal, local var** | `var p: u64 = 0xFFFFFFFF00000000; var n: u32 = @intCast(u32, p & @intCast(u64, 0xFFFFFFFF));` | 0 | GREEN (prints 0) |
| 2 | module-var typed + annotated target | `var p: u64 = ...; var n: u32 = @intCast(u32, p & ...)` | 0 | GREEN |
| 3 | module-const typed + annotated target | `const P: u64 = ...; var n: u32 = @intCast(u32, P & ...)` | 0 | GREEN |
| 4 | module-const untyped + annotated target | `const P = @intCast(u64, ...); var n: u32 = @intCast(u32, P & ...)` | 0 | GREEN |
| 5 | module-var typed struct + field access + annotated | `var node: Node = ...; var name_id: u32 = @intCast(u32, node.payload & ...)` | 0 | GREEN |
| 6 | local struct + field access + annotated | `var node: Node = ...; var n: u32 = @intCast(u32, node.payload & ...)` | 0 | GREEN |
| 7 | module-var untyped + annotated target | `var p = 0xFFFFFFFF00000000; var n: u32 = @intCast(u32, p & ...)` | 0 | GREEN |
| 8 | **module-var untyped + INFERRED target (module-scalar)** | `var p = 0xFFFFFFFF00000000; var n = p & @intCast(u64, 0xFFFFFFFF);` | 2 | RED |
| 9 | module-const untyped + INFERRED target | `const P = @intCast(u64, ...); var n = P & @intCast(u64, 0xFFFFFFFF);` | 2 | RED |
| 10 | **module-var untyped struct + INFERRED target + field access (COMMITTED)** | `var node = Node{...}; var n = node.payload & @intCast(u64, 0xFFFFFFFF);` | 2 | **RED** |
| 11 | same but annotated target `var n: u32` | `var n: u32 = @intCast(u32, node.payload & @intCast(u64, 0xFFFFFFFF));` | 0 | GREEN — annotation downgrades |
| 12 | same but single-statement inferred with outer @intCast | `var name_id = @intCast(u32, node.payload & @intCast(u64, 0xFFFFFFFF));` | 0 | GREEN — outer @intCast pins type |
| 13 | module-var untyped array + index → inferred node | `var nodes = [_]Node{...}; var node = nodes[0];` | 2 | RED (inferred `var node`) |

The committed form (row 10) is the MINIMAL self-contained RED: untyped module-level
struct var + field access + u64 `& @intCast(u64, ...)` in an inferred var-init. It
matches the brief's escalation guidance ("field-access shape ... most faithful" to
the module-var `node` at symbol_registrator.zig:357) and keeps the exact `&
@intCast(u64, 0xFFFFFFFF)` narrowing shape from the brief's trigger expression. The
brief's ladder form (a) `var p: u64` + `var n: u32` is GREEN (both the module var and
the target are typed — the void collapse is masked). The brief's literal fixture (1)
is GREEN — same false-start as R1/R2.

## GREEN control (brief Step 3, /tmp only)
`var n: u32 = 0;` (rest of program identical) → dump rc=0, gcc rc=0, run prints `0`,
run rc=0.

## Type-kind matrix (brief Step 4) — probes in /tmp, bare @import("std") + printInt
Committed-form context used throughout: untyped module struct var `var node =
Node{ .payload = 0xFFFFFFFF00000000 };`, expression in **inferred** var-init unless
stated.
| # | variant | shape | dump rc | verdict |
|---|---------|-------|---------|---------|
| 1 | trigger shape (as committed) | `var n = node.payload & @intCast(u64, 0xFFFFFFFF);` | 2 | **RED** |
| 2 | `&` alone to annotated u64 | `var q: u64 = node.payload & @intCast(u64, 0xFFFFFFFF);` | 0 | GREEN (annotation masks) |
| 3 | u64 `\|` | `var n = node.payload \| @intCast(u64, 0xFF);` | 2 | RED |
| 4 | u64 `^` | `var n = node.payload ^ @intCast(u64, 0xFF);` | 2 | RED |
| 5 | reverse @intCast (u32→u64) | `var u: u32 = 5; var n = @intCast(u64, u);` | 0 | GREEN |
| 6 | 64-bit literal typing | `var n = 0xFFFFFFFFFFFFFFFF;` (local) | 0 | GREEN |
| 7 | plain u64→u32 cast, no `&` | `var n = @intCast(u32, node.payload);` | 0 | GREEN |
Also probed (module-scalar carrier, same verdicts): `var p = 0xFFFFFFFF00000000;`
+ variants 1/3/4 → RED; variants 2/5/6/7 → GREEN. And matrix variant 1 with
**annotated** target → GREEN (warning[3000]-free), with **outer** @intCast → GREEN
(row 12 above).

## Blast-radius lead (feeds I-U64CAST)
RED requires an **untyped module-level var/const referenced in an inferred var-init**
— exactly the R1/R2 poison (module-level reference → void in value position) now
carried by the u64 bitwise-and shape. Neither the `&` operator (variant 3/4 `|`/`^`
also RED — so it is NOT the `&` specifically), nor the `@intCast(u64, ...)` narrowing
(variant 7 without `&` is GREEN, so the narrowing alone is innocent), nor the large
literal typing (variant 6 GREEN), nor the field access per se (typed-module-var
field-access row 5 is GREEN) is the poison. The trigger is the **untyped module-var
value reference**; the u64 `&` + `@intCast(u64, 0xFFFFFFFF)` is the carrier. Annotating
the consuming var (`: u32`/`: u64`) or wrapping in an outer `@intCast(u32, ...)` (which
pins the declared type) downgrades RED→GREEN. I-U64CAST should investigate the same
const/var resolution path as R1/R2 (I-IFEXPR / I-SWITCHEXPR): untyped module-level
declaration referenced in value position → void. The committed form's inferred
`var n = node.payload & ...` mirrors symbol_registrator.zig:357's chain (module var
`node`, u64 `payload` field, `& @intCast(u64, 0xFFFFFFFF)`).

## Secondary observation (not the void-decl RED)
GREEN forms that reference a module-level **struct** var's field in a binop emit C
that gcc rejects with `'zT_2' undeclared` (e.g. matrix variant 2/7, t14):
```
/tmp/f2.c:59:12: error: 'zT_2' undeclared (first use in this function)
   59 |     zT_4 = zT_2 & zT_3;
```
The zT_2 is declared later in the same fn (C-emission ordering/scope bug). This does
NOT affect the committed RED fixture (it aborts before any .c is emitted) but is a
latent emission bug to flag for the fix task.

## Post-fix expectation
This fixture flips RED→GREEN: dump rc=0, gcc rc=0, run prints `4294967295` — matching
the value the committed expression evaluates to (0xFFFFFFFF low half of
0xFFFFFFFF00000000). Once the untyped module-var void collapse is fixed, matrix
variants 3/4 (and the module-scalar/module-const carriers) flip too.

## Cross-ref
R1 sibling (if-expr carrier): `repro/mi_matrix/voiddecl_ifexpr_xmod/`. R2 sibling
(switch-expr carrier): `repro/mi_matrix/voiddecl_switchexpr_xmod/`. Self-compile
9-error set re-verified on this binary: main.zig:588, symbol_registrator.zig:258/:357,
lower.zig:4410/:5218/:5275/:5319/:5395/:5403. Note the self-compile caret at 357
spans a ~244+ char statement (the live `name_id` statement is 87 chars) — the reported
357 span is the value-position reference; the name_id statement text is what the caret
displays, matching the brief's attribution.
