# opt_slice_null_xmod — OK-by-gate but LATENT emission defect (null-payload temp typed `int`, cross-module)  [I-task: Battery B2, 2026-08-07]

## What it tests
`catch return null` in a function whose return type is an OPTIONAL SLICE —
`?[]Path` — where the function lives in an IMPORTED MODULE
(`opt_slice_null_xmod/lib.zig`), exercising the cross-module
( `zig1 --dump-c89 --output-dir`) code path. The null payload of the
optional-of-slice is emitted as an `int` temp assigned `NULL`
(`zT_3 = NULL; zT_4.has_value = 0;`), where the payload field of the optional
struct is really a slice
(`typedef struct { zT_..._Slice... value; int has_value; } Opt;`).

## The compiler gap
Same defect as `opt_slice_null_return` / `opt_slice_null`, but reproduced
cross-module: the null-construction for an optional type uses a scalar `int`
temp for the payload regardless of the payload's real type. For an optional
pointer (`?*T`) the payload IS a pointer and `int`/`NULL` is acceptable; for
an optional slice (`?[]T`) the payload is a struct, so the temp type is wrong.
LATENT BUG, not a hard compile error: gcc rc=0, warning only, and the payload
is never read when `has_value=0`. Real breakage only if the payload temp
becomes strictly type-checked (e.g., `-Werror`).

## Pre-fix emitted-C symptom (zig1, 2026-08-07, lib module `lib_*.c`)
```
    int zT_3;
    ...
    zT_3 = NULL;
    zT_4.has_value = 0;
    return zT_4;
```

## Measured result (2026-08-07, sf/build/out_release/zig1, multi-module recipe)
- dump rc=0 (emits `lib_F46EFE00.c/.h`, `main_FD8EEF0C.c/.h`, `zig_special_types.h`).
- gcc `-c *.c` rc=0 but 2 `-Wint-conversion` warnings, BOTH in the LIB
  module's `.c` (`lib_F46EFE00.c:28` and `lib_F46EFE00.c:36`,
  `assignment to 'int' from 'void *' makes integer from pointer without a cast`)
  — the `?[]Path` fn with `catch return null` lives in lib; main emits clean C.
- link rc=0, run rc=0, prints `1`.
- Classification: **OK by the gcc-exit-code gate** (rc=0), but guarded here
  because the emitted C type is wrong (payload temp typed `int` instead of
  the slice struct). Not counted as a FAIL in the corpus baseline.

## Oracle verification (zig0)
`./sf/build/zig0` accepts the program (rc=0) — optional slices with
`catch return null` are valid Z98.

## Expected classification
LATENT: currently OK (gcc rc=0, warnings only) but emits an incorrect C
type for the optional-of-slice null payload. Would become FAIL under
`-Werror` or if the payload temp were strictly typed.
