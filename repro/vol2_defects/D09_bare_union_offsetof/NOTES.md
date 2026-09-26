# D9 — `@offsetOf` on a union is an internal compiler error (RED)

## Claim
`@offsetOf` on a **bare union** hits
`error[3043]: internal: comptime value unresolved for @sizeOf/@alignOf`.
The same internal error fires for **tagged unions**; `@sizeOf` and `@alignOf`
on the bare union are fine.

## Chapter impact
Chapter 7 (unions, sample `variant.z98`) and chapter 15 (builtins) — union
introspection cannot be used.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D09_bare_union_offsetof
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D09_bare_union_offsetof \
    repro/vol2_defects/D09_bare_union_offsetof/main.zig
# rc=3, internal error
```

## OBSERVED
- `main.zig` (bare union): compile rc **3**:
  ```
  error[3043]: internal: comptime value unresolved for @sizeOf/@alignOf (node 16)
  ```
  No source location in the diagnostic and no C emitted.
- `red_tagged_offsetof.zig` (tagged union): same `error[3043]` (node 16).
- `xmod_main.zig` (union type from `raw.zig`): same `error[3043]` (node 13).
- Passing controls (compile+build+run rc 0):
  - `control_struct.zig` -> `off_a=0 off_b=4`.
  - `control_packed.zig` -> `off_a=0 bitoff_b=4` (`@offsetOf` and
    `@bitOffsetOf` on a packed struct).
  - `control_sizeof.zig` -> `size=4` (`@sizeOf` on the bare union).
  - `control_alignof.zig` -> `align=4` (`@alignOf` on the bare union).

## EXPECTED
Language Spec §4 lists `@offsetOf(T, "field")` as the byte offset of a field;
it is accepted for structs and packed structs. Whatever the correct union
answer is (Zig 0.15.2 oracle, comparison only: `@offsetOf` on a union is
rejected cleanly with `error: expected struct type, found 'Raw'`; the stale
`docs/reference/builtins.md` claim of "offset 0" was already flagged in Task 0),
an *internal* `error[3043]` is not a valid outcome. The compiler should either
fold the offset or reject with a user-level diagnostic.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Bare-union `@offsetOf` | `main.zig` | RED | `error[3043]` internal, rc 3 |
| Tagged-union `@offsetOf` | `red_tagged_offsetof.zig` | RED | `error[3043]` internal |
| Cross-module bare union | `xmod_main.zig` + `raw.zig` | RED | `error[3043]` internal |
| Struct `@offsetOf` | `control_struct.zig` | control | `off_a=0 off_b=4` |
| Packed-struct `@offsetOf`/`@bitOffsetOf` | `control_packed.zig` | control | `off_a=0 bitoff_b=4` |
| Bare-union `@sizeOf` | `control_sizeof.zig` | control | `size=4` |
| Bare-union `@alignOf` | `control_alignof.zig` | control | `align=4` |

## Boundary
The ICE is specific to `@offsetOf` on union types (bare AND tagged);
`@sizeOf`/`@alignOf` are fine. The D9 investigation should confirm the
expected union-offset semantics before any fix.
