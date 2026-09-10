# User-Facing Emission + Companion Build Scripts — Design

**Status:** FINALIZED (Task-1 feasibility findings folded in, 2026-09-10; operator-approved)
**Date:** 2026-09-10
**Plan:** `docs/superpowers/plans/2026-09-10-user-facing-emission-plan.md`

## 1. Problem

Using zig1 today is high-friction for a new user:

- **Usable output is gated behind a debug flag.** `sf/src/main.zig:824` — `phase_C89Emission` does `if (!ctx.cli.dump_c89) return;`. Without `--dump-c89`, `zig1 prog.zig` emits nothing. The flag is a debug tool, not a user contract.
- **No companion build script.** zig1 has `emitBuildTargetSh/Bat/OwcBat` in `sf/src/c89_emit.zig`, but they are **dead code** (never called; they hardcode the stale `main.c` root filename and a 3-file link line). The user must hand-roll the link line (runtime set, include path, platform libs).
- **Heavyweight std.** `sf/src/std.zig` re-exports `net` unconditionally, so every bare `@import("std")` program emits `std_net` and — under `-osw` — requires `-lwsock32` even for a stdio-only program. No module pruning exists.
- **Headers live in the compiler source tree.** Emitted C references `zig_compat.h`, `zig_runtime.h`, `net_prelude.h` (in `sf/src/include/`), which are not part of a user's view. The user must discover and `-I` the source tree.

Net effect: the user needs a multi-page manual to link a hello-world.

## 2. Vision

The compiler's output contract is: **emit the generated code for the chosen backend, plus a companion build script that shows how to use it.** The script is *recommended and complete* — the user may run it as-is or rewrite/adapt it to their flow. This contract is **backend-general**: a future asm / lisp / python backend emits *its* generated code + a companion "this is how to use the generated code" script, same shape. The C89 backend is the first instance.

## 3. Scope (this plan, C89 backend)

1. **Default emission.** `zig1 -o DIR prog.zig` (no debug flag) emits the multi-module C89 tree. `--dump-c89` becomes a debug alias.
2. **Needed-only modules.** Emit only modules reachable from the program, so a stdio-only `@import("std")` program emits no `std_net` and needs no `-lwsock32`.
3. **Self-contained output dir.** Copy the runtime/platform headers + runtime sources into `DIR`, so `-I .` + compiling every `.c` in `DIR` suffices — independent of where the compiler lives.
4. **Companion build scripts.** Generate `build_target.sh` (gcc linux / i686-w64-mingw32-gcc windows), `build_target.bat` (MSVC `cl`), `build_owc.bat` (OpenWatcom `wcc386`/`wlink`), each compiling every emitted `.c` and linking with the correct target libs (`-lwsock32` iff `std_net` emitted).

## 4. Non-goals

- **Auto-invoking** the C toolchain / linking a binary. The user runs the companion script.
- Non-C89 backends (the *contract* is designed to generalize; implementation is future work).
- Changing `std.zig`'s re-export set — the heavy-std issue is solved at **emission** (pruning), not by editing the std surface.
- Retiring `--dump-c89` entirely (kept as a debug alias).

## 5. Design

### 5.1 Emission default
`phase_C89Emission` (`sf/src/main.zig:822-824`) runs whenever an output dir is set; the `if (!dump_c89) return;` gate is removed (`--dump-c89` retained as a debug alias; with no `-o` the no-flag run still writes only `.zig1_*.tmp`). Emission is already multi-module (`main_<HEX8>.c` + per-module `.c/.h` + `zig_special_types.h`); no per-file naming change. The default-emission + prune work co-locates at the existing LIR scan in the emission phase (`main.zig:855-890`), not a separate pipeline phase (Task-1 decision 3).

### 5.2 Needed-only module emission (reachability prune)
A pre-emission pass computes the set of modules reachable from the root program and emits only those. Reachability follows **module-level LIR value references** — the `module_id` on `call`/`call_direct`/`tail_call`/`func_ref`/`load_global`/`store_global` operands plus the defining `LirFunction`/`LirSlot`/`ModuleGlobalDecl` module — **not** mere `@import`/re-export edges, so `std.zig`'s `pub const net = @import("std_net.zig")` does not keep `net` alive unconditionally (Task-1 decision 2; function-level pruning is only a fallback). The prune is applied at the emission LIR scan (`main.zig:855-890`), and `emitModuleInitCalls` (`c89_emit.zig:2708`) is restricted to reachable modules (decision 5). **Header dependency must follow the same value-ref graph, not import edges:** a module's emitted header must include the headers of every module it value-references, because cross-module mangled function prototypes live only in the callee's header (a module `A` calling `zF_<hash>_fn` from `B` must `#include "B.h"` even when no import edge points there); filtering only import-edge `dep_mod_ids` at `c89_emit.zig:2412-2422` is insufficient (MUST-FIX; Task-1 report Step 4 item 1, evidence `stdlib_debug_xmod`).

