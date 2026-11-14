# strictzig_brace_if_xmod — migration gate fixture + byte-identity proof (M1) — GREEN-GUARD

## What it tests
The invalid `if (cond) stmt; else stmt;` form (`;` before `else`), which is invalid in the Zig
grammar. The Z98 self-hosted compiler uses this exact shape at `sf/src/type_resolver.zig:980-981`
(`if (sz_node.kind == AstKind.add) arr_len = lhs + rhs; else arr_len = lhs - rhs;`),
`:987-990`, and `sf/src/diagnostics.zig:295-296`. zig1 correctly rejects this form with
`error[2000]`; zig0 (the immutable C++98 bootstrap) is lenient. M2 migrates exactly those 3
sites to braced form; this fixture locks the RED baseline + the byte-identity evidence that the
migration emits byte-identical C.

Fixture is self-contained: bare `@import("std")` (resolved via installed canonical lib at
`/tmp/fx_subfolder/lib/`) + one function doing the invalid if/else.

## Measured baseline — RED (2026-08-18, `/tmp/fx_subfolder/zig1` at HEAD)

```
cd repro/mi_matrix/strictzig_brace_if_xmod && timeout 120 /tmp/fx_subfolder/zig1 --dump-c89 main.zig > /tmp/x.c 2>/tmp/x.err; echo rc=$?
```

- **dump rc=2** (frontend error; no crash)
- **stderr (verbatim):**

```
main.zig:6:4: error[2000]: expected expression
    if (kind == 0) x = x + 1;
    ^^^^
main.zig:6:4: error[2000]: unexpected token
    if (kind == 0) x = x + 1;
    ^^^^
main.zig:8:0: error[2000]: expected expression
    std.io.printInt(@intCast(i32, x));
^
main.zig:8:0: error[2000]: unexpected token
    std.io.printInt(@intCast(i32, x));
^
```

- **0 `.c` emitted** (`/tmp/x.c` = 0 bytes) → frontend gap, classified FAIL (never "OK").

## Control — braced form emits byte-identical C (the migration's evidence)
Temporary braced variant (in /tmp, NOT committed):
```zig
if (kind == 0) { x = x + 1; } else { x = x - 1; }
```
- **dump rc=0**, gcc rc=0, run prints `3` rc=0.
- Emitted C byte count: **10846 bytes** (`/tmp/x_brace.c`).
⇒ M2's brace migration of the 3 sites emits byte-identical C ("no re-baseline" guarantee).

## Post-migration expectation
The fixture can never be GREEN on its own: it IS the invalid form. Per the oracle ruling
(2026-08-24, out-of-scope residual closeout plan), real Zig rejects `if (cond) stmt; else stmt;`
— so zig1's `error[2000]` rejection is CORRECT behavior. **Reclassified GREEN-GUARD** (correct
rejection): the fixture is no longer counted as FAIL. The braced control is what the migration
produced (migrated at HEAD `1585adf2`, 2026-08-18); the migration emits byte-identical C. The
fixture flips green-guard→OK only if zig1 were ever to accept the invalid form (a regression).
