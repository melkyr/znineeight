# Z98 std-lib extension program — Design

> **Status:** Approved 2026-09-17 (operator). Program-level spec. The
> per-plan specs below are this document; each implementation plan
> argues from it.

**Goal:** Grow the Z98 std lib from the 9-module set to the blueprint in
`sf/docs/std_lib_extension.txt` (6 layers, ~18 new/extended modules,
~60 fixtures), via one separation-audit plan and three layer-band
implementation plans — while keeping the compiler's own footprint flat.

**Source of record for module signatures:** `sf/docs/std_lib_extension.txt`
(the "blueprint"). This spec does not repeat the signatures; it fixes the
program structure, the conventions the plans inherit, the sequencing, and
the corrections to the blueprint.

## §1 Scope and finding

The compiler and the std lib are separate systems today. The std lib is
shipped as `.zig` source in the produced compiler's `lib/` and compiled
**in-process, on demand**, when a user program imports it. The compiler's
own import graph does not reach the std lib.

**Finding (preliminary; Task 0 proves it exhaustively):** a transitive
`@import` closure from `sf/src/main.zig` reaches 46 files and **zero** std
modules. The only two `@import("std")` sites in `sf/src`
(`c89_types.zig:16`, `semantic.zig:65`) are unreferenced dead files.
`pal.zig`, `diagnostics.zig`, and `util/*` import compiler internals only.
The emitted runtime is hand-written C in `sf/src/emit_support.zig`
(`zig_pal.c`/`zig_runtime.c`/`c_exit.c`/`net_prelude.h`). The build scripts
copy std into the *produced* compiler's `lib/`, never into the compiler.

The blueprint's §6 claim that the compiler self-compile "imports `std_io`,
`std_arena`, `std_net`, and `std_async` only" is **false**. Task 0 corrects
it.

## §2 Program structure

| Unit | Type | Scope | Plan |
|---|---|---|---|
| **Task 0** | I+F | Compiler↔std separation audit; delete the dead std-importing files; docs. Stands alone, first. | `2026-09-17-std-lib-task0-separation-plan.md` |
| **Plan A** | impl | L0-L2 foundation: `std_bits`, `std_os`, `std_time`, `std_debug` ext, `std_buf`, `std_str` ext. | `2026-09-17-std-lib-plan-a-foundation.md` |
| **Plan B** | impl | L3 resources + L6 capstone: `std_file`, `std_stdin`, `std_net` UDP ext, then `std_stream`. | `2026-09-17-std-lib-plan-b-resources-stream.md` |
| **Plan C** | impl | L4 + L5: `std_map`, `std_sort`, `std_heap`, `std_rle`; `std_crypto`, `std_parse`, `std_base64`, `std_hex`, `std_utf8`. | `2026-09-17-std-lib-plan-c-data-codecs.md` |

**Sequencing is binding:** Task 0 → Plan A → Plan B → Plan C. Each plan's
header carries a `Sequence:` line naming its predecessor and successor, so
the next plan to run is always discoverable from the plan just completed.
Within a plan, tasks follow the blueprint's construction order for that
band.

## §3 Task 0 — separation audit + dead-file removal (I+F)

**I (audit, no compiler change):**

1. Transitive import closure from `sf/src/main.zig`, per-file, proving zero
   std reachability (evidence: the closure file list + the import edges).
2. Prove `sf/src/c89_types.zig` and `sf/src/semantic.zig` unreferenced (no
   `@import`, no builder, no script, no test).
3. Enumerate the emitted runtime/support vs std boundary
   (`sf/src/emit_support.zig`, `zig_pal.c`, `zig_runtime.c`, `c_exit.c`,
   `net_prelude.h`).
4. Classify `sf/src/tests/*` and `scripts/self_compile/build_zig1_5.sh` /
   `scripts/seed/build_from_seed.sh`: which import std, and whether they
   are "the compiler".
5. Search-path / `-I` / `lib/` logic: does the compiler hardcode std module
   names (import resolver; `repro/mi_matrix/std_import_bare_xmod`)?
6. `sf/src/std.zig` re-export graph vs `main.zig`: confirm orthogonal.
7. **Outcome A** (coupling found): a separation design — a pre-compile
   std-to-C pass with the run-twice model. **Outcome B** (expected): the
   docs update in the F step.

**F (delete + docs):**

- Remove `sf/src/c89_types.zig` + `sf/src/semantic.zig` (and the stale std
  import in `sf/src/tests/mud_full.zig` if the audit proves it dead), only
  after the audit proves nothing builds them. The fixed point must NOT move
  (they are unreachable); if it moves, STOP.
- Correct the blueprint's §6 compiler claim.
- Record the true separation property in `docs/sf/QUICK_REF.md`,
  `sf/docs/tech_docs/*`, and `README.md` wherever they assert the
  compiler↔std relationship.

**Gate:** fixed point unmoved; corpus class-identical; `check_emit_support`
5/5; self-compile rc=0 / 0 err / 0 PANIC.

## §4 Plan scope (A/B/C)

