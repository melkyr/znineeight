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
