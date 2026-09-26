# D11 — qualified-prong payload capture is unbound (RED)

## Claim
`switch` on a tagged union with a qualified prong (`Shape.circle => |r|`)
rejects `error[20]: identifier 'r' is not declared or imported in this
module`; the anonymous-shorthand prong (`.rect => |rc|`) binds correctly.

## Chapter impact
Chapter 7 (unions, sample `variant.z98`) — the spec's payload-capture syntax
`case => |val|` is only usable in the shorthand spelling.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D11_qualified_capture
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D11_qualified_capture \
    repro/vol2_defects/D11_qualified_capture/main.zig      # rc 2
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D11_qualified_capture \
    repro/vol2_defects/D11_qualified_capture/control_unqualified.zig   # rc 0
```

## OBSERVED
- `main.zig`: compile rc 2:
  ```
  main.zig:13:28: error[20]: identifier 'r' is not declared or imported in this module
          Shape.circle => |r| r,
  ```
- `red_nested_qualified.zig` (struct payload): two `error[20]` diagnostics for
  `rc` on the same prong.
- `red_multiple_qualified.zig` (two qualified prongs with captures): `error[20]`
  for each capture (`r`, `rc`).
- `xmod_main.zig` (type from `shapes.zig`): `error[20]` for `r`.
- `control_unqualified.zig` (shorthand `.rect => |rc|`): compile/build/run
  rc 0 -> `12`. (Uses the struct payload so the unrelated D6 f32 gcc bug does
  not interfere.)

## EXPECTED
Language Spec §3.1: "**Payload Captures**: Tagged union switches support
payload captures `case => |val| ...`. `val` is an immutable reference to the
union's payload for that specific tag." The qualified prong name is a valid
`case` item (the spec example uses `Color.Red...Color.Green` for enums, and
Task 0 verified exact qualified enum prongs work), so `Shape.circle => |r|`
should bind `r`, exactly as the shorthand does. Zig 0.15.2 oracle (comparison
only): the equivalent qualified-capture switch compiles and prints `2`.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Qualified prong + float payload capture | `main.zig` | RED | `error[20]` |
| Qualified prong + struct payload capture | `red_nested_qualified.zig` | RED | `error[20]` (x2) |
| Multiple qualified prongs with captures | `red_multiple_qualified.zig` | RED | `error[20]` per capture |
| Cross-module union type | `xmod_main.zig` + `shapes.zig` | RED | `error[20]` |
| Shorthand prong capture | `control_unqualified.zig` | control | `12` |

## Boundary
The failure is purely lexical in the prong: qualified name => capture is not
bound; shorthand name => capture is. The D11 investigation should check
qualified prongs WITHOUT captures (Task 0's exact enum-prong coverage) and the
tagged-union `else`/naked-tag combinations.

## FE conversion (2026-09-26) — FIXED (D11 + bundled SIGSEGV guard)

Operator ruling: Zig-style enum-operand binding + bundle the unused-capture
SIGSEGV. Three edits:

- `sf/src/semantic_analyzer.zig`: the case-item loop now also resolves
  `AstKind.field_access` prongs through the new
  `semanticAnalyzerResolveSwitchCaseMember`, which matches the prong's member
  name against the switch condition (tagged-union field index / enum member
  value) and fills `enum_value_table` + the resolved type — the same table the
  shorthand `enum_literal` path fills. The capture-binding block registers an
  enum-condition capture with the condition (enum) type, i.e. Zig's
  operand-value semantics. No bogus-member/foreign-qualifier validation (FX4).
- `sf/src/lower.zig` (expression `swt_ex` capture path): the tagged-union
  payload table is indexed **only** when the condition type's kind is
  `tagged_union_type`; a non-tagged-union operand (an enum) binds a fresh COPY
  of the operand value (Zig-style) instead. An enum type's `payload_idx` is
  not a `tu_items` index — the unguarded read SIGSEGV'd on an unused capture.
- `sf/src/lower.zig` (statement `swt_ex` capture path): same guard/binding;
  `tu_type_box2` is now set for every resolved condition type (it was
  tagged-union-only), and the capture block branches on the kind. Unused
  captures on either path are crash-free.

POST compiler: `/tmp/fe/build2/zig1_5_clean` (fixed point
`536ed4943ecf8bacbbf93343d732c3e0`; direct two-hop closure, seed v88 NOT
rotated).

| Entry | PRE (FD1 compiler `7bf2da19…`) | POST |
|---|---|---|
| `main.zig` (f32 payload) | rc 2, `error[20]` | **compile rc 0**, gcc blocked by D6 (FF) |
| `red_nested_qualified.zig` (struct) | rc 2, `error[20]` ×2 | **build+run rc 0 → `area=12`** |
| `red_multiple_qualified.zig` | rc 2 (`error[3068]`, see below) | **compile rc 0** (multiple qualified prongs bind), gcc D6 (f32 circle) |
| `xmod_main.zig` (`shapes.Shape.circle`) | rc 2, `error[20]` | **compile rc 0**, gcc D6 (f32) |
| `control_unqualified.zig` | build+run → `12` | unchanged, byte-identical |
| `red_enum_capture_unused.zig` (new) | **rc 139 SIGSEGV** | **build+run rc 0 → `1 2`** |
| `red_enum_capture_used.zig` (new) | rc 2, `error[20]` | **build+run rc 0 → `c=.red\|1 c=.green\|1`** |

Notes:

- `red_multiple_qualified.zig` gained `else => 0` — the FA-a mandatory-`else`
  rule (`error[3068]`) applies to repro fixtures too; while all three union
  tags were listed, Z98 requires the `else` prong. Without it the file no
  longer reached the D11 defect at all.
- The f32 shapes now stop at gcc on the unrelated D6 whole-union float
  assignment (`incompatible types when assigning to type 'union <anonymous>'
  from type 'double'`), exactly as the D11 report §6 predicted. FF owns D6.
- Enum-operand semantics match the Zig 0.15.2 oracle (comparison only): the
  capture holds the operand value (`v` prints `.red` / `.green` with `{}`,
  same as Zig). Zig additionally rejects an *unused* capture ("unused
  capture"); Z98 accepts it (the pre-fix crash shape) — a documented Z98
  divergence pinned by the new siblings and the mi_matrix fixture.

