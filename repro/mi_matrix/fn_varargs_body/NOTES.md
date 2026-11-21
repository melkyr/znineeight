# fn_varargs_body — varargs fn bodies via @cVaStart/@cVaArg/@cVaEnd  [4-item compiler gaps plan, Task F5, 2026-08-06]

## What it tests
A Z98-defined variadic function whose body reads its variable arguments with
`@cVaStart` / `@cVaArg` / `@cVaEnd` (`va_list` + C varargs), plus a variadic
`extern fn printf` that is called with `...` (so its C prototype must be
emitted — Option B extern prototypes) and prints the computed sum.

The KEY proof: `sum(3, 10, 20, 30)` returns 60 by reading three `i32`
varargs via `@cVaArg(&vl, i32)`.

## Critical repro constraint
Do NOT `@cInclude("<stdio.h>")` here: stdio declares `printf(const char *, ...)`
while the Z98 declaration `[*]const u8` lowers to `unsigned char*` — a C
prototype type conflict. The repro therefore declares printf standalone and
relies on F5's Option B extern prototype (`int printf(unsigned char *, ...);`
name-passthrough, emitted only for variadic externs).

## Measured result — POST-FIX (Task F5)
- dump rc=0; emitted C contains `#include <stdarg.h>` (stdarg.h gated on any
  `fns[i].is_variadic`), `int printf(unsigned char *fmt, ...);` extern
  prototype, `int ..._sum(unsigned int count, ...) { ... }` definition, and
  `va_start(zL_vl, zL_count);` / `zT_5 = va_arg(zL_vl, int);` / `va_end(zL_vl);`.
- gcc-clean; runs printing `sum=60`, rc=0.

## Classification
- **OK** — frontend + emission + gcc + runtime all pass.
