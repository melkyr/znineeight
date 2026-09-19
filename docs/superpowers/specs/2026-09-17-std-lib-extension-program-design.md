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
| **Plan A** | impl | L0-L2 foundation: `std_bits`, `std_os`, `std_time`, `std_debug` ext, `std_buf`, `std_str` ext; plus the optional-fn-pointer compiler-defect I/F pair (Tasks 4b-I/4b-F/4c) and the `-ffast` undefined slice/optional/struct-field compiler-defect I/F pair (Tasks 6b-I/6b-F). | `2026-09-17-std-lib-plan-a-foundation.md` |
| **Plan B** | impl | L3 resources + L6 capstone: `std_file`, `std_stdin`, `std_net` UDP ext, then `std_stream`. | `2026-09-17-std-lib-plan-b-resources-stream.md` |
| **Plan C** | impl | L4 + L5: `std_map`, `std_sort`, `std_heap`, `std_rle`; `std_crypto`, `std_parse`, `std_base64`, `std_hex`, `std_utf8`. | `2026-09-17-std-lib-plan-c-data-codecs.md` |
| **Plan D** | impl | Network async: non-blocking socket primitives in `std_net` (`recvNonBlocking`/`sendNonBlocking`/`setNonBlocking`), `std_stream.SocketLineReader`, `MsgReader`, and an optional `std.async.wait(handle)`. Deferred from Plan B (Model C ruling). | `2026-09-18-plan-D-network-async.md` |

**Sequencing is binding:** Task 0 → Plan A → Plan B → Plan C. Each plan's
header carries a `Sequence:` line naming its predecessor and successor, so
the next plan to run is always discoverable from the plan just completed.
Within a plan, tasks follow the blueprint's construction order for that
band.

**Plan C L5 codec `decode` contract (operator ruling m1842).** The
`std_base64`/`std_hex` `decode` functions declare `errors OutOfMemory,
InvalidInput`; both modules' `encode` functions stay `OutOfMemory`-only.
`decode` (both modules) rejects malformed or whitespace input with
`error.InvalidInput`. An empty input is a VALID empty result (a length-0
slice, no error) and is distinct from an invalid one. This mirrors the
blueprint's `Contract:` line (git-ignored `sf/docs/std_lib_extension.txt`);
this spec is the durable, committed source of record.

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
- **Plan B (L3 + L6)** is where R4 (the `*Async` flavor) and C2 (no
  `tick`/`waitFor`/`waitAll` in std) are exercised. Under the operator's
  Model C ruling (`sf/docs/answerT4.txt`, m1449/m1451), Plan B's L6 is
  **file-only**: `std_stream.FileLineReader` with `readLineSync` (blocking)
  and `readLineAsync` (a separate chunked implementation that yields via the
  `@asyncSuspend` builtin once per incomplete read). `SocketLineReader`,
  `MsgReader`, the non-blocking socket primitives, and `std.async.wait(handle)`
  are deferred to Plan D. `std_stream` is the only module that pulls in the
  async facility; a program that does not use `std_stream` must not link the
  async runtime (C3). Plan B carries a graph assertion for this.
- **Plan C (L4 + L5)** imports L0-L2 only and is independent of Plan B.

## §5 Conventions (binding; inherited from the blueprint)

- **R1 — Arena.** Every allocating function takes `arena: *std.arena.Arena`
  first; never owns memory across calls; `OutOfMemory` in every allocating
  function's error set.
- **R2 — Errors.** One error set per module, at the top of the file.
  Cross-module translation at the call site. No `catch unreachable` in std.
