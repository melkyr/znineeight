# D10 — `p[0]` on a single-item pointer is accepted (RED, acceptance bug)

## Claim
`p: *i32; p[0]` compiles and runs (`42`) although Language Spec §1.2 says
`ptr[i]` is "strictly rejected for single-item pointers". This repro pins the
current behavior; the investigation decides defect-vs-spec-correction.

## Chapter impact
Chapter 3 (pointers, sample `pointers.z98`) — the chapter must not claim the
rejection until the operator rules. Task 0 OQ: spec vs implementation.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D10_single_ptr_index
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D10_single_ptr_index \
    repro/vol2_defects/D10_single_ptr_index/main.zig
cd /tmp/vol2_defects_out/D10_single_ptr_index && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

## OBSERVED
- `main.zig`: compile/build/run rc 0:
  ```
  p[0]=42
  p.*=42
  mp[1]=20
  ```
  The offending `p[0]` is accepted with no diagnostic.
- `red_p1.zig`: `p[1]=8` (reads past the pointee, accepted).
- `red_field_base.zig`: `ps[0].x=5 ps.x=5` (pointer-to-struct indexed then
  field-accessed; `ps.x` auto-deref also works).
- `xmod_main.zig` + `helper.zig` (`p[1]` inside the imported module):
  `helper=8`.
- `control_deref.zig`: `p.*=42`, `mp[1]=20` (the supported forms).

## EXPECTED
Language Spec §1.2: "**Indexing**: `ptr[i]` is allowed for many-item pointers,
but strictly rejected for single-item pointers." Expected: a compile-time
rejection of `p[0]`/`p[1]`. Zig 0.15.2 oracle (comparison only): `p[0]` on
`*i32` rejects with `error: type '*i32' does not support indexing`. Because
the operator has not ruled whether Z98 should follow the spec text or amend it,
the repro deliberately does not assert a diagnostic text.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| `p[0]` + controls | `main.zig` | RED (accepted) | `p[0]=42` |
| `p[1]` | `red_p1.zig` | RED (accepted) | `p[1]=8` |
| `ps[0].x` field base | `red_field_base.zig` | RED (accepted) | `ps[0].x=5` |
| Cross-module indexing | `xmod_main.zig` + `helper.zig` | RED (accepted) | `helper=8` |
| `p.*` + many-pointer `mp[i]` | `control_deref.zig` | control | `p.*=42`, `mp[1]=20` |

## Boundary
The acceptance also covers `p[1]` and a field base. The D10 investigation
should decide whether the spec sentence or the implementation is authoritative
and pin the diagnostic text if a rejection is added.
