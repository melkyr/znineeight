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

## FF conversion (2026-09-26) — FIXED (Zig-parity clean reject)

Fixed point `cadf3c241abd1baf4d31da52b0ccd649` (seed v88 NOT rotated). Sema now
validates the five introspection builtins before lowering
(`semanticAnalyzerCheckIntrospectionBuiltin`, `sf/src/semantic_analyzer.zig`):
`@offsetOf`/`@bitOffsetOf` are struct-only (every union kind, scalar, pointer,
enum, slice, array, optional target → level-0 `error[3072]` `expected struct
type, found 'X'`), a missing/unknown/non-literal field name → `error[3073]`
(Zig's `no field named 'x' in struct 'S'` wording for the unknown case), an
unresolved/incomplete target or a wrong argument count → `error[3074]`. The
packed-union offset fold arms are deleted from `comptime_eval.zig` and
`type_resolver.zig`, and the `lower.zig` safety net is now a clean `error[3074]`
fallback (never `error[3043]`).

| Entry | PRE (seed `a3928c11…`) | POST (FF `cadf3c24…`) |
|---|---|---|
| `main.zig` (bare union) | rc 3, `error[3043]` node 16 | **rc 2, 1 × `error[3072]` `expected struct type, found 'Raw'`, 0 `.c`** |
| `red_tagged_offsetof.zig` | rc 3, `error[3043]` | **rc 2, `error[3072]` `found 'T'`, 0 `.c`** |
| `xmod_main.zig` (`raw.zig`) | rc 3, `error[3043]` node 13 | **rc 2, `error[3072]` `found 'Raw'`, 0 `.c`** |
| `control_struct.zig` | `off_a=0 off_b=4` | byte-identical |
| `control_packed.zig` | `off_a=0 bitoff_b=4` | byte-identical |
| `control_sizeof.zig` / `control_alignof.zig` | `size=4` / `align=4` | byte-identical (bare-union `@sizeOf`/`@alignOf` still accepted) |

Additional shapes verified POST (probes `/tmp/ff/out`, fixture
`repro/mi_matrix/union_offset_reject_xmod`): packed-union `@offsetOf` AND
`@bitOffsetOf` now reject 3072 (the legacy `0U` fold is gone), module-level
union `@offsetOf` rejects 3072, scalar target rejects 3072 (`found 'i32'`),
unknown field rejects 3073, const-string name (`const N = "a"`) and int name
reject 3073, missing/extra arguments and `@sizeOf` extra args reject 3074,
unresolved types (`Nope`, `std.base64`) reject 3074. `@sizeOf`/`@alignOf`/
`@bitSizeOf` values are unchanged on every union kind (bare `4/4/32`, tagged
`8/4/64`, two-u8 tagged `8/4/64`, `u8/u64` bare `8/8/64`, `u8/u64` tagged
`16/8/128`, packed `1/1/4`); `@alignOf(void)` stays `0` (documented residual,
untouched). Array-size/enum-init positions keep their pre-existing clean
`error[3050]`/`error[3055]` rejects (structs included — documented 11H
residual); the packed-union array-size fold is gone too, so
`[@offsetOf(PU,"a")]u8` now reports `error[3050]` instead of folding 0.
