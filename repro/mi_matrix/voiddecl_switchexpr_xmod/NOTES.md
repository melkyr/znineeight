# voiddecl_switchexpr_xmod — RED trigger: untyped enum-const arms in value-position switch

**Status: DONE** (2026-08-19). Reproduces `error[3000] cannot declare variable of
type void` for the value-position `switch (x) { … => enum_const, … }` shape at
`symbol_registrator.zig:258` (`var type_kind: TypeKind = switch (init_node.kind) {
AstKind.struct_decl => TypeKind.struct_type, … }`). Trigger = **untyped module-level
consts** (enum-valued) referenced as switch-arm values in an **inferred var-init**.
Enum annotation on the var downgrades to warning; literal / direct enum-member /
struct / union arms are GREEN.

## Purpose
Task R2 of the voiddecl-family plan. Minimal RED repro + type-kind matrix for the
value-position switch-expr void collapse. Self-contained (single main.zig — the
commit rule allows only main.zig + NOTES.md in this fixture dir).

## Fixture (main.zig, committed, md5 `f0b976608722fdf025c930d2b1639f69`)
```zig
const std = @import("std");
const E = enum(u8) { struct_type, void_type };
const A = E.struct_type;
const B = E.void_type;
pub fn main() void {
    var kind: u32 = 0;
    var t = switch (kind) {
        0 => A,
        else => B,
    };
    std.io.printInt(@intCast(u32, @enumToInt(t)));
}
```
`@enumToInt`/`@intCast` only in the print; Z98 dialect constraints (no anytype, no
@Type) respected. `const A = E.struct_type;` is a **truly-untyped** module-level
const whose value is an enum member — the poison. The switch is the carrier.

## RED baseline (Step 2)
Recipe (from fixture dir):
`timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig`
```
rc = 2
stderr:
main.zig:7:4: error[3000]: cannot declare variable of type void
    var kind: u32 = 0;
    ^^^^^^^^^^^^^^^^^^ ... (wide caret)
```
- stdout (the `.c`) = 0 bytes — compile aborts, nothing emitted.
- Diagnostic caret sits on line 6's text (`var kind: u32 = 0;`) while reported at
  7:4; the actual poisoned statement is line 7 (`var t = switch (kind) {`). Same
  off-by-one diagnostic display quirk seen in R1 and in the self-compile
  (symbol_registrator.zig:258 shows line 257's `if` text).

## Escalation table (brief Step 1 ladder + extras, all probed in /tmp)
| # | form | shape | dump rc | verdict |
|---|------|-------|---------|---------|
| 1a | literal arms, same-module enum annotation | `var t: E = switch (kind) { 0 => E.first, else => E.second };` | 0 | GREEN |
| 1b | inferred var, no annotation, direct enum-member arms | `var t = switch (kind) { 0 => E.first, else => E.second };` | 0 | GREEN |
| 1c | cross-module enum consts via module consts | `mod.F`/`mod.S` (annotated) | 0 | GREEN (warning only) |
| 1c' | cross-module enum consts, inferred | `var t = switch … { 0 => mod.F, else => mod.S }` | 2 | RED (needs mod.zig; not committed — commit rule) |
| 1d | **untyped module-level enum-const arms, inferred** (COMMITTED) | `const A = E.struct_type; … var t = switch (kind) { 0 => A, else => B };` | 2 | **RED** |
| 1d' | same arms but var annotated | `var t: E = switch (kind) { 0 => A, else => B };` | 0 | GREEN — warning[3000] source:void target:enum |
| 1e | cross-module enum alias, two-step | `const TypeKind = type_mod.TypeKind; … switch` arms `TypeKind.struct_type` | 2 | RED (needs mod.zig) |

The committed form (1d) is the MINIMAL self-contained RED: untyped module const
arms + inferred var. It matches the brief's own escalation guidance ("untyped
module-level const arms (R1 lesson)"). The brief's literal fixture (1a) is GREEN —
same false-start as R1.

## GREEN control (Step 3, /tmp only)
`var t: E = E.struct_type;` (rest of program identical) → dump rc=0; gcc rc=0; run
prints `0`, run rc=0.

## Type-kind matrix (Step 4) — probes in /tmp, bare @import("std") + printInt
| # | variant | shape | dump rc | verdict |
|---|---------|-------|---------|---------|
| 1 | enum annotation + untyped enum-const arms | `var t: E = switch (x) { 0 => A, else => B }` (A/B untyped) | 0 | GREEN — warning only (source: void, target: enum) |
| 2 | inferred var, int arms | `var t = switch (x) { 0 => 13, else => 12 };` | 0 | GREEN |
| 3 | arms returning struct values | `S{.v=13}` / `S{.v=12}` | 0 | GREEN |
| 4 | arms returning union values | `U{.a=13}` / `U{.b=12}` | 0 | GREEN |
| 5 | switch as fn-argument expression | `useE(switch (x) { 0 => A, else => B })` | 0 | GREEN |
| 6 | cross-module enum annotation + cross-module enum-const arms (258-faithful) | `var t: TypeKind = switch … TypeKind.struct_type` via `const TypeKind = type_mod.TypeKind` | 2 | RED (needs mod.zig) |
| 7 | annotated (`: E`) vs inferred — does annotation matter? | annotated: warning-only GREEN; inferred: **RED** | 0 / 2 | annotation downgrades |

## Blast-radius lead (feeds I-SWITCHEXPR)
RED requires an **untyped module-level `const`** referenced as a switch-arm VALUE in
an **inferred var-init** — exactly the R1 poison (`const X = <expr>;` no annotation)
now carried by a switch instead of an if. The switch itself is not the problem
(int/struct/union/direct-enum-member arms all GREEN); the module-const reference is
the poison, the switch is the carrier. Cross-module forms (module-const arms via an
imported enum, or a two-step `const TypeKind = type_mod.TypeKind` alias) are also RED
and are the most faithful to symbol_registrator.zig:258, but need a second module
file which the fixture commit rule excludes — so the same-module form is committed.
Annotating the var (`: E`) downgrades to `warning[3000]` (void collapse still
computed, source:void target:enum). Local enum-typed consts (inside `main`) are
GREEN. I-SWITCHEXPR should investigate the same const-resolution path as R1
(I-IFEXPR): `const X = <enum-member expr>` untyped → void in value position.

## Post-fix expectation
This fixture flips RED→GREEN: dump rc=0, gcc rc=0, run prints `0` — matching the
GREEN control. Variant 6 (cross-module, the faithful 258 shape) and R1's fixture
flip too, once the untyped-module-const void collapse is fixed.

## Cross-ref
R1 sibling (if-expr carrier): `repro/mi_matrix/voiddecl_ifexpr_xmod/`.
Self-compile 9-error set re-verified on this binary: symbol_registrator.zig:258 is
in it; full list main.zig:588, symbol_registrator.zig:258/:357, lower.zig:4410/:5218/
:5275/:5319/:5395/:5403.
