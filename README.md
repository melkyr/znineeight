> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 0.20.0 "Oxalic Acid" — Self-Hosted Compiler (zig1)
**A self-hosting subset of Zig → C89 compiler, now compiling itself.**

> **Are you looking for the bootstrap era?** The pre-self-hosted (C++98 `zig0`) guide that
> previously lived in this file is preserved byte-verbatim in
> [README_zig0_bootstrap.md](README_zig0_bootstrap.md). This page documents the current
> self-hosted (`zig1`) era.

## Project Overview
Z98 is a subset of the Zig language. This compiler is not affiliated with the official Zig project.

Z98 targets the Windows 9x-era class of hardware (Pentium II/III, 32 MB RAM, 1998-era tools) via a
"Progressive Enhancement" strategy: a **Stage 0** bootstrap compiler written in C++98 (`zig0`,
Milestones 1–11) compiles a **Stage 1** compiler written in a subset of Zig; **Stage 1** now
compiles itself to become the fully self-hosted compiler, **zig1** — the subject of this release.

- **Stage 0 (`zig0`, C++98)** — the bootstrap compiler. Bootstrap-era work ended 2026-04-27.
  Its own guide is [README_zig0_bootstrap.md](README_zig0_bootstrap.md).
- **Stage 1/2 (`zig1`, Z98)** — the self-hosted compiler. Since 2026-04-27 it is written in Z98
  (a Zig subset) under `sf/src/`, emits ANSI C89, and self-compiles to a byte-identical binary
  (deterministic fixed point — see [Determinism](#determinism)).

## Timeline
- **2025-12-07** — Repository created; bootstrap (`zig0`) work started.
- **2025-12-07 → 2026-04-27** — Bootstrap era (~4.7 months; releases 0.10.0 → 0.13.0).
- **Elapsed (overall)** — project 2025-12-07 → 2026-09-06: **~9 months**.
- **2026-04-27** — Self-hosted era began: branch `zig1_start` born (`main` last commit same day);
  first self-hosted commit `cb11d5c6` "Self hosting initial milestone0 commit".
- **2026-04-27 → 2026-09-06** — Self-hosted / 0.20.0 development window (~4.3 months;
  **1500 commits** on `zig1_start` since `main`).
- **2026-09-06** — This release: **Z98 0.20.0 "Oxalic Acid"**, the first self-hosted release.

## Current Status
The **self-hosted milestone is complete**: `zig1` compiles itself, the compilation is
**deterministic to a fixed point** (self-compile binary md5 `10f0ca2b…`), the 4-program emission
gate is byte-identical (see [Determinism](#determinism)), and the maintained example matrix is
**21/21** dump/gcc/link. The mi_matrix corpus at `-s0` (EXPECTED_FAIL v70, 2026-09-05, **428 dirs**)
classifies **OK=406 / FAIL=13 / GREEN=9 / GCCFAIL=0 / ICE=0 / CRASH=0**; the FAIL=13 and GREEN=9
rows are the documented expected-fail / correctly-rejected fixtures maintained in
`repro/mi_matrix/EXPECTED_FAIL.md`. The upgraded showcase gate
(`scripts/closeout/verify_upgraded.sh`) passes its full A1–B7 battery.

## Key Features
**Language-wins builtins & semantics** (the zig1 feature set):
- Introspection builtins `@offsetOf`, `@bitSizeOf`, `@bitOffsetOf` (struct field byte offsets /
  bit sizes, folded at comptime).
- Pointer builtins `@intFromPtr`, `@ptrFromInt`, `@fieldParentPtr`.
- `@bitCast` (same-size integer reinterpretation).
- `export fn` / `export var` (source-named, non-mangled symbols) and cross-module `pub var`
  scalar stores.
- `switch` case ranges (`1...10 => …`) and clean primary diagnostics for unsupported builtins /
  unknown types (a `error[3000]` primary; the documented downstream void-cascade on untyped
  results is expected, not a defect).

**Target model** — per-invocation target flags `-osl` (linux, default) / `-osw` (windows) with the
`--target linux|windows` alias; `@isWindows()` folds from the chosen target (comptime-pruned).

**Networking (`std_net`)** — rewritten with target-selected OS extern bindings: wsock32
(WSAStartup 1.1 → WSACleanup) on Windows / libc on Linux, one OS-prototype header
(`sf/src/include/net_prelude.h` via `@cInclude`); additive public client factory
`createTcpClient(port: u16) i32`. The old `@socket*` builtins were removed — direct callers get a
clean `error[3000]: unsupported builtin function`.

**Spill management** — `-s<N>` trades RAM for disk I/O (default `-s0` = all five compiler-state
spills on disk, lowest `pool=`); `-mm<N>` sets the hard pool budget (default 64 MB). Compiler
output is byte-identical in every `-s` mode.

**Determinism** — byte-identical self-emission to a fixed point; see below.

**Upgraded showcase examples** — `examples/z98/lisp_interpreter_upgraded` and
`examples/z98/rogue_mud_upgraded` (each with committed canonical/demo goldens and a demo client),
gated by `scripts/closeout/verify_upgraded.sh`.

## Determinism
The self-hosted compiler is deterministic end-to-end. Successive self-host hops emit **byte-identical
C89** and rebuild **byte-identical binaries** — the self-compile fixed point is closed.

- **Self-compile fixed point:** self-compiled `zig1` binary md5 `10f0ca2b703e9c4ffde6ed262f4d8881`
  (41 `.c`, 0 `error[`, 0 PANIC; hop1 == hop2 closure). Operator-approved re-baseline 2026-09-04.
- **Emission chain (verified from source):** gen-0 emission `9c1d956a…` → zig1 binary
  `e791ffd2…` → self-emission set `c0102983…` → fixed-point `zig1_linux32` `10f0ca2b…`.
- **Self-emission byte-identity:** the 41-file `.c`/`.h` self-emission set is byte-identical on
  every successive hop (only hidden `.zig1_*.tmp` spill scratch is non-deterministic — compare
  emitted `.c`/`.h` only). Output is byte-identical at every `-s0`…`-s5` spill level and under
  both target flavours (linux / `-osw`).

**4-program emission gate** (md5 prefixes of `zig1 --dump-c89 … | md5sum`, repo-root CWD,
re-verified 2026-09-06 at HEAD `2e43b541` with the reference `zig1` md5 `c8f1b3d0…`):

| Program | md5 prefix |
|---|---|
| `examples/z98/game_of_life/main.zig` | `302df36b` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `3591bad9` |
| `examples/z98/json_parser/main.zig` | `76056b97` |
| `examples/z98/mud_server/main.zig` | `846106ac` |

All four hashes byte-exact vs the recorded constraints (lisp emits `warning[3037]` diagnostics on
stderr; they do not contaminate the stdout hash). Corpus/golden summary (EXPECTED_FAIL v70,
2026-09-05): **428 dirs** `-s0` = OK=406 / FAIL=13 / GREEN=9 / GCCFAIL=0 / ICE=0 / CRASH=0;
golden fixtures 9/9; example matrix 21/21.

## Build Machine & Toolchain
> AMD Ryzen 7 7700X 8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian; gcc/g++ 12.2.0;
> i686-w64-mingw32-gcc 12-win32

The 0.20.0 binaries were built on this machine. Linux builds target 32-bit (`-m32`) C89 output;
Windows builds are cross-compiled with `i686-w64-mingw32-gcc` (12-win32).

## RAM & Wall-Clock Comparison
Measured on the build machine, each row 3× under `/usr/bin/time -v` in fresh scratch dirs with
fresh output names (no incremental caching); **median** reported. wall = "Elapsed (wall clock)",
RSS = "Maximum resident set size (kbytes)". All runs: rc=0, 0 `error[`, 0 PANIC.

| Row | Phase | Wall (s) | Peak RSS (kB) | ≈ MB | Emitted `.c` |
|---|---|---|---|---|---|
| A | g++ → zig0 (C++98 bootstrap, 64-bit) | 1.52 | 186,432 | 182.1 | — |
| B | zig0 → gen-0 C89 | 3.10 | 46,704 | 45.6 | 43 |
| C | gcc -m32 compile+link of emitted C89 → zig1 | 1.87 | 87,280 | 85.2 | (43 in) |
| D | zig1 `-s0` self-compile → C89 | 1.12 | 13,388 | 13.1 | 41 |
| E | gcc -m32 compile+link of zig1's self-emitted C89 → zig1_5 | 3.46 | 170,544 | 166.5 | (41 in) |

> **The gcc caveat (~80 MB and ~166 MB, both measured).** The gcc backend is the memory hotspot of
> building the compiler from source, and both gcc steps are measured here. Row C — gcc over the gen-0 C89 that zig0 emitted
> (43 files, ~3.3 MB) — peaks at **~85 MB** (linux `-m32`; the mingw cross peaks higher, ~168 MB).
> Row E — gcc over zig1's **own** self-emission (41 files, ~7.6 MB, ~2.3× the gen-0 C set,
> byte-identical on every self-host hop) — peaks at **~166 MB** (3.46 s). Because each self-host hop
> recompiles that same byte-identical self-emission, **Row E's ~166 MB figure — not Row C's —
> applies to every `zig1_5`-style next-generation hop** and to any compiler-from-source build that
> starts from a self-hosted zig1; it is not specific to this measurement. Row A (the g++ C++98
> bootstrap) is even larger at ~182 MB, but only matters when rebuilding `zig0` from scratch; the
> release ships prebuilt `zig0` binaries (no `zig0` source archive). Rows B (~46 MB) and D (~13 MB)
> fit comfortably in era-class RAM.

Supporting data for the `-s0` row: `zig1 -s0 --markers --track-memory` self-compile reports
`pool=14881K` (~14.5 MB pool) with RSS ~13 MB — the basis for the "~16 MB at `-s0`" figure.

## Minimum Requirements
| Requirement | Linux | Windows 9x / MinGW |
|---|---|---|
| **RUNNING `zig1`** (compiling a program with a released binary) | `zig1` binary + the 4-file `lib/` std set next to it (auto-discovered); ~16 MB RAM at `-s0` | `zig1_w32.exe` + the std set on the search path (`-I <lib>`; win has no exe-relative auto-discovery); ~16 MB RAM at `-s0` |
| **BUILDING the compiler from source** | gcc (C89) for the emitted C — gcc backend **~80 MB** peak (measured ~85 MB); + g++ ~182 MB if also rebuilding the `zig0` bootstrap from scratch | mingw gcc for the emitted C — gcc backend dominates (mingw cross measured ~168 MB on the reference machine) |

> **zig1 runs in ~16 MB at `-s0`, but building the compiler from source is dominated by the gcc
> backend ~80 MB — a 16 MB machine can run zig1 but cannot build it from source.** Running (compiling
> programs) and building (recompiling the compiler) have different memory profiles; do not assume a
> small-RAM era machine that can run the released binaries can also build them.

## PII/PIII Time Estimates
Engineering estimates — not measurements. Clock-scaled from the table above via
`T_p = T_m × f_m/f_p × k` (`k` = 1.0 default uncertainty multiplier; `f_m` = 4.0 GHz conservative
single-core figure for the 7700X; PII representative 300–450 MHz, PIII 700–1000 MHz). Each entry
is a range spanning the clock band; the low end is the k=1.0 clock-only lower bound.

| Row (median `T_m`) | PII 300–450 MHz (s) | PIII 700–1000 MHz (s) |
|---|---|---|
| A — g++ → zig0 (1.52 s) | 13.5 – 20.3 | 6.1 – 8.7 |
| B — zig0 → gen-0 C89 (3.10 s) | 27.6 – 41.3 | 12.4 – 17.7 |
| C — gcc C89 → zig1 (1.87 s) | 16.6 – 24.9 | 7.5 – 10.7 |
| D — zig1 `-s0` self (1.12 s) | 10.0 – 14.9 | 4.5 – 6.4 |
| whole battery (Σ 7.61 s) | ~68 – 101 (≈1.1–1.7 min) | ~30 – 44 |

**Methodology.** Each row was run 3× under `/usr/bin/time -v` on the reference machine (AMD Ryzen 7
7700X — see machine statement), in fresh scratch directories with fresh output names per repetition
to defeat any incremental caching; the median wall-clock ("Elapsed (wall clock)") and median peak
RSS ("Maximum resident set size (kbytes)") are reported. The PII/PIII figures are clock-scaled
engineering estimates computed as `T_p = T_m × f_m/f_p × k`, where `T_m` is the measured median wall
time on the reference machine, `f_m = 4.0 GHz` is a conservative single-core figure for the 7700X,
`f_p` is the target-era representative clock (PII 300–450 MHz; PIII 700–1000 MHz), and `k = 1.0` is
the default uncertainty multiplier. Each entry is a range spanning the platform's clock band; the
low end is the k=1.0 clock-only lower bound. Memory-bound phases (notably the gcc backend, ~80–90 MB
measured, and the g++ bootstrap, ~190 MB measured) scale worse than the clock ratio on small-RAM era
machines where paging dominates — apply 1.5–3× as the stated upper rationale. **These are engineering
estimates; verify on the operator's real VM.**

## Getting Started / Building from Source / Building a Program
Two workflows: run a released binary, or build `zig1` from the source archive.

**Build `zig1` from source** — download the release source archive **`zig1_src.tgz`** (linux) or
**`zig1_src.zip`** (win9x-unpackable). It contains the full compiler source tree (`sf/src/*.zig` +
`sf/src/include/`), a `RELEASE_README.txt` with the exact where/how build commands, and the std
modules. This source is a Zig-subset program, **not** directly compilable by a C toolchain: it must
first be compiled with the `zig0` bootstrap compiler (download `zig0_linux32` or `zig0_w32.exe`
from this same release), or rebuilt via the self-host chain — a working `zig1` can emit its own C
(`zig1 -s0 --dump-c89 --output-dir <dir> sf/src/main.zig`) and you then compile+link that C with the
runtime (`zig_runtime.c`, `zig_pal.c`, `c_exit.c`) — deterministic, byte-identical to the fixed
point. For the bootstrap (`zig0`) toolchain build, see
[README_zig0_bootstrap.md](README_zig0_bootstrap.md) and [docs/Building.md](docs/Building.md).

**Compile a program with `zig1`** — `zig1 --dump-c89` emits C89; compile+link it with a C89
compiler, the include path, and the runtime:
```bash
zig1 --dump-c89 hello.zig > hello.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I <include-dir> \
    hello.c zig_runtime.c zig_pal.c -o hello
```
(Install the 4 std modules — `std.zig`, `std_io.zig`, `std_arena.zig`, `std_net.zig` — next to the
`zig1` binary in a `lib/` dir for `@import("std")`; windows users pass `-I <lib>` explicitly.)
Multi-module programs emit one `.c`/`.h` pair per module: use
`zig1 --dump-c89 --output-dir <dir> main.zig` and compile+link `<dir>/*.c` with the runtime set.
The authoritative, always-verified command set lives in [docs/sf/QUICK_REF.md](docs/sf/QUICK_REF.md);
the build script is `sf/scripts/build_release.sh`. Release binaries (`zig1_linux32` /
`zig1_w32.exe`) ship with a sibling `lib/` and `MANIFEST.txt` (md5/sha256/sizes).

## Command-Line Flags
`zig1`'s flag set (the self-hosted compiler; for the `zig0` bootstrap flags see
[README_zig0_bootstrap.md](README_zig0_bootstrap.md)):

| Flag | Purpose |
|---|---|
| `-o <dir>` / `--output-dir <dir>` | Output directory for emitted `.c`/`.h` files |
| `--dump-c89` | Emit the input program's C89 (to stdout, or per-module `.c`/`.h` into `--output-dir`) |
| `-I <dir>` / `--lib-dir <dir>` | Add a module search dir for `@import` (importer dir, then `-I` dirs in order, then `<exe_dir>/lib`, then CWD) |
| `-osl` / `-osw` | Target OS: linux (default) / windows; folds `@isWindows()` |
| `--target <linux\|windows>` | Alias for the target OS |
| `-s<N>` | Spill level 0–5 (default `-s0`): how many of the five compiler-state spills live in RAM instead of `.zig1_*.tmp` disk files. Higher `-s` = more RAM, less disk I/O; emission byte-identical in every mode. `-s0` ≈ 14.9 MB pool; `-s1` ≈ 33 MB; `-s2`..`-s5` ≈ 71–73 MB. Bare/non-digit/out-of-range `-s` = error rc=1 |
| `-mm<N>` | Hard pool budget in MB (default 64). Levels whose pool exceeds the budget abort with `memory limit exceeded` rc=3 (e.g. `-s2`+ need `-mm128`) |
| `-m <size>` / `--max-mem <size>` | Pool memory budget with k/M/G suffix |
| `--track-memory`, `--markers` | Memory tracking / pipeline markers (e.g. the `pool=` report line) |
| `-e <n>` / `--max-errors <n>` | Maximum errors before abort |
| `-q` / `--quiet` | Quiet mode |
| `-W` / `--warnings-as-errors`, `--warn-all`, `--warn-error` | Warning policy |
| `--color <mode>`, `--error-format <fmt>` | Diagnostic rendering |
| `--no-null-check`, `--no-lifetime-check`, `--no-leak-check` | Disable individual static analyzers |
| `--test`, `--sanity-test` | Compiler self-test / sanity-test mode |

## Running Tests
- **Unit/analyzer tests**: the sf test binaries under `sf/src/tests/` (e.g. the analyzer test bin),
  built via `sf/scripts/build_test.sh`; plus `zig1 --test` / `--sanity-test`.
- **Corpus gate**: the `repro/mi_matrix` corpus (428 dirs at `-s0`, EXPECTED_FAIL v70) — run
  `zig1 --dump-c89` + gcc `-c` per dir, classified OK/FAIL/GREEN per the QUICK_REF classifier.
- **Example matrix**: 21 `examples/z98` programs, 21/21 dump/gcc/link.
- **Golden fixtures**: 9/9 golden outputs.
- **Upgraded-showcase gate**: `scripts/closeout/verify_upgraded.sh` (A1–B7) gates
  `lisp_interpreter_upgraded` and `rogue_mud_upgraded` against their committed canonical/demo
  goldens (with `scripts/closeout/flush.c` for timeout-safe server output).
- The bootstrap-era root `./test.sh` runner is gone from this branch; the live suites above are the
  current verification surface. See [docs/sf/QUICK_REF.md](docs/sf/QUICK_REF.md) for exact commands.

## Minimal Distribution
To build a Z98 program on a target machine you need:
1. **`zig1`** (or `zig1_w32.exe`) — the self-hosted compiler binary.
2. **The std modules** — the 4 files `std.zig`, `std_io.zig`, `std_arena.zig`, `std_net.zig`
   (linux: in a `lib/` dir beside the binary; windows: on the `-I` search path).
3. **Runtime sources & headers** — `sf/src/include/` (`zig_runtime.c`/`.h`, `zig_pal.c`,
   `zig_compat.h`, and the OS/prelude headers) needed to compile and link the emitted C89.

## Documentation
- [docs/](docs/) — building, language spec, design, and reference docs.
- [docs/sf/](docs/sf/) — self-hosted compiler documentation (`Design_p2.md`, `TYPE_SYSTEM_p2.md`,
  `LIR_C89_Emission_p2.md`, and the design corpus), plus the **QUICK_REF** cheat sheet with the
  authoritative build/compile/gate commands.
- [docs/reference/Language_Spec_Z98.md](docs/reference/Language_Spec_Z98.md) — the Z98 language
  specification.
- [docs/superpowers/](docs/superpowers/) — plan/spec/design history for the self-hosted era.
- [repro/mi_matrix/EXPECTED_FAIL.md](repro/mi_matrix/EXPECTED_FAIL.md) — the mi_matrix corpus
  manifest (v70).
- [README_zig0_bootstrap.md](README_zig0_bootstrap.md) — the preserved bootstrap-era (`zig0`)
  README, kept byte-verbatim.

## Example Showcase
`examples/z98/` carries the maintained example suite (matrix 21/21 dump/gcc/link), including
complete programs that exercise the language-wins features and the PAL/networking runtime:
- **`game_of_life`** — interactive simulation on the PAL UI layer.
- **`lisp_interpreter_curr`** and the upgraded **`lisp_interpreter_upgraded`** — a complete Lisp
  interpreter with tagged unions, deep switches and arena GC (upgraded edition adds committed
  canonical/demo goldens under `demo/`).
- **`json_parser`** — JSON parser exercising optional types and error handling.
- **`mud_server`** — non-blocking telnet server over `std_net`.
- **`rogue_mud`** and the upgraded **`rogue_mud_upgraded`** — a networked roguelike (A* pathfinding,
  BSP maps, export symbols, and a `demo/` client/server pair
  `net_main.zig` / `net_demo_client.zig` using `std_net.createTcpClient`).
- Plus the classic single/multi-module programs (`hello`, `prime`, `fibonacci`, `days_in_month`,
  `heapsort`, `quicksort`, `sort_strings`, `mandelbrot`, `lzw`, `func_ptr_return`, `tco_*`).

See `scripts/closeout/verify_upgraded.sh` for the canonical/demo golden gates on the upgraded
showcase programs.
