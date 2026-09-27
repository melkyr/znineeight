# D10 — `p[0]` on a single-item pointer (FIXED by FH, reject 3066/3067)

## Claim
`p: *i32; p[0]` compiled and ran (`42`) although Language Spec §1.2 said
`ptr[i]` is "strictly rejected for single-item pointers". The operator ruled
Zig parity: the spec sentence is narrowed (many-item + `*[N]T` auto-deref only)
and the compiler rejects the residual with a dedicated diagnostic.

## Chapter impact
Chapter 3 (pointers, sample `pointers.z98`) — the chapter may now claim the
rejection (`error[3066]` index / `error[3067]` slice) and teach the three legal
`*T` slice forms (`*[0]T`/`*[1]T`).

## Seed compiler (historical RED evidence)
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## FH conversion (2026-09-27)
The case is now a `fixedreject` in `run_all.sh`: `main.zig` must reject without
signalling, emit 0 `.c`, and match the multi-code census in
`expected_error.txt`:
```
3066 6    p[0], p[1], runtime p[i], p[0] = v, ps[0].x, (*p)[i]
3067 5    p[0..2], p[1..0], p[-1..1], p[0..m] (runtime), p[0..] (former ICE)
3000 10   void-declaration cascades + the unchanged p.*[0] control
```
Zig 0.15.2 oracle wording: `type '*i32' does not support indexing` (+ note
`operand must be an array, slice, tuple, or vector`), `unable to resolve
comptime value` (+ note `types must be comptime-known` for the `type` base),
`slice of single-item pointer must have bounds [0..0], [0..1], or [1..1]`,
`unable to resolve comptime value` (+ note `slice of single-item pointer must
have comptime-known bounds`), `slice of single-item pointer must be bounded`.
No shape emits `error[3043]` any more.

Siblings (exercised outside `run_all.sh`):
- `reject_slice_02.zig` / `reject_slice_10.zig` / `reject_slice_open.zig` —
  the illegal slice forms reject `error[3067]` (rc 2 / 0 `.c`).
- `reject_star_paren.zig` — `(*p)[i]` (a `type` base) rejects `error[3066]`
  instead of the seed-v88 silent `arr[zT_12]` wrong code.
- `control_slice_legal.zig` — accepted + runs rc 0, stdout
  `lens=0 1 0 v=42 sl0=42 c=42 pa1=20 pas1=20 dv=42 mp=20` (the three legal
  `*T` slices now type as `*[0]T`/`*[1]T` with `const`/`volatile` carried; the
  `*[N]T` and deref/many-pointer controls are unchanged).
- `xmod_main.zig` + `helper.zig` — the cross-module `p[1]` rejects
  `error[3066]` in `helper.zig`.

Positive/reject corpus fixtures: `repro/mi_matrix/stdlib_ptrslice_ok_xmod`
(golden, stdlib pin) and `repro/mi_matrix/ptr_slice_reject_xmod` (3066/3067
census); standalone repros `repro/single_ptr_slice_ok.z98` /
`repro/single_ptr_index.z98`.

## OBSERVED (seed-v88 historical)
- `main.zig`: compile/build/run rc 0:
  ```
  p[0]=42
  p.*=42
  mp[1]=20
  ```
  The offending `p[0]` was accepted with no diagnostic.
- `red_p1.zig`: `p[1]=8` (read past the pointee, accepted).
- `red_field_base.zig`: `ps[0].x=5 ps.x=5` (pointer-to-struct indexed then
  field-accessed; `ps.x` auto-deref also worked).
- `xmod_main.zig` + `helper.zig` (`p[1]` inside the imported module):
  `helper=8`.
- `control_deref.zig`: `p.*=42`, `mp[1]=20` (the supported forms, unchanged).
- `p[0..0]`/`[0..1]`/`[1..1]` returned `[]T`; `p[0..2]`/`p[1..0]`/`p[-1..1]`
  were accepted unchecked; `p[0..]` ICEd `error[3043]`; `(*p)[i]` silently
  compiled to wrong C.

## Variants (post-FH verdicts)
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| `p[0]` + reject census | `main.zig` | FIXED (reject) | `3066 6` / `3067 5` / `3000 10` |
| `p[1]` | `red_p1.zig` | FIXED (reject) | `error[3066]` |
| `ps[0].x` field base | `red_field_base.zig` | FIXED (reject) | `error[3066]` |
| Cross-module indexing | `xmod_main.zig` + `helper.zig` | FIXED (reject) | `error[3066]` in `helper.zig` |
| `p.*` + many-pointer `mp[i]` | `control_deref.zig` | control | `p.*=42`, `mp[1]=20` |
| legal `*T` slices | `control_slice_legal.zig` | accepted | `*[0]T`/`*[1]T` golden |

## Boundary
`*[N]T` auto-deref indexing/slicing and `[*]T` stay accepted; `p.*[0]` on
`*i32` keeps its `error[3000]` (deref yields a scalar). The FX5 siblings
(`*[N]T[a..b]` scaling, `*[N]T[s..]`/`mp[N..]` ICEs, unchecked runtime slice
bounds, `pa.*[i]`) are recorded, not fixed. Documented residual: an internal
array-field decay copied into an unannotated local (`var x = s.a; x[i]`) now
rejects `error[3066]` because the decay erases the declared array length.
