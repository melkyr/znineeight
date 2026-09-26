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