- **R3 — Imports.** Strict direction: lower layers only, never siblings,
  never higher. One-pass module-level import-graph check.
  **Correction (operator, 2026-09-18):** the current `std.zig` re-export
  set is authoritative — `std.zig` re-exports
  `io/arena/str/mem/math/debug/net/async/bits/os/time/buf` (12 names; the
  set grew from the original 8 through Plan A). The blueprint's R3 text
  ("core L0-L3 only") is corrected to match; `async` stays re-exported.
  **Exception 1 (operator, m1243):** `std_debug.backtrace(ctx, out:
  *std.buf.Buf)` (blueprint §3 L1) consumes `std_buf`, so `std_debug` (L1)
  imports `std_buf` (L2) for this one function. It is cycle-free (`std_buf`
  imports only `std_arena`) and sanctioned because the blueprint fixes the
  public API name/signature.
  **Exception 2 (operator, 2026-09-18):** `std_debug` (L1) also imports the
  core `std_io` module (no imports of its own) for `log`/`writeCoreDump`.
  It is cycle-free and operator-authorized; no other L1→L2 import is
  permitted.
  **Exception 3 (Plan B final review, 2026-09-18):** `std_stdin` (L3) imports
  `std_file` (L3) for the stdin-handle read path — it wraps the stdin
  fd/HANDLE in a `std_file.File` so the win32/POSIX handle logic is shared and
  the compiler-PAL `pal_file_*` surface stays untouched
  (`sf/src/std_stdin.zig:14`). It is cycle-free (`std_file` imports only
  `std_arena` + its private `std_file_pal`) and sanctioned by the Plan B plan
  Task 2 "Consumes: `std_file`, `std_file_pal`" line. No other L3→L3 import is
  permitted.
- **R4 — Coroutines.** Three flavors where all three are meaningful: pure
  (`fn foo(...) T`), sync (`fn read(...) !usize`), async
  (`fn readAsync(...) !usize`, same signature + `Async` suffix, same
  module). No transitive coloring.
  **Model C clarification (operator, m1449/m1451).** Z98 is
  cooperative-yield: the caller drives `std.async.tick`; there is no
  executor and no `poll` loop. A `*Async` function is a **separate
  implementation** from its sync sibling — it does its own I/O and calls the
  `@asyncSuspend` builtin when it has nothing more to do right now; it is not
  a wrapper over the sync path. `std_stream.readLineAsync` reads a bounded
  chunk and yields once per incomplete read.
  **Asset-loading idiom (the Model C answer to "background loading").** The
  frame loop runs every tick and draws a *placeholder*; a loading coroutine
  reads one chunk per tick and yields, then swaps in the decoded asset and
  sets a ready flag. The render path never waits — it draws the placeholder
  until the flag flips. Chunk size is the tuning knob (bigger = faster load,
  longer per-tick pause; 64 KB is a reasonable default for a PII/local disk).
  There is no "wait for I/O" anywhere in the model, only "do work, yield,
  do more next tick."
- **R5 — Single-threaded.** No locking/atomics/concurrency.
- **R6 — Determinism.** No output may depend on addresses, the wall clock,
  or the PID unless the contract says so. `-fsafe`'s `0xAA` fill is not a
  contract.
- **R7 — Fixtures.** Every public function gets at least one
  `repro/mi_matrix/stdlib_<module>_<name>_xmod` fixture. A module is
  complete when its fixtures are GREEN and the dependency-graph check
  passes.
- **R7b — Usage programs.** Each layer band ships usage programs under
  `stdlib_test/` — real programs that compose the band's modules in the
  intended workflows, each with a deterministic stdout contract, compiled
  and run under the same gates as a fixture (3× emission md5, `-fsafe`/`-ffast`
  parity). A module is complete only when its R7 unit fixture AND its band's
  usage programs are GREEN.
- **R8 — PAL boundary.** The std lib never edits
  `sf/src/pal.zig`/`sf/src/include/zig_pal.c`/`sf/src/emit_support.zig`,
  except for the authorized compiler-graph changes: the per-OS prelude
  headers in Plan A Tasks 2-3, the `std_debug` trap hook in Task 4, the
  optional-fn-pointer C-emission fix in Plan A Task 4b-F (operator ruling
  m1243; Task 4c is std-only), and the `-ffast` undefined
  slice/optional/struct-field C-emission fix in Plan A Task 6b-F (operator
  ruling m1277).
  Per-OS primitives live in `sf/src/std_<module>_pal.zig`, a private
  implementation unit of that module (exempt from the R3 sibling rule),
  using `@cInclude` + `extern` declarations and `@isWindows()` guards. The
  compiler PAL carries only what the compiler itself imports.
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
the 12 names above
(`io/arena/str/mem/math/debug/net/async/bits/os/time/buf`; operator ruling
2026-09-18 authorized the growth from 8). Higher layers are imported by path.
The compiler's `lib/` gains the new `.zig` modules; the self-compile fixed point
stays flat because the compiler imports none of them — the property Task 0
proves. `std_stream` (L6) ships as `FileLineReader` only in Plan B;
`SocketLineReader` and `MsgReader` are **deferred to Plan D** and are not part
of the Plan B distribution. `stdlib_test/` is a corpus container: the harness
(`scripts/corpus/list_corpus_dirs.sh`) enumerates every immediate subdir of
`stdlib_test/` as a usage program (container rule D), distinct from the
per-function `repro/mi_matrix/` fixtures.

