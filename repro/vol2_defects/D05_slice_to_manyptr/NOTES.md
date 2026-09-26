# D5 — slice -> `[*]T` implicit coercion emits gcc-invalid C (RED)

## Claim
Passing/storing a `[]T` / `[]const T` where `[*]T` / `[*]const T` is expected
compiles (rc 0) but emits C that gcc rejects with
`cannot convert to a pointer type` (the whole slice struct is cast to a
pointer).

## Chapter impact
Chapter 3 (pointers, sample `pointers.z98`) and chapter 9 (arrays and slices,
sample `strings.z98`) — the spec-promised coercion cannot be used.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D05_slice_to_manyptr
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D05_slice_to_manyptr \
    repro/vol2_defects/D05_slice_to_manyptr/main.zig     # rc 0
cd /tmp/vol2_defects_out/D05_slice_to_manyptr && timeout 120 sh build_target.sh linux main
```

## OBSERVED
- `main.zig`: compile rc 0; gcc build rc 1:
  ```
  main_0A340D3A.c:39:5: error: cannot convert to a pointer type
  ```
  Emitted C:
  ```c
  zT_9.ptr = arr;
  zT_9.len = zT_10;
  sl = zT_9;
  zT_12 = (int*)sl;      /* sl is the slice struct */
  mp = zT_12;
  ```
- `red_const_slice.zig`: same gcc error at `red_const_slice_D17091C2.c:39:5`.
- `xmod_main.zig` + `helper.zig` (coercion at the call into a
  `fn first(mp: [*]i32)` in another module): gcc error
  `xmod_main_C2442CBC.c:38:5: error: cannot convert to a pointer type`; C
  `zF_4881D841_first((int*)((int*)sl))`.
- Passing controls (compile+build+run rc 0):
  `control_array_slice.zig` -> `sl[1]=20 len=3`;
  `control_slice_slice.zig` -> `b[1]=20`;
  `control_array_manyptr.zig` -> `mp[2]=30 cmp[0]=10`;
  `control_ptr_field.zig` (`.ptr` workaround) -> `mp[1]=20`.

## EXPECTED
Language Spec, "Type Coercions / Implicit Coercion to Many-Item Pointers and
Slices": "**Slice to Pointer**: A slice `[]T` is coerced to `[*]T` by
accessing its `.ptr` field", allowed in assignments, argument passing and
returns. Expected: `mp[1]=20` (or the xmod `first-ish=20`). Zig 0.15.2 oracle
(comparison only): Zig rejects `[]i32` -> `[*]i32` with
`error: expected type '[*]i32', found '[]i32'`; the Z98 spec explicitly
promises the coercion, so the defect is that Z98 accepts it and then emits
invalid C instead of either lowering `.ptr` or rejecting.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| In-module `[]i32` -> `[*]i32` | `main.zig` | RED | gcc `cannot convert to a pointer type` |
| Cross-module parameter | `xmod_main.zig` + `helper.zig` | RED | gcc error at call |
| Const slice -> `[*]const` | `red_const_slice.zig` | RED | gcc error |
| Array -> slice | `control_array_slice.zig` | control | runs |
| Slice -> slice | `control_slice_slice.zig` | control | runs |
| Array -> `[*]` (mut + const) | `control_array_manyptr.zig` | control | runs |
| Explicit `.ptr` | `control_ptr_field.zig` | control | runs |

## Boundary
Array -> `[*]T` is correctly lowered (`&arr[0]`-style); only the slice source
is emitted as a raw cast of the slice struct. The investigation should also
check the return-value context and the `[]const T` -> `[*]const T` direction
(the latter is RED here).
