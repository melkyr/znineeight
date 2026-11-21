# switch_on_error_anon — switch exhaustiveness over an anonymous error set (P3-5, 2026-08-05)

## What it tests
`switch (err)` over an **anonymous** (bare-`!`) error-set error value caught via
`catch |err|`. `f() !i32` returns `error.Bad`. Expected runtime print: `1` (the
`error.Bad` prong).

## Upstream defect (fixed by P3-5)
Same as `switch_on_error_named` — switch-case collection (`lower.zig:2919-2934` expr site +
`lower.zig:3644-3658` stmt site) dropped `error_literal` case nodes, so the emitted switch
always took `default`. Anonymous error literals carry the raw name_id as the C error code
(`lower.zig:1191-1206`); the P3-5 `error_literal` case branch resolves the value via
`enum_value_table` when present, else falls back to the raw name_id (matching the anon
error-code representation — the anon switch cond has no named error set, so no sema ordinal
resolution runs and the raw name_id path is taken).

## Measured result (recorded 2026-08-05, /tmp/p35base = pre-fix, /tmp/p35fix2 = post-fix)
- Pre-fix (RED): prints `0` (else/default branch taken — wrong; expected `1`).
  Emitted C: `switch (err) { default: goto z_bb_6; }` — zero case entries.
- Post-fix (GREEN): prints `1` (matching prong taken — correct).
  Emitted C: `case 23: goto z_bb_4; case 28: goto z_bb_5; default: goto z_bb_6;`
  (raw name_ids; produced error carries name_id `23` = `error.Bad`).
- dump rc=0, 1 `.c`, gcc-clean, run rc=0 both before and after.
- zig0 oracle: prints `1` (`case ERROR_Bad:` / `case ERROR_Other:`) — matches post-fix behavior.
- Classifies OK per the QUICK_REF corpus gate in both states (runtime-gap-now-fixed; the defect
  was runtime-wrong, not a compile failure) — see EXPECTED_FAIL.md P3-5 section.
