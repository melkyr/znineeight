# Multi-Module C89 Emission — Design Specification

**Version:** 1.0
**Date:** 2026-07-31
**Status:** Approved

## 1. Goal

Make zig1's `--dump-c89` emit one `.c` and `.h` file per module (instead of a single monolithic `.c`), matching the design intent in `docs/sf/LIR_C89_Emission_p2.md` §2 and zig0's behavior. This enables incremental compilation where each `.c` compiles to `.o` independently.

## 2. Architecture

```
zig1 --dump-c89 -o <outdir> <entry.zig>
  → outdir/
      zig_special_types.h      (shared: Slice_*, EU_*, Opt_*, TU_* typedefs)
      zig_runtime.h             (copied from sf/src/include/)
      main.c + main.h           (root module)
      sand.c + sand.h           (module 1)
      value.c + value.h         (module 2)
      ...
      Makefile                  (generated build script)
```

## 3. Output per module

### module.h
- `extern fn` prototypes for this module's `pub` functions (mangled names)
- `extern var` declarations for this module's `pub` variables
- `#include "zig_special_types.h"` (for type definitions)
- Forward type declarations if needed (`typedef struct zS_Foo zS_Foo;`)

### module.c
- `#include "module.h"` (own header)
- `#include` of imported modules' `.h` files (topological dependency order)
- `#include "zig_runtime.h"` (runtime functions)
- Function bodies in source-declaration order
- Includes only the `.h` of direct imports, not transitives (transitive usages use imported-module types, which the direct import's `.h` already declares)

## 4. Include strategy

**Topological (Model A):** Each `.c` includes only the `.h` of its direct imports. Kahn's sorted order ensures `.h` files are emitted before the `.c` that needs them. This avoids:
- Circular include headaches
- Anonymous union/struct cross-module type confusion
- Monolithic-all-includes drifting out of sync

## 5. Shared files

| File | Content | Emitted once? |
|------|---------|---------------|
| `zig_special_types.h` | All Slice_*, EU_*, Opt_*, TU_* typedefs shared across modules | Yes |
| `zig_runtime.h` | std_print*, arena, panic prototypes | Copied from `sf/src/include/` |
| `zig_pal.c` / `zig_pal.h` | PAL layer (stderr, itoa, memcpy, Win32/POSIX) | Copied from `sf/src/include/` |
| `Makefile` | gcc commands: compile each `.c` → `.o`, link all `.o` → executable | Generated |

## 6. Emission order

Per `LIR_C89_Emission_p2.md` §2:
1. Phase 1: Type headers — emit `zig_special_types.h`, then each module's `.h` in Kahn topological order
2. Phase 2: Function bodies — emit each module's `.c` (includes its own `.h` + imports' `.h` + shared headers)

Ownership: functions go to the `.c` of the module where they're declared. Pub functions get prototypes in the module's `.h`. Private functions stay in `.c` only.

## 7. I-task scope

Research-only (no prototype code). Study:
1. Current `c89_emit.zig` emission loop (`emitModule` at :1605-1611, `emitSpecialTypes`, per-function loop)
2. Module ownership model — which functions/types belong to which module (module_registry + symbol_table)
3. How to emit multiple files: add `output_dir` to C89Emitter, open/close `BufferedWriter` per module
4. Cross-module include dependency list per module (from import edges in module_registry)
5. `main.zig` changes: `--output-dir` flag, invoke emitter per module
6. Build script generation — minimal `Makefile` or `build.sh`
7. zig0 comparison: verify zig0's independent `.c` + `.h` per module pattern

Produce report with exact edit targets (file:line), Option A/B/C comparison, blast-radius analysis. Then F-task executes the implementation.

## 8. Success criteria

- `zig1 --dump-c89 -o /tmp/out examples/z98/lisp_interpreter_curr/main.zig` produces 10 `.c` + 10 `.h` files
- `gcc -m32 -std=c89 -c` each `.c` independently → zero errors
- `gcc -m32` link all `.o` + runtime → executable runs correctly
- All 18 examples produce correct multi-module output
- Corpus: 184 repros, OK=176 FAIL=8 ICE=0 CRASH=0
