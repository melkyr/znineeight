# conditional_import_lazy_xmod — §4/C1b: true Zig laziness for dead-arm `@import` (Amendment 2)

## What it tests
An untaken arm's `@import` NEVER loads its file (Zig never opens it):
`const lazy_if = if (false) @import("missing.zig") else @import("real.zig");`
(and the `switch (false) { true => @import("missing.zig"), else =>
@import("real.zig") }` form) must be SILENT about the missing dead-arm file
(no `error[3048]` — that diagnostic is live-arm-only), never parse-register or
emit it, and select `real.zig`. `missing.zig` deliberately does not exist.

Mechanism (C1b): `parserParseImportExpr` skips `moduleRegistryResolveImport`
inside a comptime-untaken `if`/`switch` arm (`dead_import_depth`, folded by
`parserFoldComptimeBool` — literals, `!`/`and`/`or` compounds, zero-arg
`@isWindows()` with `ModuleRegistry.target_is_windows`, and already-parsed
immutable `const` bindings). Live imports resolve exactly as before.

## Measured RED (pre-C1b, T4 fixed point `e7099859f44e8050e7738be8545e8a58`)
```
/tmp/d1d2_t4/zig1_5_clean -ffast -o out main.zig
→ dump rc 2, 0 `.c`
  error[3048]: could not resolve imported file 'missing.zig'   ×2
```
Both dead-arm imports were parse-resolved eagerly (`parser.zig:780` pre-C1b),
so the missing file errored even though no arm can ever select it. Class
**FAIL** (frontend reject). `expected_error.txt`=`3048 2` + `expected.rc=2`
carry the RED census (T3 cond_if convention); the GOLDEN flip to OK is the
`expected.txt`/`expected.rc=0` capture below.

## Expected classification (post-C1b)
- dump rc 0, NO error[3048]; only `real_*` emitted (plus `std_io_*`/support);
  `missing.zig` never read, never registered, never emitted.
- stdout `real ping\nreal ping\ncond import lazy ok\n` (linux and `-osw` —
  `false` is target-neutral), rc 0, deterministic 3x → class **OK**
  (designed FAIL→OK flip).

## T4 fix round flip (2026-10-17) — designed FAIL→OK
Measured on the fix-round build (seed-built `/tmp/d1d2_t4/zig1_5_clean` after
C1b+C2, fixed point recorded in task-4-report.md §Fix round):
- linux: dump rc 0 silent; `build_target.sh linux` clean; run
  `real ping\nreal ping\ncond import lazy ok\n` rc 0 (3x byte-identical).
- `-osw`: same (target-neutral condition) — cross-checked.
- Goldens captured at the flip (`scripts/stdlib/run_fixtures.sh --capture`).

## Companion manual probe (target polarity, NOT this fixture)
`const impl = if (@isWindows()) @import("missing.zig") else
@import("real.zig");` — on linux: silent + `real ping` (dead arm never opens
`missing.zig`); on `-osw`: `error[3048]` rc 2 (the LIVE arm's import must
resolve — target-selected laziness, not blanket suppression). Recorded in
task-4-report.md §Fix round; not fixture-pinned because the `-osw` half is an
intentional reject.
