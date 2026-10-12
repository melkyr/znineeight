# mod_silent_drop_xmod — D2 TRACKING REPRO (module drop does NOT currently reproduce)  [R1b, 2026-08-08]

## What it tests
A 3-module chain `main.zig → lib_b.zig → lib_a.zig`: `main` calls
`b.wrapper()`, which calls `a.helper()` in a deeper module. `lib_a.zig` is
only reachable transitively (not directly imported by `main.zig`). This is
the minimal shape hypothesized to exercise D2 (silent module drop) — the
MEM4-reported `json_parser` arena.c gap and the rogue_mud scenario/room
pattern.

## Measured result (2026-08-08, sf/build/out_release/zig1) — DOES NOT REPRODUCE
- dump rc=0; **lib_a_*.c IS emitted** (along with lib_b_*.c and main_*.c).
- gcc `-c` of each emitted `.c`: rc=0 (no compile errors).
- gcc link: rc=0; run rc=0.
- **The brief's expected failure (lib_a.c absent → `undefined reference to
  zF_*_helper`) does NOT occur on the current compiler.** 6 module-graph
  shapes were probed (linear chain, diamond, import-only chain, type-only,
  import cycle, const re-export, 4-deep chain) — every shape emits ALL
  modules. The module→`.c` emission loop (main.zig:760-823, driven by
  `moduleRegistryGetModules`) emits every registered module.

## Root-cause investigation for the corpus evidence
The two MEM4 D2 examples do NOT show a compiler module drop on the current
compiler:
- `json_parser`: `arena.zig` is NEVER `@import`ed (grep confirms) — it is an
  orphan file. The link failure is `arena_alloc_default` undefined, which
  exists only in the LEGACY `src/runtime/zig_runtime.c`, not
  `sf/src/include/zig_runtime.c` (json_parser/NOTES.md documents the
  legacy-runtime link workaround; it is a runtime-library path gap, not a
  module-emission gap).
- `rogue_mud`: all 20 modules emit .c; gcc link fails ONLY on the 5
  `plat_*` stubs (D4, out-of-scope platform layer), with NO module-symbol
  gaps.

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy: rc=0, emits **all 3 modules** (lib_a.c,
lib_b.c, main.c) — matching zig1's emission. Consistent with "no drop on
the current compiler".

## Expected classification
Currently **PASSES the corpus gate** (dump/gcc/link/run all rc=0). Kept as
a regression guard for D2: if the module→`.c` emission ever drops
transitively-imported modules, this repro flips to FAIL. The I2 task should
investigate whether D2 has a non-minimal trigger or whether the original
diagnosis (json_parser/rogue_mud) was a runtime-library issue mislabeled as
a compiler defect.
