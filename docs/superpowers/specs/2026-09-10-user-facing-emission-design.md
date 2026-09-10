# User-Facing Emission + Companion Build Scripts — Design

**Status:** draft (Task-1 feasibility findings will refine §5–§7)
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
`phase_C89Emission` runs by default when an output dir is set; the `--dump-c89` gate is removed (flag retained as an alias). Emission is already multi-module (`main_<HEX8>.c` + per-module `.c/.h` + `zig_special_types.h`); no per-file naming change. Exact pipeline hook TBD by Task 1.

### 5.2 Needed-only module emission (reachability prune)
A pre-emission pass computes the set of modules reachable from the root program and emits only those. Reachability must follow *value references* (functions/globals actually used), **not** mere `@import`/re-export edges — otherwise `std.zig`'s `pub const net = @import("std_net.zig")` keeps `net` alive unconditionally. The mechanism (module-level prune, and whether function-level is needed/feasible) is **Task 1's primary investigation**.

### 5.3 Self-contained output dir
The emit phase writes/copies into `DIR`: all reachable module `.c/.h`, `zig_special_types.h`, `zig_compat.h`, `zig_runtime.h`, `net_prelude.h`, `zig_runtime.c`, `zig_pal.c`, `c_exit.c`, plus the companion scripts. How the compiler sources these (embed as constants vs read from a known install path vs a build-time staging step) is **Task 1's investigation**.

### 5.4 Companion build scripts
Revive + modernize the three dead `emitBuildTarget*` templates. Each script:
- compiles every `*.c` in the output dir (or an enumerated list) with the target compiler/flags,
- links them with the target's runtime needs + platform libs,
- adds `-lwsock32` **only when `std_net` was emitted**,
- is emitted only for the platform(s) selected (`-osl`/`-osw`; the `.bat`/owc scripts are target-specific).

### 5.5 Companion-script contract (backend-general)
Define the companion script as a first-class compiler output for any backend: a human-readable, directly-runnable "how to build/run the generated code" artifact, not a hidden implementation detail. C89 is the reference implementation; the interface (name/location/role) is chosen so future backends reuse it.

### 5.6 The feasibility investigation (Task 1) — drives this spec
Task 1 is a **record-only** investigation followed by a **STOP** for operator review. Its findings finalize §5.1–§5.5 and the exact tasks/steps of the plan (the plan drives the spec). It must answer: the emit pipeline hook; the exact output file set + sourcing mechanism for headers/runtime; the reachability graph + prune feasibility + fixed-point impact; `@cInclude`/`net_prelude.h` resolution and whether pruning net removes the wsock32 dependency; toolchain flag sets for gcc/mingw/MSVC/OpenWatcom multi-module; and how linux-vs-windows target selection reaches the script generator.

## 6. Testing / gates

- **Default emission:** `zig1 -o DIR examples/z98/hello/main.zig` (no flag) emits the tree; the companion script builds+runs it (host), output byte-identical to the current `--dump-c89` path.
- **Pruning:** a stdio-only fixture's output dir contains no `std_net_*.c/.h`, and a net-using fixture does; `-osw` of the stdio program links **without** `-lwsock32`; the net program links **with** it.
- **Self-contained dir:** build succeeds from a copied output dir with no `-I` into the repo (other than `.`).
- **Scripts:** each target script builds a representative example where the toolchain is available (gcc/mingw on this box; MSVC/owc are emission-only checks unless a toolchain exists).
- **Regression:** golden 9/9 + matrix 21/21 byte-identity; corpus `-s0` zero-asymmetric vs the STDLIB-closed baseline; 4-MD5 rows; self-emission fixed point moves → N-hop closure + seed rotation at close.

## 7. Risks / unknowns (for Task 1)

- Reachability prune correctness (must not drop a transitively-used module), and its fixed-point impact (a compiler-source change).
- Sourcing headers/runtime for the self-contained dir (embed vs path vs staging).
- MSVC/OpenWatcom multi-module correctness is unverifiable on this box beyond emission shape.
- Interaction with `emitBuildTarget*` being dead and the root module rename (`main_<HEX8>.c`).
