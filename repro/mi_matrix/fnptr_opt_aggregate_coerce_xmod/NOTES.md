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
- After T1 (canonical synthetic composites + structural fn_type comparison):
  compiles and runs, stdout `coerce sigint ok` / rc 0 → class **OK** (this NEW
  fixture's designed GREEN→OK flip; no pre-existing corpus fixture may move).
  Goldens for the run are captured by T1 at that point (`run_fixtures.sh
  --capture`; GREEN contract in main.zig header) — no runtime golden is
  measurable pre-fix because the frontend rejects.

## Why no expected.txt
The program cannot build with the pre-fix compiler (frontend reject), so no
runtime stdout/rc exists to freeze. Shape matches the reject-census fixtures
(`expected.rc` + `expected_error.txt`, e.g. `error_union_capture_reject_xmod`);
`expected_error.txt` is force-added (`git add -f`; `.gitignore` ignores `*.txt`).
