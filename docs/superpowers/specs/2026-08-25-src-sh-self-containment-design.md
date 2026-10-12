# sf/src_sh/ Self-Containment Implementation — Design

**Date:** 2026-08-25
**Status:** Approved design (Plan 2 of two). Implements the Task 7 design (`/workspace/znineeight/.superpowers/sdd/task-7-report.md`).

## Goal

Make `zig1_5` depend only on `zig1` — leave zig0 out of service. Create an `sf/src_sh/` self-hosted tree where logic is unchanged and only dependencies change: externs migrate to `@cInclude`, `__bootstrap_*` symbols are eliminated, and `zig1_5` links only self-emitted `.o` + a minimal non-bootstrap runtime.

## Current Dependency Facts (Tasks 5-6, verified)

### Toolchain
- zig0 = C++ bootstrap at repo-root `src/bootstrap/` (44 .cpp, unity via `bootstrap_all.cpp`). Emits per-module `.c/.h` (NOT a monolith).
- zig1 built by `build_release.sh`: zig0 → per-module C → `gcc -m32 -std=c89` on `$OUT_DIR/*.c` + `zig_pal.c` → `/tmp/fx_subfolder/zig1`. zig1 links **only** `zig_pal.c` (not zig_runtime.c, not c_exit.c).
- zig1_5 built by `build_zig1_5.sh`: `zig1 --dump-c89 --output-dir gen sf/src/main.zig` (40 per-module `.c`) → `gcc -c *.c` → link `*.o` + `zig_runtime.c` + `zig_pal.c` + `c_exit.c` → `zig1_5`.

### Extern surface
- `sf/src/pal.zig:5-14` — `extern "c" fn`: fopen, fread, fclose, fseek, ftell, c_exit, pal_file_open, pal_file_write, pal_file_close, pal_get_default_lib_path.
- `sf/src/extern_c.zig:1-3` — `extern "c" fn`: write, __bootstrap_print, __bootstrap_print_int.
- `extern_c_z98.zig:1-2` — EXISTING `@cInclude` exemplar (`@cInclude("pal.h")`, `@cInclude("zig_runtime.h")`); DEAD (not imported by the 40-module build).

### Bootstrap symbols (zig1_5 true deps)
- 9 `_from_` cast helpers (176 real calls), ALL bounds-checked (panic on overflow): u32_from_u64=110, usize_from_i32=28, u8_from_u32=18, u8_from_usize=4, i32_from_u32=4, u32_from_i64=4, u32_from_i32=3, i32_from_usize=3, u64_from_i64=2.
- `__bootstrap_panic`: 0 real calls in gen/ (zig1 eliminated module-level panic paths).
- `std_*`: 23 distinct names, 0 real calls (c89_emit string templates).
- libc real: write(2), fclose(4), fopen(2), fread(1), fseek(2), ftell(1).
- Residence: `pal_file_*` + `pal_get_default_lib_path` in emitted pal module; `c_exit` in `sf/src/c_exit.c`.

### @cInclude mechanism
- `@cInclude("X")` emits `#include "X"` (quoted) or `#include <X>` (if starts with `<`) in the module header (c89_emit.zig:2204-2219), per-module. It does NOT parse headers and cannot supply Zig-side signatures (no @cImport).
- Extern fns are never forward-declared by the emitter (c89_emit.zig:2226, :2373 skip `is_extern==1`); calls rely on implicit declaration (kept `-Wno-implicit-function-declaration`).

## Design Decisions

### Decision 1 — `@cInclude` ≠ `@cImport`: pair, don't replace
`@cInclude` supplies only the C prototype. Zig-side signatures for libc/PAL externs are RETAINED as `extern "c" fn` in the .zig source and PAIRED with a `@cInclude` for the C header. Only the `__bootstrap_*` externs are dropped (they are compiler-internal, not libc).

### Decision 2 — `@cInclude("<unistd.h>")` lives in `pal.zig`, NOT `extern_c.zig`
`write` is called only in `pal.zig` (stdout_write/stderr_write via `ext_c.write`, emitted to pal module). `@cInclude` is strictly per-module, and the include must appear in the module whose emitted `.c` performs the call. `extern_c.zig` emits zero `write` calls. So the `<unistd.h>` include goes in `pal.zig`.

### Decision 3 — Rename, don't remove, the 9 cast helpers
The 9 `_from_` helpers are genuine runtime work (bounds-checked casts with panic on overflow). They are renamed `__bootstrap_<a>_from_<b>` → `z_<a>_from_<b>` in a renamed runtime C file, keeping the identical bounds-checking + panic behavior. `__bootstrap_panic` and `__bootstrap_print*` are dropped (zero real call sites in the 40-module build).

### Decision 4 — Runtime split
- **Linked C (minimal, non-bootstrap)**: renamed `zig_runtime.c` (the 9 `z_*_from_*` helpers + `std_panic`) + `zig_pal.c` (unchanged) + `c_exit.c` (unchanged).
- **zig1 emits**: the 40 modules unchanged except `pal.zig` (adds `@cInclude("<stdio.h>")`, `@cInclude("<unistd.h>")`, `@cInclude("sh_runtime.h")`) and `extern_c.zig` (drops `__bootstrap_print*`).
- **libc-only**: fopen/fread/fclose/fseek/ftell/write via system headers.

### Decision 5 — `sf/src_sh/` tree
40-module tree at `sf/src_sh/` (copied-unchanged 37, modified 5, new 1):
- 37 modules copied unchanged.
- `pal.zig` — modified: add the 3 `@cInclude` lines.
- `extern_c.zig` — modified: drop `__bootstrap_print`/`__bootstrap_print_int`.
- `main.zig` + 2 other modules — modified for the renamed helper prefix / import path as pinned in Task 7 report.
- `sh_runtime.h` — new: 9 `z_*_from_*` C prototypes (bounds-checked) + `std_panic`.
- Include dir: `sf/src_sh/include/` holds `sh_runtime.h` (and the system headers come from `<stdio.h>`/`<unistd.h>`).

### Decision 6 — Build script
`build_zig1_5.sh` compiles `sf/src_sh/main.zig` (not `sf/src/main.zig`) and links: self-emitted `.o` + `sf/src_sh/include/zig_runtime.c` (renamed) + `zig_pal.c` + `c_exit.c`. No zig0, no `__bootstrap_*`.

## Success Criteria

1. `zig1_5` builds from `sf/src_sh/` (zig1 → per-module C → gcc → link), zero `__bootstrap_*` symbols in the linked binary (`nm` check).
2. `zig1_5` runs and self-dumps `sf/src/main.zig` (or `sf/src_sh/main.zig`) without regression beyond the documented fidelity-gap behavior.
3. 4 MD5 gates byte-identical: gol `4afb203fdde7a880ec6e7aed32543691`, lisp `5f886646b164a70c52bf042eb54bda78` (repo-root CWD), json `089e4f046464ce3882aa2b2c4e585013`, mud `a1d0dd55aada9c3fd904ae33f54de32e`. (The sh-tree is a NEW directory; canonical sf/src/ emissions are untouched.)
4. `pal.zig` migration compiles: fopen/fread/fclose/fseek/ftell/write call sites resolve via `@cInclude` headers.
5. Documented: `main_exp.zig`/`test_a.zig` break (reference `__bootstrap_print`, non-compiler entrypoints, outside the 40-module build) — out of scope.
