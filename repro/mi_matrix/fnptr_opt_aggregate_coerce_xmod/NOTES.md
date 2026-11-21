# fnptr_opt_aggregate_coerce_xmod — D1 frontend-coercion repro (T0, RED before any fix)

## What it tests
Minimal reproducer A of `examples/torrent_example_defects.md` D1: assigning a
free function `fn (*void) ?Key` (Key = aggregate) to a fn-pointer struct field
of the same spelled type. Spec §2 bug 1 — `typeRegistryGetOrCreateOptional`
(`sf/src/type_registry.zig:814`) caches the composite only when the payload is
already laid out (`if (opt_state == 2) MapPut`), so the field's `?Key` and the
function's `?Key` can be two distinct ids, and `typeRegistryIsAssignable`'s
`fn_type` comparison (`:1830-1849`) reads `return_type` ids directly.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`, `-ffast --dump-c89`)
- dump rc=2, 0 `.c`.
- Exactly one level-0 diagnostic (census pinned in `expected_error.txt`):

  `main.zig:35:44: error[3000]: type mismatch in field initialization -- initializer type may not be compatible with the field type` (note: source: function / note: target: pointer)

## Expected classification
- RED pre-fix: **GREEN** (canonical classifier: 0 `.c` + `error[3000]` = documented
  green-guard bucket) — recorded as the fixture's expected-class before any fix.
- After T1 (canonical synthetic composites + structural fn_type comparison),
  measured 2026-10-16 on the seed-built T1 compiler `69cf0269933a8b943453fa7bce0e25cc`:
  dump rc 0, 6 `.c`, 0 diagnostics — the frontend flip lands (this report's
  `task-1-report.md` R4). But the corpus class is gcc-gated and the T2-owned
  emit-ordering bug still blocks gcc on this shape (fp-typedef emitted before
  the optional typedef it references — `zig_special_types.h:637` vs the
  `Opt_23` typedef `:744`, the exact Bug-2 error), so the measured T1 class is
  **FAIL**: the designed trajectory is **GREEN→FAIL at T1**, not GREEN→OK.
- **T2 owns BOTH flips and the golden capture** (this fixture FAIL→OK + `fnptr_opt_aggregate_emit_xmod`
  FAIL→OK, same ordering gap). At T2 the fixture runs: stdout `coerce sigint ok`
  / rc 0 → class **OK**, goldens captured then (`run_fixtures.sh --capture`;
  GREEN contract in main.zig header). No pre-existing corpus fixture may move.

## Why no expected.txt
No runtime golden is measurable until T2 makes the emitted C gcc-buildable
(see above). Shape matches the reject/build-fail fixtures (`expected.rc` +
`expected_error.txt` RED census, e.g. `error_union_capture_reject_xmod`;
`zT_missing_fwd_xmod` for the build-fail half) — `expected_error.txt` is
force-added (`git add -f`; `.gitignore` ignores `*.txt`). The T2 task captures
`expected.txt`/`expected.rc` at the flip.
