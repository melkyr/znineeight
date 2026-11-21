# switch_on_error_named — switch exhaustiveness over a named error set (P3-5, 2026-08-05)

## What it tests
`switch (err)` over a **named** error-set error value caught via `catch |err|`.
Named set `const E = error{ Bad, Other }`; `f() E!i32` returns `error.Bad`.
Expected runtime print: `1` (the `error.Bad` prong).

## Upstream defect (fixed by P3-5)
Switch-case collection (`lower.zig:2919-2934` expr site + `lower.zig:3644-3658` stmt site)
handled only `int_literal` and `enum_literal` case nodes; an `error_literal` case node
(`error.Bad => ...`) fell through to `continue` → zero SwitchCase entries → emitted
`switch (err) { default: ... }` always takes `default`. P3-5 adds the `error_literal` branch
mirroring `enum_literal` (value via `enum_value_table` ordinal when present, else raw name_id)
at BOTH sites, plus a companion sema fix (`semanticAnalyzerResolveSwitchExpr`) that resolves
`error_literal` case nodes against the switch cond error set so `enum_value_table` gets the
ordinal for named sets.

## Measured result (recorded 2026-08-05, /tmp/p35base = pre-fix, /tmp/p35fix2 = post-fix)
- Pre-fix (RED): prints `0` (else/default branch taken — wrong; expected `1`).
  Emitted C: `switch (err) { default: goto z_bb_6; }` — zero case entries.
- Post-fix (GREEN): prints `1` (matching prong taken — correct).
  Emitted C: `case 0: goto z_bb_4; case 1: goto z_bb_5; default: goto z_bb_6;`
  (ordinal 0 = `error.Bad`, ordinal 1 = `error.Other`; produced error carries ordinal `0`).
- dump rc=0, 1 `.c`, gcc-clean, run rc=0 both before and after.
- zig0 oracle: prints `1` (`case ERROR_Bad:` / `case ERROR_Other:`) — matches post-fix behavior.
- Classifies OK per the QUICK_REF corpus gate in both states (runtime-gap-now-fixed; the defect
  was runtime-wrong, not a compile failure) — see EXPECTED_FAIL.md P3-5 section.