Each plan implements one blueprint layer band. One task per module (or a
small same-shape batch), each task = the blueprint's exact signatures for
that module + its R7 fixtures + the §6 gates. Module completion requires
its fixtures GREEN and the dependency-graph check passing.

- **Plan A (L0-L2)** validates the layering rule and the arena rule before
  anything depends on them. No L3+, no async.
- **Plan B (L3 + L6)** is where R4 (the `*Async` flavor) and C2
  (`std.async.wait`; no `tick`/`waitFor` in std) are exercised.
  `std_stream` is the only module that imports `std.async` transitively; a
  program that does not use `std_stream` must not link the async runtime
  (C3). Plan B carries a graph assertion for this.
- **Plan C (L4 + L5)** imports L0-L2 only and is independent of Plan B.

## §5 Conventions (binding; inherited from the blueprint)

- **R1 — Arena.** Every allocating function takes `arena: *std.arena.Arena`
  first; never owns memory across calls; `OutOfMemory` in every allocating
  function's error set.
- **R2 — Errors.** One error set per module, at the top of the file.
  Cross-module translation at the call site. No `catch unreachable` in std.
- **R3 — Imports.** Strict direction: lower layers only, never siblings,
  never higher. One-pass module-level import-graph check.
  **Correction (operator, 2026-09-17):** the current `std.zig` re-export
  set is authoritative — `std.zig` re-exports
  `io/arena/str/mem/math/debug/net/async`. The blueprint's R3 text ("core
  L0-L3 only") is corrected to match; `async` stays re-exported.
- **R4 — Coroutines.** Three flavors where all three are meaningful: pure
  (`fn foo(...) T`), sync (`fn read(...) !usize`), async
  (`fn readAsync(...) !usize`, same signature + `Async` suffix, same
  module). No transitive coloring.
- **R5 — Single-threaded.** No locking/atomics/concurrency.
- **R6 — Determinism.** No output may depend on addresses, the wall clock,
  or the PID unless the contract says so. `-fsafe`'s `0xAA` fill is not a
  contract.
- **R7 — Fixtures.** Every public function gets at least one
  `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixture. A module is
  complete when its fixtures are GREEN and the dependency-graph check
  passes.
- **§6 correction.** "The compiler imports no std module; its fixed point
  is independent of the std lib." (replaces the false blueprint claim).

## §6 Gates (per blueprint §5, reusing the existing harness)

- Coverage: every public function has a fixture.
- Determinism: run each fixture 3×; C89 emission md5 identical.
- Safety: each fixture runs under `-fsafe` and `-ffast`; behavior identical
  except where `-ffast` is documented to differ.
- Arena gate (allocating modules): a fixture exhausts the arena; the
  function returns `OutOfMemory`; no memory written outside the arena.
- Crypto gate: RFC/FIPS normative vectors.
- Async gate (L6): fixtures suspend at least twice per call.

The existing classifier (`OK`/`FAIL`/`GREEN`/`GCCFAIL`/`ICE`/`CRASH`)
applies unchanged. `repro/mi_matrix/EXPECTED_FAIL.md` is bumped once per
plan at its closeout.

## §7 Distribution

`MANIFEST.txt` lists every module with its md5. The core re-exported set is
unchanged (the 8 names above). Higher layers are imported by path. The
compiler's `lib/` gains the new `.zig` modules; the self-compile fixed point
stays flat because the compiler imports none of them — the property Task 0
proves.

## §8 Risks

- **`std_debug` TrapContext (L1)** adds `TrapContext` + `setTrapHandler` +
  `defaultTrapHandler`, which touch the emitted-runtime trap handler — a
  surface that may cross the compiler↔std boundary Task 0 audits. Plan A
  resolves the boundary explicitly.
- **Win32-specific L1** (`QueryPerformanceCounter`, `CreateFileA`,
  `GetFileSizeEx`) needs `-osw` + wine evidence, not just linux.
- **R4 `*Async` discipline.** A sync function accidentally calling a
  `*Async` sibling would pull the async runtime into programs that do not
  use it (C3 violation). Plan B asserts this in the import graph.
- **Fixture volume (~60 dirs).** Corpus growth per plan; each plan
  re-baselines `EXPECTED_FAIL.md` once at closeout.

## §9 Out of scope

The consuming artifacts themselves (debugger, BitTorrent client, game
libraries) — only the std modules they drive are in scope. The blueprint's
explicit §2 exclusions (image/compression formats, graph algorithms,
application math, Win32/DirectX/COM declarations, regex, container types
beyond the three maps and one heap, a testing framework) are out of scope.

## §10 Plan index (next-plan tracking)

1. `docs/superpowers/plans/2026-09-17-std-lib-task0-separation-plan.md` — Task 0 (I+F). **First to execute.**
2. `docs/superpowers/plans/2026-09-17-std-lib-plan-a-foundation.md` — L0-L2.
3. `docs/superpowers/plans/2026-09-17-std-lib-plan-b-resources-stream.md` — L3 + L6.
4. `docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md` — L4 + L5.

Each plan's header `Sequence:` line names its predecessor and successor;
the successor plan is the "next plan to follow up" for the plan just
completed.
