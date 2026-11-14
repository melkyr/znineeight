# std_import_bare_xmod — OK (bare `@import("std")` resolves via `<exe_dir>/lib`)  [Task R, 2026-08-14; updated 2026-09-17]

## What it tests
A **bare module-name import**: `const std = @import("std");` followed by
`std.io.printInt(@intCast(i32, 42))`. The import resolver must find `std.zig`
via a **search path** (the `-I`/`--lib-dir` mechanism plus the default
`<exe_dir>/lib` install dir) rather than a sibling or relative file. This is the
D1 gap that once forced every repro to carry byte-local copies of
`std.zig`/`std_io.zig` in-tree.

## Layout (intentional)
- `main.zig` — the bare `@import("std")` caller.
- `local/std.zig` + `local/std_io.zig` — io-only std copies (byte-identical to
  `repro/mi_matrix/union_literal_nested_xmod/{std,std_io}.zig`), placed in the
  `local/` subdirectory which is **NOT on any path**. The bare import cannot
  fall back to a sibling — there is none next to `main.zig`.

## Resolution (current truth)
`@import("std")` (bare module name) resolves. `moduleResolverResolve`
(`sf/src/module_registry.zig`) probes, in order: (1) the importer's own
directory, (2) each `-I`/`--lib-dir` `search_dirs` entry, (3) `<exe_dir>/lib`
(the default canonical install dir, via `pal_get_default_lib_path`), and (4) `.`
(the CWD), with a generic `.zig` auto-append for bare names. Both the
`-I`/`--lib-dir` flag (`sf/src/main.zig`) and `<exe_dir>/lib` are **implemented**
and wired through, so `"std"` maps to `std.zig` and the import resolves.

## Two-state test (the gate for the I/F search-path tasks)
- **No flag → OK (GREEN):** bare `@import("std")` resolves via the default
  `<exe_dir>/lib` install path (canonical std installed), and the program prints
  `42`.
- **`--lib-dir local/` (or `-I local/`) → OK (GREEN):** the resolver searches
  `local/`, finds `std.zig` → `std_io.zig`, and the program prints `42`. This
  flag is implemented; this GREEN path is unchanged.

## Measured result (current: corpus classification **OK**)
Command:
```bash
/tmp/fx_subfolder/zig1 --dump-c89 repro/mi_matrix/std_import_bare_xmod/main.zig > /tmp/r.c 2>/tmp/r.err; echo "rc=$?"
```
- **dump rc=0** — resolves and emits; the program runs and prints `42`.
- Corpus classification: **OK** (was FAIL pre-fix — import-resolution gap).
- Historical FAIL evidence (2026-08-14, before the search path landed): dump
  rc=2, 0 `.c` emitted, stderr `error[3048]: could not resolve imported file
  'std'`.

## Classification history
**FAIL (2026-08-14, pre-fix) → OK (post-fix, via `<exe_dir>/lib`; the
`--lib-dir local/` GREEN path also works).**