## §8 Risks

- **`std_debug` TrapContext (L1) — RESOLVED (operator, 2026-09-17).** The
  trap hook is an authorized compiler↔std crossing: `zig_pal` gains a
  `static void(*g_trap_handler)(TrapContext*)`, `pal_trap()` invokes the
  installed handler (register capture on GCC/x86, zero-filled context
  elsewhere) and then raises the divergence trap (`int3`/SIGTRAP on
  MSVC/Watcom/x86-GCC, `pal_abort()` fallback), `emit_support.zig` emits
  the setter, and `std_debug.zig` declares the extern and wraps it. It
  moves the fixed point. No compiler-graph change beyond the four
  authorized ones (this hook, the per-OS preludes, the optional-fn-pointer
  fix below, and the `-ffast` undefined slice/optional/struct-field fix
  below) is permitted in the program.
- **Optional fn-pointer / optional `*void` C emission — RESOLVED (operator,
  m1243).** The landed `std_debug.setTrapHandler` diverged from the
  blueprint's `?fn(*TrapContext) void` because `?fn`/`?*void` was believed
  not to lower; the reviewer's probe shows it DOES lower but emits
  `-Wincompatible-pointer-types` — valid Zig compiling to incorrect C is a
  compiler bug. Plan A adds the I/F pair Task 4b-I (pin with
  `repro/mi_matrix/opt_fnptr_extern_xmod`/`opt_void_extern_xmod`, classify,
  present the fix surface) → Task 4b-F (fix; fixed point moves), then Task 4c
  reverts `setTrapHandler` to the blueprint `?fn` signature and drops the
  redundant `clearTrapHandler` (null-install is `setTrapHandler(null)`).
- **`-ffast` undefined slice/optional/struct-field emission — RESOLVED
  (operator, m1277).** The pre-existing `-ffast` defect where an undefined
  `[N][]const u8` (and nested undefined optional/struct/tagged-union fields)
  emitted incorrect C is fixed at the pinned locus in Plan A Task 6b-F. It
  is the fourth authorized compiler change and moves the fixed point.
  Pinned by `repro/mi_matrix/undefined_slice_array_xmod` (Task 6b-I) with
  the off-corpus `-fsafe`/default control
  (`known_excluded/undefined_slice_array_safe_xmod`).
- **L1 OS externs — RESOLVED (operator, 2026-09-17).** `std_os`/`std_time`
  MUST NOT wrap the compiler PAL. They own std-side PAL modules
  (`std_os_pal.zig`/`std_time_pal.zig`) built with `@cInclude`+`extern`+
  `@isWindows()` (the `std_net.zig` pattern); per-OS C prototypes come from
  the authorized `std_os_prelude.h`/`std_time_prelude.h` preludes (the
  `net_prelude.h` analog). The compiler's cost is what it imports; the
  library's cost is what emits.
- **Win32-specific L1** (`QueryPerformanceCounter`, `CreateFileA`,
  `GetFileSizeEx`) needs `-osw` + wine evidence, not just linux.
- **Per-OS C prototypes — RESOLVED (operator, 2026-09-17: option B).**
  win9x `GetTickCount`/`QueryPerformance*`/`GetCurrentDirectoryA` need
  `<windows.h>`; linux `getcwd`/`gettimeofday` need `<unistd.h>`/
  `<sys/time.h>`. A single unconditional `@cInclude` cannot serve both.
  Plan A adds `net_prelude.h`-style per-OS prelude headers
  (`std_os_prelude.h`/`std_time_prelude.h`: canonical header +
  `emit_support.zig` emitter + conditional emission in `c89_emit.zig` + a
  `check_emit_support.sh` entry) — an authorized compiler-graph change that
  moves the fixed point.
