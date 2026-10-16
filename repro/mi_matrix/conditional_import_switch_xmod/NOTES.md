# conditional_import_switch_xmod — §4 conditional `@import`, switch form (T0, RED before any fix)

## What it tests
Spec §4 ("and the `switch` form"): `const impl = switch (@isWindows()) {
true => @import("a.zig"), else => @import("b.zig") };` must resolve to the live
module exactly like the if/else form (`conditional_import_if_xmod`).

## Spelling note
The `true`/`else` prong set is deliberate: Z98's switch rejects an exhaustive
bool prong set without `else` (`error[3068]: switch must have an 'else' prong`
— measured 2026-10-16 on the `true`/`false` no-else spelling). That
bool-exhaustiveness behavior is a separate pre-existing surface (out of T4
scope; Zig accepts `switch (b) { true => ..., false => ... }`); the `true`/`else`
spelling keeps this fixture on §4's import-selection axis. Observation recorded
here; not a T0 deliverable.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`, `-ffast --dump-c89`)
- dump rc=0, 6 `.c` — NEITHER `a_*` NOR `b_*` module emitted (import_expr in
  switch prongs dropped).
- gcc `-c` of every emitted `.c`: rc 0 (the broken call is an implicit
  declaration under the binding `-Wno-implicit-function-declaration` flag-set —
  note the corpus classifier is compile-only and would bucket this OK).
- `sh <out>/build_target.sh linux <out>/prog`: **rc 1** — LINK FAIL:
  `undefined reference to 'zT_1'` from `zF_EA90E208_main` (emitted
  `(void)zT_1();` — the `impl.ping()` call through the unresolved import
  value). No runnable program pre-fix.

## Expected classification
- RED pre-fix: corpus class **OK** (compile-only classifier; gcc `-c` clean) but
  the binary cannot LINK — recorded as the fixture's red (link-fail). This is
  the one T0 fixture whose red is invisible to `scripts/corpus/classify`; the
  class file carries no mover risk from it either way.
- After T4 (conditional `@import` resolution): `impl` = live module; stdout
  `b ping\ncond import switch ok\n` (linux) / `a ping\ncond import switch ok\n`
  (`-osw`), rc 0, links clean → class stays **OK**, program becomes runnable.
  Goldens captured by T4 at fix time (GREEN contract in main.zig header).

## Why no expected.txt/expected.rc
No runtime golden is measurable pre-fix (link fail). zT_missing_fwd_xmod
defect-repro shape (NOTES + sources). T4 captures goldens at fix time.
