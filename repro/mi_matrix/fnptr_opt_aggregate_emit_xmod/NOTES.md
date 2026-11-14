# fnptr_opt_aggregate_emit_xmod — D1 emit-ordering repro (T0, RED before any fix)

## What it tests
Minimal reproducer B of `examples/torrent_example_defects.md` D1: merely
DEFINING `contract.Console` (fn-pointer field `readKey_fn: fn (*void) ?Key`,
never assembled) is enough. Spec §2 bug 2 — the fn-pointer typedef (whose
return type is the optional composite) is emitted before/without the optional
typedef it references; D8-class gap for `optional_type` (P2 `typeHasForwardDecl`
edge suppression vs the per-kind emit dispatch at `sf/src/c89_emit.zig:1440-1453`).
T2 pins which of the two is the gap, repro-driven.

## Measured pre-fix (2026-10-16, seed-built `/tmp/d1d2_build/zig1_5_clean`, md5 `f18b69ece1917bf970a036b276e5e403`, `-ffast --dump-c89`)
- dump rc=0, 6 `.c` emitted (`main_*.c`, `std_io_*`, `std_net_*`, `zig_pal.c`,
  `zig_runtime.c`, `c_exit.c`) — frontend accepts.
- gcc `-c` (binding flag-set, `-I sf/src/include`) of `main_B1CC0B32.c` FAILS,
  via its header chain (`main_*.h` → `zig_special_types.h`):

  `zig_special_types.h:663:29: error: expected declaration specifiers or '...' before '*' token`

  (byte-for-byte the defect entry's symptom; the subsequent
  `unknown type name 'zT_..._FP_zT_..._Opt_'` follows).

## Expected classification
- RED pre-fix: **FAIL** (emitted `.c` present but gcc-invalid).
- After T2 (composite typedefs emitted + ordered before every spelling
  reference): all emitted `.c` compile clean → class **OK** (this NEW fixture's
  designed FAIL→OK flip). GREEN contract (main.zig header): stdout
  `fnptr emit ok` / rc 0 — goldens captured by T2 at fix time.

## Why no expected.txt/expected.rc
No runtime golden is measurable pre-fix (the build dies in gcc). Defect-repro
shape matches `zT_missing_fwd_xmod` (NOTES.md + sources, no goldens; expected
classification recorded). T2 captures the goldens when the fixture turns green.
