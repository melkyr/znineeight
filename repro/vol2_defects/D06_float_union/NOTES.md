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

## FF conversion (2026-09-26) — FIXED

Fixed point `cadf3c241abd1baf4d31da52b0ccd649` (seed v88 NOT rotated). The
tagged-union init path (`sf/src/lower.zig`, `struct_init` tagged-union arm) now
narrows an **f64 float-literal** payload temp to the selected variant's declared
f32 type (`float_cast` to f32) before the `.assign_field` payload store, so the
emitter's exact type-id variant match selects the real field instead of falling
back to the whole-union `payload = <double>`. The predicate is literal-only
(`float_literal`, optionally under `negate`/`paren_expr`) — the Zig parity rule;
a typed f64 variable stays the documented FX3 residual.

POST (`/tmp/ff/build1/zig1_5_clean`), each entry `-o <dir>` + `build_target.sh
linux <name>` + run:

| Entry | PRE (seed `a3928c11…`) | POST (FF `cadf3c24…`) |
|---|---|---|
| `main.zig` (annotated f32) | compile rc 0, gcc rc 1 | **compile/gcc/run rc 0, `f=2`** |
| `red_anon.zig` (`var c: ShapeF = .{ .circle = 3.0 };`) | gcc rc 1 | **run rc 0, `f2=3`** |
| `red_inferred_f32.zig` | gcc rc 1 | **run rc 0, `f=2`** |
| `xmod_main.zig` (union from `shapes.zig`) | gcc rc 1 | **run rc 0, `f=2`** |
| `red_sibling.zig` (`{a:f32,b:f64}`, `.a = 2.0`) | silent wrong variant (`a=0 b=2.5`) | **run rc 0, `a=2 b=2.5`** |
| `control_f64.zig` / `control_inferred.zig` | `d=2` / `2.5` | byte-identical (`d=2` / `2.5`) |
| `control_int.zig` / `control_bool.zig` / `control_struct.zig` | rc 0 | byte-identical (`go=7 count=9` / `b=true` / `area=12`) |

Emitted C (POST `main.zig`): `zT_1.tag = zT_3; zT_4 = (float)zT_2;
zT_1.payload.circle._0 = zT_4;` — a real `circle` variant store (PRE was
`zT_1.payload = zT_2;`).

Boundaries (unchanged / residual):
- f32-typed sources (`@as(f32, 2.0)`, f32 variable) already selected the variant
  correctly; they stay byte-identical.
- A typed **f64 variable** payload (`var d: f64 = 2.0; var x: U = U{ .a = d };`)
  is Zig-rejected; Z98 stays silent (with an f64 sibling it still writes the
  sibling; without one it still emits the whole-union assignment). Documented
  FF residual, deferred to FX3.
- The f32 **parameter** literal reject (`fn f(x: f32); f(2.0)` → `error[3000]`)
  is unchanged — FX3 owns it.
- The `p_d6_big` shape (`1.0e300` literal into an f32 payload) now compiles and
  selects the right variant (f32 `inf`), but `printF64` prints `inf`
  incorrectly — the documented ch18 print Q2 bounded residual, not a D6
  regression.
- Same-type variant aliasing (two variants with the same type) keeps the
  documented first-match emitter heuristic (NON-ISSUE, unchanged).

## FX3 conversion (2026-09-27) — value-aware narrowing

The FX3 fix (`fix(sema): narrow float values to f32 value-aware`, fixed point
`8233580ff281e73c006d04c5c91281e4`) closes both D6 residuals:

- `green_param.zig` (new sibling) is the former f32-param residual turned
  positive: `takeF32(1.5)`, `takeF32(2)`, a typed `const d: f64 = 2.5` and a
  comptime-known `const c: i32 = 2` all narrow to f32 and print
  `x=1.5 / x=2 / x=2.5 / x=2` (compile/build/run rc 0).
- The typed-f64-variable payload is now a **clean reject**: `U{ .a = d }` with
  a runtime `d: f64` is level-0 `error[3000]` (Zig rejects it too) instead of
  the silent whole-union/sibling write; the same rule applies to runtime f64
  parameters/returns/fields/declarations/assignments and to inexact comptime
  values (`16777217`, typed `f64` 0.1).
- The accept/reject matrix is pinned by
  `repro/mi_matrix/stdlib_f32_narrow_ok_xmod` (golden, Zig-0.15.2-twin
  byte-identical) and `repro/mi_matrix/f32_narrow_reject_xmod` (18 ×
  `error[3000]`, rc 2 / 0 `.c`); the D06 `main.zig` literal payloads stay
  byte-identical.

Documented FX3 boundary: the lexer's naive `parseF64` accumulates digits, so
an extreme literal like `3.4028234663852886e38` is not the correctly-rounded
f64 and a typed const of it stays rejected even though Zig accepts; that is the
pre-existing float-literal precision residual (spec §7.2), not the narrowing
rule.
