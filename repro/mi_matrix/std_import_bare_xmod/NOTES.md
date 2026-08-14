# std_import_bare_xmod — FAIL (import resolver defect: bare `@import("std")` has no search path)  [Task R, 2026-08-14]

## What it tests
A **bare module-name import**: `const std = @import("std");` followed by
`std.io.printInt(@intCast(i32, 42))`. The import resolver must find `std.zig`
via a **search path** (a `-I`/`--lib-dir` mechanism) rather than a sibling or
relative file. This is the D1 gap that forces every current repro to carry
byte-local copies of `std.zig`/`std_io.zig` in-tree.

## Layout (intentional)
- `main.zig` — the bare `@import("std")` caller.
- `local/std.zig` + `local/std_io.zig` — io-only std copies (byte-identical to
  `repro/mi_matrix/union_literal_nested_xmod/{std,std_io}.zig`), placed in the
  `local/` subdirectory which is **NOT on any path**. The bare import cannot
  fall back to a sibling — there is none next to `main.zig`.

## The compiler gap
`@import("std")` (bare module name) fails to resolve. `moduleResolverResolve`
(`sf/src/module_registry.zig:144`) searches only: (1) the importer's own
directory, (2) the `search_dirs` list — never populated, because
`moduleResolverAddSearchDir` (`:139`) is not called from any CLI path — and
(3) `.` (the CWD). There is no `.zig`-extension append for bare names and no
`-I`/`--lib-dir` flag wired through `main.zig` to seed `search_dirs`, so the
bare name `"std"` never maps to `std.zig`; `moduleRegistryResolveImport`
(`:260`) returns null → `error[3048]`.

## Two-state test (the gate for the I/F search-path tasks)
- **No flag → FAIL (RED):** bare `@import("std")` is unresolved; `--dump-c89`
  emits 0 `.c` files and a diagnostic. See "Measured result" below.
- **`--lib-dir local/` (or `-I local/`) → SUCCESS (GREEN):** the resolver
  searches `local/`, finds `std.zig` → `std_io.zig`, and the program prints
  `42`. **NOTE:** this flag is NOT implemented yet — this is the EXPECTED
  post-fix behavior only, recorded for the I/F tasks. Do not run it today.

## Measured result (2026-08-14, /tmp/fx_subfolder/zig1)
Command:
```bash
/tmp/fx_subfolder/zig1 --dump-c89 repro/mi_matrix/std_import_bare_xmod/main.zig > /tmp/r.c 2>/tmp/r.err; echo "rc=$?"
```
- **dump rc=2** — frontend failure, 0 `.c` files emitted, stdout empty.
- **stderr:**
  ```
  error[3048]: could not resolve imported file 'std'
  ```
- Corpus classification: **FAIL** (import-resolution gap — real compiler gap).

## Expected classification
**FAIL pre-fix → OK post-fix** (the I/F search-path tasks add `-I`/`--lib-dir`
handling so the bare name resolves against `local/`).
