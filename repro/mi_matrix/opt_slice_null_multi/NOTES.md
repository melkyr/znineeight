# opt_slice_null_multi — OK-by-gate but LATENT emission defect (null-payload temp typed `int`, multiple catch-return-null paths)  [I-task: Battery B3, 2026-08-07]

## What it tests
`catch return null` on MULTIPLE error paths (2 calls: `failA`/`failB`) inside
one function whose return type is an OPTIONAL SLICE — `?[]Point`. Exercises
3 null-construction sites (`catch return null` ×2 + final `return null`). Each
null payload of the optional-of-slice is emitted as an `int` temp assigned
`NULL` (`zT_6 = NULL; zT_7.has_value = 0;` etc.), where the payload field of
the optional struct is really a slice
(`typedef struct { zT_..._Slice... value; int has_value; } Opt;`).

## The compiler gap
Same defect as `opt_slice_null_return` / `opt_slice_null`, reproduced with
multiple `catch return null` paths in one fn: the null-construction for an
optional type uses a scalar `int` temp for the payload regardless of the
payload's real type. For an optional pointer (`?*T`) the payload IS a pointer
and `int`/`NULL` is acceptable; for an optional slice (`?[]T`) the payload is
a struct, so the temp type is wrong. LATENT BUG, not a hard compile error:
gcc rc=0, warning only, and the payload is never read when `has_value=0`.
Real breakage only if the payload temp becomes strictly type-checked
(e.g., `-Werror`).

## Pre-fix emitted-C symptom (zig1, 2026-08-07)
```
    int zT_6;
    ...
    zT_6 = NULL;
    zT_7.has_value = 0;
    return zT_7;
```
(3 occurrences — lines 82, 96, 100 in the emitted `.c`.)

## Measured result (2026-08-07, sf/build/out_release/zig1)
- dump rc=0, `.c` emitted (199 lines).
- gcc rc=0 but 3 `-Wint-conversion` warnings
  (`assignment to 'int' from 'void *' makes integer from pointer without a cast`).
- run rc=0, prints `1` (all three `findPath` results are null; null payload
  never read when has_value=0).
- Classification: **OK by the gcc-exit-code gate** (rc=0), but guarded here
  because the emitted C type is wrong (payload temp typed `int` instead of
  the slice struct). A future `-Werror` or a strictness fix would turn this
  into a real FAIL. Not counted as a FAIL in the corpus baseline.

## Oracle verification (zig0)
`./sf/build/zig0` accepts the program (rc=0) — optional slices with
`catch return null` are valid Z98.

## Expected classification
LATENT: currently OK (gcc rc=0, warnings only) but emits an incorrect C
type for the optional-of-slice null payload. Would become FAIL under
`-Werror` or if the payload temp were strictly typed.
