# D6 — f32 tagged-union payload emits gcc-invalid C (RED)

## Claim
A tagged-union construction with an **f32** payload (`var a: ShapeF =
ShapeF{ .circle = 2.0 };` or the inferred `var v = ShapeF{ .circle = 2.0 };`)
compiles rc 0 but emits `payload = <double>` (whole union from a double), which
gcc rejects:
`incompatible types when assigning to type 'union <anonymous>' from type 'double'`.
f64, integer, bool and struct payloads emit `payload.<tag>._0 = ...` and work.

## Chapter impact
Chapter 7 (unions, sample `variant.z98`) — the flagship float-payload shape
must be avoided or fixed.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D06_float_union
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D06_float_union \
    repro/vol2_defects/D06_float_union/main.zig          # rc 0
cd /tmp/vol2_defects_out/D06_float_union && timeout 120 sh build_target.sh linux main
```

## OBSERVED
- `main.zig`: compile rc 0; gcc build rc 1:
  ```
  main_34413BC5.c:12:20: error: incompatible types when assigning to type 'union <anonymous>' from type 'double'
  ```
  Emitted C (broken f32 path):
  ```c
  zT_2 = 2e+0;
  zT_3 = 0;
  zT_1.tag = zT_3;
  zT_1.payload = zT_2;        /* assigns the WHOLE union from a double */
  a = zT_1;
  ```
- `red_anon.zig` (annotated anonymous payload `.{ .circle = 3.0 }`): same gcc
  error at line 12:20.
- `red_inferred_f32.zig` (unannotated `var v = ShapeF{ .circle = 2.0 };`):
  same gcc error — the defect is the f32 payload, not the annotation.
- `xmod_main.zig` (union type from `shapes.zig`): same gcc error at line 12:20.
- Passing controls (compile+build+run rc 0):
  - `control_f64.zig` (annotated f64) -> `d=2`; correct C:
    `zT_1.payload.circle._0 = zT_2;`
  - `control_inferred.zig` (unannotated f64) -> `2.5`.
  - `control_int.zig` -> `go=7 count=9`.
  - `control_bool.zig` -> `b=true`.
  - `control_struct.zig` -> `area=12`.

## EXPECTED
Language Spec §1.3 tagged unions: variants carry payloads and the compiler
"handles the C89 declaration and initialization of these internal structures";
nothing restricts payload scalar types. Expected: `f=2`. Zig 0.15.2 oracle
(comparison only): the equivalent f32 tagged-union program compiles and prints
`f=2`.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Annotated f32 payload | `main.zig` | RED | gcc `... from type 'double'` |
| Inferred f32 payload | `red_inferred_f32.zig` | RED | same gcc error |
| Anonymous `.{}` f32 payload | `red_anon.zig` | RED | same gcc error |
| Cross-module f32 union type | `xmod_main.zig` + `shapes.zig` | RED | same gcc error |
| Annotated f64 payload | `control_f64.zig` | control | `d=2`, correct C |
| Inferred f64 payload | `control_inferred.zig` | control | `2.5` |
| Integer payloads | `control_int.zig` | control | `go=7 count=9` |
| Bool payload | `control_bool.zig` | control | `b=true` |
| Struct payload | `control_struct.zig` | control | `area=12` |

## Boundary
The boundary is the payload width: f32 is broken (both annotated and
inferred), f64 works. The investigation should determine whether the emitter
selects the "assign to payload" path for f32 (or all 4-byte floats) and
whether other 4-byte scalar types (e.g. `u32` payloads) are affected — the
`control_int.zig` u8/i32 cases pass, so plain integer payloads are fine.
