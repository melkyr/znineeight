# D8 — `catch |e|` capture of an error set prints numeric (RED)

## Claim
`catch |e| print("{}", .{e})` prints the numeric error code (`1`) where the
same error-set value printed directly prints `error.Bar`. The provenance is
lost at the capture; direct typed values (const, parameter, return value,
struct field) print the name correctly. An **annotated copy** of the capture
does print the name, so the brief's "even `const et: E = e;` prints numeric"
is NOT reproduced as stated — see the boundary below.

## Chapter impact
Chapter 12 (error unions, sample `error_unions.z98`) and chapter 18 (print)
— the spec print table promises `error.Name` for an error-set value, so a
sample that prints a capture would be silently wrong.

## Seed compiler
`/tmp/manual_seed/zig1_5_clean`, md5 `a3928c11f9852db9646dff39006ef654`.

## Commands
```sh
mkdir -p /tmp/vol2_defects_out/D08_errset_capture
timeout 120 /tmp/manual_seed/zig1_5_clean -o /tmp/vol2_defects_out/D08_errset_capture \
    repro/vol2_defects/D08_errset_capture/main.zig
cd /tmp/vol2_defects_out/D08_errset_capture && timeout 120 sh build_target.sh linux main
timeout 120 ./main
```

## OBSERVED
- `main.zig`: compile/build/run rc 0:
  ```
  direct=error.Bar
  param=error.Bar
  return=error.Bar
  field=error.Bar
  ok=1
  capture=1
  copied=error.Bar
  ```
  `expected.txt` (spec-correct) has `capture=error.Bar`; the diff is the RED.
- Emitted C (`main_70C4AB8F.c`) shows the route difference:
  ```c
  e = zT_21.data.err;
  copied = e;
  std_print("capture=");
  zF_9FD0BAD6_printI32(e);          /* numeric route */
  std_print("copied=");
  z98_printErrorSet_23(copied);     /* name route */
  ```
- `red_capture.zig`: `capture=1`.
- `control_copied.zig`: `copied=error.Bar` — annotating the copy restores the
  name.
- `control_typed.zig`: all four typed shapes `error.Bar`.
- `control_dx_reject.zig`: explicit `{d}` and `{x}` on the typed value are
  rejected `error[3013]` per the spec table.
- `xmod_main.zig` + `errors.zig`: `direct=error.Bar`, `capture=1`.

## EXPECTED
Language Spec §4 print table: `error_set` with `{}` prints `error.Name`
(explicit `{d}`/`{x}` are `3013`). §3.3: the `catch |err|` capture binds the
error code; a captured error-set value printed with `{}` should print the same
`error.Name` as any other typed error-set value. Zig 0.15.2 oracle (comparison
only): `direct=error.Bar`, `capture=error.Bar`.

## Variants
| Shape | File | Verdict | Evidence |
|---|---|---|---|
| Capture + typed controls in one run | `main.zig` | RED | `capture=1` vs `expected.txt` |
| Capture only | `red_capture.zig` | RED | `capture=1` |
| Cross-module error set | `xmod_main.zig` + `errors.zig` | RED | `capture=1` |
| Typed direct/param/return/field | `control_typed.zig` | control | all `error.Bar` |
| Annotated copy of capture | `control_copied.zig` | control | `copied=error.Bar` |
| Explicit `{d}`/`{x}` | `control_dx_reject.zig` | control | `error[3013]` |

## Boundary
Only the un-annotated capture is numeric. Task 0's reviewer
(`s15_capture_type.z98`) saw `typed=error.Bar copy=1` for
`print(.{ et, e })`, which is consistent with this: `et` is the annotated copy
and prints the name, `e` is the capture and prints numeric. The D8
investigation should pin the sema/intrinsic provenance rule (what tags a
value as an error set for printing) and decide whether the annotated copy
route is the documented workaround.

## FE conversion (2026-09-26) — FIXED

Operator ruling #7: **retype the capture temp to the sema error-set type** (not
a narrow print dispatch). `sf/src/lower.zig`'s `catch_expr` arm now reads the
error union's `error_set` from the registry and uses it for `err_code_temp`,
`maybeDisambiguateCapture`, `addLocalDecl` and `decl_local`, exactly the type
`semantic_analyzer.zig` registers for the capture. A bare `!T` capture
(`error_set == 0`) stays `i32` — an explicitly documented residual (anyerror
is unusable today; see the D8 report §9.3).

POST compiler: `/tmp/fe/build2/zig1_5_clean` (fixed point
`536ed4943ecf8bacbbf93343d732c3e0`; direct two-hop closure, seed v88 NOT
rotated).

| Entry | PRE (FD1 compiler `7bf2da19…`) | POST | 
|---|---|---|
| `main.zig` | build+run rc 0, `capture=1` | **build+run rc 0, `capture=error.Bar`** (matches `expected.txt`; controls unchanged) |
| `red_capture.zig` | `capture=1` | **`capture=error.Bar`** |
| `xmod_main.zig` | `capture=1` | **`capture=error.Bar`** |
| `control_typed.zig` | all `error.Bar` | unchanged, byte-identical |
| `control_copied.zig` | `copied=error.Bar` | unchanged, byte-identical |
| `control_dx_reject.zig` | `error[3013]` on `{d}`/`{x}` | unchanged |

Additional verification (probes `/tmp/fe/probes`):

- `{d}` on a **capture** still rejects `error[3013]` at the argument node,
  byte-identically PRE↔POST (no 3013 inconsistency).
- Comparison (`e == error.Bar`), passing the capture to an `E` parameter,
  `return e` from a catch handler and `@intCast(u32, e)` all compile/build/run
  PRE↔POST with byte-identical stdout (`d8_blast`).
- Emitted-C delta is exactly the capture decl/route: `int err;` →
  `zT_…_E err;` (error sets are `typedef int`; a same-type `@intCast` loses
  its runtime check). The 4-MD5 lisp/json dumps move on this delta and were
  re-baselined with PRE↔POST runtime identity (QUICK_REF).


