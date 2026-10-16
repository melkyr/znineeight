# conditional_import_if_xmod — §4 conditional `@import`, if/else form (T0, RED before any fix)

## What it tests
Spec §4: `const impl = if (@isWindows()) @import("a.zig") else @import("b.zig");`
must resolve to the LIVE module (the Zig idiom z9play M6 wants for per-platform
backends). `import_expr` in expression position (`semantic_analyzer.zig` /
`type_resolver.zig` / `lower.zig` handle it only at decl/member positions
today), plus the §3 sema fold so the untaken arm's `@import` is never resolved.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`, `-ffast --dump-c89`)
- dump rc=0, 6 `.c` — NEITHER `a_zig`/`a_*.c` NOR `b_zig`/`b_*.c` module
  emitted (the `import_expr`s in the if arms are dropped).
- gcc `-c` of `main_D1CCDD00.c` FAILS:
  `main_D1CCDD00.c:29:24: error: 'zT_4294967295' undeclared (first use in this function)`
  (`impl.ping()` calls through a garbage/unresolved module value — the
  documented "currently yields void"/unresolved behavior).

## Expected classification
- RED pre-fix: **FAIL** (emitted `.c` present but gcc-invalid). Recorded before
  any fix.
- After T4 (conditional `@import` resolution): `impl` = live module
  (`b` on linux, `a` on `-osw`); only the live module is resolved/emitted;
  stdout `b ping\ncond import if ok\n` (linux) / `a ping\ncond import if ok\n`
  (`-osw`), rc 0 → class **OK** (this NEW fixture's designed FAIL→OK flip).
  Goldens captured by T4 at fix time (GREEN contract in main.zig header).

## Why no expected.txt/expected.rc
No runtime golden is measurable pre-fix (the frontend accepts but emits
gcc-invalid C; the build dies before run). zT_missing_fwd_xmod defect-repro
shape (NOTES + sources). T4 captures goldens at fix time.
