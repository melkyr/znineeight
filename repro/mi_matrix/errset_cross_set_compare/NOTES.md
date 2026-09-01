# errset_cross_set_compare — RED/GREEN  [Plan 3, Task P3-6, 2026-08-05]

## What it tests
Cross-set error identity comparison (the I3-5 / P3-6 defect). Both halves are
real-Zig-legal subset→superset coercions that the zig0 oracle REJECTS (type mismatch,
see `.superpowers/sdd/I3-5-errorcodes-report.md` §0) but real Zig accepts per the
langref — so the authority is runtime behavior matching real Zig, not zig0.

- **Cross anon→named:** `anon() !i32` returns `error.Bad`; assigned to `var x: E!i32`
  (inferred set coerced into named set `E`); catch compares `err == error.Bad`.
- **Cross named→named:** `fromB() B!i32` returns `error.Bad`; assigned to
  `var y: A!i32` (subset `B={Bad}` coerced into superset `A={Other,Bad}`); catch
  compares `err2 == error.Bad`. Decisive: per-set ordinals miscompare even between two
  NAMED sets when the same name sits at different ordinals.

## Measured result (RED)
Before P3-6 (per-set ordinals / raw name_id): both prints `0` (should be `1`).
- `probe_cross_miscompare`: produced `err = 23` (raw name_id of "Bad"), literal `0`
  (ordinal in `E`) → `23 == 0`.
- `probe_named_cross`: produced `err = 0` (ordinal in `B`), literal `1` (ordinal in `A`)
  → `0 == 1`.

## Measured result (GREEN, post-P3-6)
Both prints `1`. Every error code is now a program-global per-name registry code
(`#define ERROR_Bad <code>`, dense 1-based, first-use order), so `e1 == e2` compares
equal exactly when the names are equal. Run output: `11`.

## Fix
Task P3-6: `name_id → code` registry (`U32ToU32Map` on CompilerContext, `getOrAdd`
first-use order) + all error-code producers (sema literal/member sites, lower.zig
`error_literal`/`E.Bad` field-access/switch-case fallbacks) emit the registry code;
per-set ordinal path deleted; prologue emits `#define ERROR_<name> <code>`. See
`.superpowers/sdd/task-P3-6-report.md`.

## Expected classification
- **RED (pre-P3-6): FAIL** (runtime miscompare — the defect the repro guards).
- **GREEN (post-P3-6): OK** — dump rc=0, gcc-clean, links, runs, prints `11` (rc=0).
