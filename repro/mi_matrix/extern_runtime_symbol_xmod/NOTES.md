# extern_runtime_symbol_xmod — std.arena cross-module alloc regression guard  [F3, 2026-08-08]

## What it tests
A minimal cross-module program exercising the **`std_arena.zig`** bump
allocator (the F3 fix that closed the D2/F2 `arena_alloc_default` link gap):
`lib.zig` imports `std_arena.zig` (a local copy of `sf/src/std_arena.zig`),
creates an `Arena`, wraps `std.alloc` in `pub fn alloc`; `main.zig` imports
`lib.zig`, calls `alloc`, and prints whether the returned pointer is null.
Before F3, this repro declared `extern "c" fn arena_alloc_default(n: u32)
[*]u8` — the smallest exercise of the json_parser link gap (`json.zig:253`,
`file.zig:25`, `arena.zig:1`): an extern the **sf runtime fails to provide**
(`sf/src/include/zig_runtime.c` has no arena symbols; the symbol exists only
in the legacy `src/runtime/zig_runtime.c:31/:154-156`). Per the I2 report
(`.superpowers/sdd/I-orphan-module-report.md`) that was **class (b)
runtime-library gap**, NOT a compiler defect — deferred to the std-zig1
library. F3 resolves the deferral with a **Zig-side arena module** instead of
a runtime C symbol: json_parser + json_parser_workaround + this repro now
import `std_arena.zig` and link+run against the STANDARD sf runtime with NO
legacy runtime object. This repro is now the green regression guard for
cross-module `std.arena` use (module emission + alloc + multi-module link).

## Measured result (2026-08-08 F3, sf/build/out_release/zig1)
- `zig1 --dump-c89 --output-dir DIR main.zig` → dump rc=0; **all modules
  emit** (`lib_*.c/.h`, `main_*.c/.h`, `std_arena_*.c/.h`,
  `zig_special_types.h`) — the std_arena module joins the emission set.
- gcc `-c` of every emitted `.c` (standard recipe, `-I
  /workspace/znineeight/sf/src/include`): **rc=0**.
- **Standard sf-runtime link rc=0** (zig_runtime.c + zig_pal.c, NO legacy
  object): the `arena_alloc_default` undefined ref is GONE — the repro now
  calls `std.alloc` (module `std_arena_*.c`), which is self-contained.
- **run rc=0**, prints `0` (the 16-byte alloc succeeds → non-null pointer →
  `@ptrToInt(p) == 0` is false). Same printed value as the F2 legacy-runtime
  run; the point is the cross-module std.arena path links and runs.

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy: dump rc=0, emits `lib.c`/`main.c` (same
module set). **Nuance vs the brief's "SAME link failure"** (documented
honestly): zig0 re-emits the extern declaration in `lib.c` as `extern
unsigned char* arena_alloc_default(unsigned int n);` (from the `[*]u8`
return type), which CONFLICTS with `zig_runtime.h:21` `void*
arena_alloc_default(unsigned int size);` → the oracle's standard-recipe
output fails at **compile** (conflicting types), not link. zig1 (which does
not re-emit the extern, using the header decl) fails at **link**. Both
confirm the same underlying runtime gap. Secondary oracle artifact: zig0
emits `__bootstrap_i32_from_bool(...)` for the `@intCast(i32, bool)` — a
checked-cast helper that exists in NO runtime (legacy zig0 emission
behavior; the F1 range-check in zig1 emits a raw `(int)` cast for this
widening), so the oracle's link would cite that helper too. zig1's output
links with the single `arena_alloc_default` undefined ref.

## Source corrections vs the brief's verbatim blocks (both REQUIRED)
1. **main.zig — in-body `extern fn` moved to module scope (top-level).** The
   brief's draft placed `extern fn __bootstrap_print_int(n: i32) void;`
   INSIDE `main()`. Both the current zig1 (dump rc=2, `error[3020]:
   internal error: unhandled node kind in type resolution`) and the zig0
   oracle (syntax error, `Expected a primary expression`) reject an
   in-function `extern fn` declaration — a pre-existing Z98 subset
   limitation, NOT a zig1 defect. The corpus pattern
   (`ptr_to_int_void_xmod`, `opt_slice_null_*`, etc.) declares externs at
   module scope; the repro now matches it.
2. **main.zig — the `@ptrToInt(p) == @intCast(usize, 0)` line works
   post-F1** (as the brief predicted): emitted as `zT_5 = (unsigned int)p;
   zT_6 = 0; zT_7 = zT_5 == zT_6; zT_8 = (int)zT_7;` — `@ptrToInt` resolves
   to `usize` (single-arg call, commit `51bfdb3c`), no error.

## Expected classification (F3)
**FULLY OK (regression guard)**: dump rc=0, all modules emit, per-file gcc
`-c` rc=0, standard-recipe link rc=0, run rc=0. The F2 std-lib-deferred /
OK-by-gate-latent classification is CLEARED — the repro migrated off the
`arena_alloc_default` extern to the `std_arena.zig` module (F3). It is the
green regression guard for cross-module `std.arena` use: a future regression
that drops the std_arena module, breaks its emission, or re-breaks the
multi-module link/run flips this repro to FAIL/ICE. `mod_silent_drop_xmod`
remains the general emission regression guard.
