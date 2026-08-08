# extern_runtime_symbol_xmod — class-(b) runtime-library gap repro (std-lib-deferred)  [F2, 2026-08-08]

## What it tests
A minimal cross-module program calling the documented runtime API extern
`arena_alloc_default` (declared `sf/src/include/zig_runtime.h:21-22`):
`lib.zig` re-declares it as `extern "c" fn arena_alloc_default(n: u32) [*]u8`
and wraps it in `pub fn alloc`; `main.zig` imports `lib.zig`, calls
`alloc`, and prints whether the returned pointer is null. This is the
smallest exercise of the json_parser link gap (`json.zig:253`,
`file.zig:25`, `arena.zig:1`): an extern the **sf runtime fails to provide**
(`sf/src/include/zig_runtime.c` has no arena symbols; the symbol exists only
in the legacy `src/runtime/zig_runtime.c:31/:154-156`). Per the I2 report
(`.superpowers/sdd/I-orphan-module-report.md`) this is **class (b)
runtime-library gap**, NOT a compiler defect — the compiler never emits
definitions for externs; the module→`.c` emission loop is verified intact by
`mod_silent_drop_xmod`. **Operator ruling: deferred to the std-zig1 library —
not fixed here.** This repro is the std-lib plan's spec (flips to PASS once
the std-lib runtime provides `arena_alloc_default`).

## Measured result (2026-08-08, sf/build/out_release/zig1)
- `zig1 --dump-c89 --output-dir DIR main.zig` → dump rc=0; **all modules
  emit** (`lib_*.c/.h`, `main_*.c/.h`, `zig_special_types.h`) — no orphan drop.
- gcc `-c` of every emitted `.c` (standard recipe, `-I
  /workspace/znineeight/sf/src/include`): **rc=0** (compile is clean; zig1
  relies on the header's `void* arena_alloc_default(unsigned int)` decl and
  emits only the call site).
- **Standard sf-runtime link rc=1**: `lib_*.c:(.text+0x4a1): undefined
  reference to 'arena_alloc_default'` — the ONLY undefined ref (json_parser
  shows 5: 4 in json + 1 in file; this repro collapses it to 1).
- **Legacy-runtime link flips to PASS**: `gcc -c
  src/runtime/zig_runtime.c -o /tmp/rt.o && gcc *.o /tmp/rt.o
  sf/src/include/zig_pal.c -o prog` → **link rc=0, run rc=0** (prints `0` —
  the lazy-init arena is NULL before `arena_create`; the value is
  incidental, the point is the symbol links and the program runs).
  Confirms class (b): the extern is a documented runtime API
  (`docs/reference/runtime_api.md:38-48`) that only the legacy runtime
  defines.

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

## Expected classification
**OK-by-gate / LATENT, NOT a corpus FAIL**: dump rc=0, all modules emit,
gcc -c clean, standard-recipe link rc=1 ONLY on the missing extern symbol.
Counted separately from FAIL (mirrors `opt_slice_null_return`
OK-by-gate precedent). **Deferred to the std-lib plan** — this repro is the
spec: it flips to a clean link+run (printing `0`) once the std-zig1 runtime
provides `arena_alloc_default` in `sf/src/include/zig_runtime.c` (or the
json_parser legacy-runtime workaround is standardized). `mod_silent_drop_xmod`
stays as the emission regression guard; this repro guards the extern-link
pattern it does NOT cover.