### 5.3 Self-contained output dir
The emit phase writes into `DIR`: all reachable module `.c/.h`, `zig_special_types.h`, `zig_compat.h`, `zig_runtime.h`, `net_prelude.h`, `zig_runtime.c`, `zig_pal.c`, `c_exit.c`, plus the companion scripts. **Sourcing = embed the canonical bytes** of `sf/src/include/*` and `sf/src/c_exit.c` in the compiler as Z98 string constants, with a byte-equality gate against the on-disk canonical files in the test suite (Task-1 decision 1). The dead `emitZigPalC`/`emitZigRuntimeC` mirrors must NOT be revived verbatim — they are stale relative to `sf/src/include` (missing `errno.h` + `pal_get_default_lib_path`, different runtime body); Task 4 embeds canonical bytes and adds the equality gate.

### 5.4 Companion build scripts
Revive + modernize the three dead `emitBuildTarget*` templates (which hardcode the stale root `main.c`). Each script:
- compiles the **compiler-enumerated** emitted `.c` list (decision 6; runtime sources last so symbols resolve) with the target compiler/flags,
- links them with the target's runtime needs + platform libs,
- adds `-lwsock32` **only when `std_net` was emitted** (predicate: any emitted module's `c_includes` names `net_prelude.h`),
- emits `build_target.sh` always, and the `.bat` (MSVC `cl`) / OpenWatcom scripts only on the windows target `-osw` (decision 7, per this section),
- targets a default output binary name `prog`/`prog.exe`, overridable (decision 8).

### 5.5 Companion-script contract (backend-general)
Define the companion script as a first-class compiler output for any backend: a human-readable, directly-runnable "how to build/run the generated code" artifact, not a hidden implementation detail. C89 is the reference implementation; the interface (name/location/role) is chosen so future backends reuse it.

### 5.6 The feasibility investigation (Task 1) — COMPLETE
Task 1 was a **record-only** investigation (report `.superpowers/sdd/task-EMITEMIT-report.md` `## Task 1`), finalized via operator-approved amendments on 2026-09-10. It resolved: the emit pipeline hook; the exact output file set + sourcing mechanism for headers/runtime; the reachability graph + module-level prune + fixed-point impact; `@cInclude`/`net_prelude.h` resolution and confirmation that pruning net removes the `-lwsock32`/`net_prelude.h` dependency (reproduced); toolchain flag sets for gcc/mingw/MSVC/OpenWatcom multi-module; and how linux-vs-windows target selection reaches the script generator.

## 6. Testing / gates

- **Default emission:** `zig1 -o DIR examples/z98/hello/main.zig` (no flag) emits the tree; the companion script builds+runs it (host), output byte-identical to the current `--dump-c89` path.
- **Pruning:** a stdio-only fixture's output dir contains no `std_net_*.c/.h`, and a net-using fixture does; `-osw` of the stdio program links **without** `-lwsock32`; the net program links **with** it. A caller of a value-referenced module `#include`s that module's header (the name-mangled prototype lives only there) — the strict `-Wall -Wextra` gate must show no implicit declarations.
- **Self-contained dir:** build succeeds from a copied output dir with no `-I` into the repo (other than `.`).
- **Scripts:** each target script builds a representative example where the toolchain is available (gcc/mingw on this box; MSVC/owc are emission-only checks unless a toolchain exists).
- **Regression:** golden 9/9 + matrix 21/21 byte-identity; corpus `-s0` zero-asymmetric vs the STDLIB-closed baseline; 4-MD5 rows; self-emission fixed point moves → N-hop closure + seed rotation at close.

## 7. Risks / unknowns (resolved by Task 1, 2026-09-10)

- Reachability prune correctness (must not drop a transitively-used module), and its fixed-point impact (a compiler-source change).
- Sourcing headers/runtime for the self-contained dir (embed vs path vs staging).
- MSVC/OpenWatcom multi-module correctness is unverifiable on this box beyond emission shape.
- Interaction with `emitBuildTarget*` being dead and the root module rename (`main_<HEX8>.c`).

Resolution (Task 1 report `## Task 1`, decisions 1-8): prune = module-level LIR value refs at the emission scan + value-ref header includes (MUST-FIX); sourcing = embed canonical bytes + equality gate (do not revive the stale mirrors); gcc/mingw/wine present, MSVC/OpenWatcom emission-only-checkable; the dead templates are revived to enumerate the compiler-known emitted file list against the real `main_<HEX8>.c` stem.