- **R4 `*Async` discipline.** A sync function accidentally calling a
  `*Async` sibling would pull the async runtime into programs that do not
  use it (C3 violation). Plan B asserts this in the import graph.
- **Fixture volume (~60 dirs).** Corpus growth per plan; each plan
  re-baselines `EXPECTED_FAIL.md` once at closeout.
- **Network async — SCHEDULED as Plan D (operator, m1449/m1451/m1927).** Z98 is
  Model C cooperative-yield, so there is no runtime-mediated wakeup. Plan D
  lands the network half of the `std_stream` two-reader surface; it is the
  capstone of the std-lib extension program. Module signatures (source of
  record, mirrored in `sf/docs/std_lib_extension.txt` §3 L3/L6):

  ```
  // std_net (L3)
  pub fn setNonBlocking(s: *Socket) NetError!void;
  pub fn recvNonBlocking(s: *Socket, buf: []u8) NetError!usize;
  pub fn sendNonBlocking(s: *Socket, buf: []const u8) NetError!usize;

  // std_stream (L6)
  const SocketLineReader = struct { src: *std.net.Socket, buf: []u8, pending: []u8 };
  pub fn initSocketLineReader(src: *std.net.Socket, buf: []u8) SocketLineReader;
  pub fn readSocketLineSync(lr: *SocketLineReader) !?[]u8;    // blocking
  pub fn readSocketLineAsync(lr: *SocketLineReader) !?[]u8;   // yields on error.WouldBlock

  const MsgReader = struct { src: *std.net.Socket, buf: []u8, pending: []u8 };
  pub fn initMsgReader(src: *std.net.Socket, buf: []u8) MsgReader;
  pub fn readMsgSync(mr: *MsgReader) !?[]u8;    // blocking: length-prefix frame
  pub fn readMsgAsync(mr: *MsgReader) !?[]u8;   // yields on error.WouldBlock
  ```

  `recvNonBlocking` returns `error.WouldBlock` when no data is ready and 0 at
  peer close. The `*Async` readers yield on `error.WouldBlock` and are
  re-driven on the next tick (Model C); the `Sync` forms block. `MsgReader`
  reads a length prefix, then the body. An optional `std.async.wait(handle)`
  needs an executor or a `poll()` loop and is Plan D Task 4 (optional). Plan B's
  `std_stream` is file-only (`FileLineReader`, `readLineSync` + `readLineAsync`).
  Recorded in `docs/superpowers/plans/2026-09-18-plan-D-network-async.md`.
- **Async frame-layout residual — DECLARED (Plan B Task 4 fix round 1).** A
  suspending function with a `while` loop that returns `!?[]u8` trips the
  P2/P3 async frame-layout size guard
  (`sf/src/async_frame_layout.zig:659`,
  `panic: async frame layout exceeds authoritative frame size`). The trigger is
  the **loop + error-union + optional-slice return** in one function;
  `std_stream.readLineAsync` works around it with the internal `awaitLine`
  scalar-status helper. Pinning it with an I/F fixture pair and fixing the
  layout is a recorded follow-up — the fix moves the fixed point and needs
  operator authorization. Declared in `repro/mi_matrix/EXPECTED_FAIL.md` v139.

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
5. `docs/superpowers/plans/2026-09-18-plan-D-network-async.md` — network async: non-blocking sockets in `std_net`, `std_stream.SocketLineReader`, `MsgReader`, optional `std.async.wait(handle)`. **Deferred from Plan B** (Model C ruling); not in the Task 0 → A → B → C sequence.

Each plan's header `Sequence:` line names its predecessor and successor;
the successor plan is the "next plan to follow up" for the plan just
completed.

**Completion (2026-09-19).** Task 0 → Plan A → Plan B → Plan C are COMPLETE;
the std-lib extension program's core bands are COMPLETE. The next executable is
Plan D (`2026-09-18-plan-D-network-async.md`, the network-async capstone:
non-blocking sockets in `std_net`, `std_stream.SocketLineReader`, `MsgReader`,
optional `std.async.wait(handle)`), followed by a Plan D test-hardening plan
(operator m1927). Plan C closeout:
`docs/superpowers/plans/2026-09-17-std-lib-plan-c-data-codecs.md` § "Next plan";
seed v39; fixed point `fc9198f6c1a24c92ec136e741c81c975`.
