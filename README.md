> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project. Z98 represents a specific interpretation of the Zig language, designed to target 1998-era hardware and C89 code generation. As such, it contains intentional differences from the official Zig specification.

# Z98 0.21.2 "Terephthalic Acid" — Self-Hosted Compiler (zig1)
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
- **2025-12-07 → 2026-04-27** — Bootstrap era (~4.7 months; releases 0.10.0 → 0.13.0). *Historical.*
- **Elapsed (overall, through 0.20.0)** — project 2025-12-07 → 2026-09-06: **~9 months**. *Historical.*
- **2026-04-27** — Self-hosted era began: branch `zig1_start` born (`main` last commit same day);
  first self-hosted commit `cb11d5c6` "Self hosting initial milestone0 commit".
- **2026-04-27 → 2026-09-06** — Self-hosted / 0.20.0 development window (~4.3 months;
  **1500 commits** on `zig1_start` since `main`). *Historical.*
- **2026-09-06** — **Z98 0.20.0 "Oxalic Acid"** released, the first self-hosted release.
  *Historical; no 0.20.0 tag exists.*
- **2026-09-06 → 2026-10-29** — 0.21.0 development window: **53 days (~7.6 weeks)**,
  **1,864 commits** from `ab49e167` to `d609186c` (no merges); followed by the Win9x truth hotfix
  (`cdec5098`, `1e7b303a`) and seed v129 rotation (`b5580232`).
- **2026-10-29** — Z98 **0.21.0 "Terephthalic Acid"** released (seed v129).
- **2026-11-02** — Win9x emission fixes rotate the seed v130 → v131 (included in this hotfix).
- **2026-11-03** — Z98 0.21.1 "Terephthalic Acid" (hotfix), seed **v132**.
- **2026-11-05** — This release: **Z98 0.21.2 "Terephthalic Acid"**, seed **v135**, with the
  operator-built Windows 9x/NT compilers.

## Current Status
**Z98 0.21.2 "Terephthalic Acid" is the current release (2026-11-05).** It supersedes the
0.21.1 hotfix staging and ships the operator-built Windows compilers (OpenWatcom static-CLIB
canonical, MSVC 6 `/MT`, MinGW CRT) with the Linux artifacts. It rolls up the v133-v135 work:
the z9play/z9torr optimizations, example idiom modernization, and the portable switch /
negative-case / enum emission fixes. The **self-hosted milestone is complete**: `zig1`
compiles itself, the compilation is **deterministic to a fixed point** (current self-compile
binary md5 `73c75a65e30dfd212fdf93ae1e57a687`; committed seed **v149**,
`release/seed/zig1-seed.tgz`; the fixed point moved from v141 `cf68f192…` by the Phase 3.1
Task 1/7 compiler-source changes, v142-v145 retained `cd8d283b…`, the Phase 3.5 defect
closure moved it to `de5e99b6…`, and the final expected-type fix moved it to
`73c75a65…`), the 4-program emission gate
is byte-identical (see [Determinism](#determinism)), and the maintained example matrix is
**29/29** dump/gcc/link.
The mi_matrix corpus at `-s0` is enumerated by the canonical generator
[`scripts/corpus/list_corpus_dirs.sh`](scripts/corpus/list_corpus_dirs.sh); the Phase 4 P2
measurement with the v147 compiler is
1279 dirs = 1093 OK / 63 GREEN /
123 FAIL / 0 ICE / 0 CRASH, class md5 `47cac0ca24240759d0df922e5fd7a976` (the v147
Phase 3.5 anchor was 1278 = 1092 OK / 63 GREEN / 123 FAIL, class md5
`c0c3fdc5dbf09c294b75eac98523cd73`; the added OK entry is the now-enumerated
`examples/z98/z9gb`), with goldens
5/5 and stdlib 376/0 + crosscheck 10/10. The frozen-1124 subset is
`17eb6474b9ff6895cd1b3b3615584e3c` (950 OK / 59 GREEN / 115 FAIL; one operator-accepted
D15 consequence: `switch_case_qualifier_reject_xmod` FAIL→GREEN). The upgraded showcase gate
(`scripts/closeout/verify_upgraded.sh`) passes its full A1–B7 battery.

**Phase 4 P3 (playable DMG) is complete.** The `z9gb` Win32 backend adds DirectDraw pixel
presentation (`std_ddraw`), DirectInput8 keyboard/gamepad with a `GetAsyncKeyState` keyboard
fallback (`std_dinput`), QPC frame pacing, the DMG APU, and DirectSound with a WinMM `waveOut`
fallback (`std_dsound`); JOYP input (`FF00`) is wired through `emuSetButtons` (Task 5.1).
Windowed display requires the DirectX 6/8 runtimes: `IDirectDraw7` needs the DX6+ runtime and
gamepad input needs `dinput8.dll` (DX8); stock Win98 ships DX5, and a missing `dinput8.dll` falls
back to keyboard-only input. The authoritative performance gate is host headless `2048.gb`
(`--headless --frames 600 --audio`) at **>= 59.0 fps** (measured 967.742 fps); Wine windowed
`2048.gb` is evidence only, never Win98, and sandbox Wine is painfully slower (measured 47.658
fps, `child_rc=0`). Operator-supplied Wine numbers are non-authoritative. Audio falls back to
WinMM when DirectSound is unavailable. No Win98 real-hardware run was performed: the Wine result
is not hardware evidence.

**Phase 4 P4 (CGB support) is complete.** `z9gb` now runs Game Boy Color software with `--cgb`:
CGB color palettes (`BCPS/BCPD`, `OCPS/OCPD`), tile attributes, two VRAM banks and eight WRAM
banks, double-speed mode via `KEY1`, general-purpose/HBlank HDMA (`HDMA1..HDMA5`), and CGB APU
semantics. A CGB-only cartridge is a hard requirement: without `--cgb` it prints
`z9gb: CgbRequired` and exits 2. The P4 hard gates `cgb-acid2`, `cgb_sound`, and `interrupt_time`
all pass (`tier_cgb.sh` 18 passed; DMG tiers unchanged: `tier_smoke` 18, `tier_dmg` 49 plus gates
3, `tier_audio` 10, `tier_win32` 35). The committed `cgb-acid2` golden is derived from the official
`mattcurrie/cgb-acid2` v1.1 reference PNG (SHA-256
`9ea9c262…0c4fdf01`), not from this emulator, and is pinned at SHA-256
`0fba336c…71fcf9fd`. CGB host headless `2048.gb` measured **983.607 fps** (unchanged >= 59.0 fps
threshold); CGB-mode peak RSS measured **10,288 KiB** for the deterministic 8 MiB ROM workload.
Wine windowed `2048.gb` measured 47.620 fps as DMG-mode Wine evidence only (the Wine path
delegates to `tier_win32.sh --perf` and does not receive `--cgb`); it is never Win98 hardware.
No Win98 real-hardware CGB run was performed; real-hardware sign-off remains the operator's.

**Phase 4 P5 (SM83 dynarec) is complete.** `z9gb` adds `--dynarec`, a Win32/x86
basic-block translator that executes from a separate 1 MiB `VirtualAlloc`
`PAGE_EXECUTE_READWRITE` mapping; the interpreter remains the oracle and the
fallback for non-ROM PCs, interrupts/DMA, allocation failure, and *nix hosts
(where `--dynarec` prints `dynarec=disabled reason=unsupported-host`). The code
cache is separate from the 1 MiB stack and from static/BSS state
(`code_cache_bytes=1048576`, `stack_limit=1048576`, `static_bytes=9801160`,
dynarec state 262,196 bytes). Final gates: `tier_dmg --gates` 166/0,
`tier_dynarec` 26/0, `tier_smoke` 18/0, `tier_cgb` 39/0, `tier_audio --gate`
9/0, `tier_win32` 39/0 and `--smoke` 18/0, `tier_perf` 8/0 plus the
`--compat --user-roms` matrix 16/0. On `2048.gb` over 600 frames, host headless
`--no-dynarec` measured **833.333 fps** (the unchanged >= 59.0 fps hard gate,
unpaced interpreter throughput); host `--dynarec` is disabled as unsupported on
*nix, so host runs cannot judge dynarec. The primary throughput metric is Wine
headless turbo `T-cycles/sec = 42,134,400 / wall`, using medians of three
alternating runs after a warmup. The verdict is workload-dependent: at 1.2%
coverage `2048.gb` measured **8,056,291** with dynarec versus **8,181,437**
without (1.5% slower); at 31.7% coverage Pokemon Crystal measured **7,646,897**
versus **9,363,200** (18.3% slower); at 97.3% coverage Pokemon Pinball measured
**12,768,000** versus **10,666,937** (19.7% faster). The original P5 "no
measurable gain" verdict came from the 2048-only, ≤6%-coverage workload; it is
not a universal result. Wine windowed fps (47.168 without dynarec, 47.622 with
it) is display-bound evidence only. No fixed speedup threshold applies. Wine is
evidence only, never Win98; no real Win98 dynarec run was performed and
real-hardware sign-off remains the operator's.

**Phase 1 (TLS + WireGuard) is complete.** The std library now carries the
browser-grade TLS 1.2/1.3 client (`std_tls` over `std_crypto`/`std_cipher`/
`std_ecc`/`std_asn1`/`std_x509`/`std_http`), the WireGuard initiator
(`std_wireguard`), and the client-only userspace IPv4/TCP/UDP/DNS/ICMP stack
(`std_tcpip`). On Linux the closeout tiers run real HTTPS and a MUD session
through a real Linux kernel WireGuard tunnel; the `-osw` builds are
emission/import-gated and are **not executed by `tier_tls`**. `tier_wireguard`
additionally executes its demo under Wine, while `tls_demo/README.md` documents
a manual Wine run. Measured RAM/CPU tables are in the two demo READMEs.

**Phase 3.3 (HTTP/2) is complete and shipped in seed v145.** The std library adds
`std_tls_io` (nonblocking `TlsIo` socket driver over `std_net`), `std_hpack`
(full HPACK decode with a literal-only encoder), and `std_http2` (coroutine-driven
HTTP/2 client with connection reuse and multiplexing). TLS gains ALPN
(`alpn_h2`, `tlsAlpnSelected`) and the opt-in `prefer_chacha20` suite/group
ordering; the HTTP/2 path sets it, and the default `false` keeps existing wire
fixtures byte-identical. Both transports work: TLS+ALPN `h2` and cleartext h2c
via prior knowledge only (no HTTP/2 Upgrade). The caller owns the event loop:
select **read and write** readiness with a bounded timeout and a stall watchdog,
and re-arm for writability whenever `http2Pump` reports pending output; the
non-suspending pump returns `WouldBlock` and request coroutines suspend in
`http2Wait`. HPACK decoding is full (canonical Huffman + ring dynamic table);
encoding is literal-only. Closed/reset streams are **leased** until
`http2Release`; buffered response bodies are copied into the caller-owned
`out.body` capacity and capped at 1 MiB (larger bodies use `ResponseSink`).
There is no server push, no priority scheduling, and no HTTP/2 Upgrade. The
local integration tier uses an ephemeral Node 18+ `http2` server generated in
`/tmp`; when Node is absent it prints `SKIP` and never claims PASS. Server-backed
fixtures pin argless usage goldens, and z9git remains unchanged on HTTP/1.1.
Win9x evidence for the HTTP/2 path is cross-build/emission only — no h2 hardware
run is claimed.

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

**Async / coroutines** — cooperative `@async*` builtins (`@asyncInit` / `@asyncSuspend` /
`@asyncResume` / `@asyncFrameSize`) compile every suspending function into a step machine, driven by
the `std.async` library: a per-task child-frame `Context` pool, `Task`/`Scheduler`, and
`tick` / `addTask` / `removeTask` / `awaitTask` / `waitFor` / `cancel`. The converted `rogue_mud`
(NPC AI, per-client broadcast, cross-module create/schedule/cancel) and `mud_server` (per-client
tasks) examples exercise it. See `sf/docs/tech_docs/12_async_coroutines.md` and the language spec
§4.1.

**Spill management** — `-s<N>` trades RAM for disk I/O (default `-s0` = all six compiler-state
spills on disk, lowest `pool=`); `-mm<N>` sets the hard pool budget (default 64 MB). Compiler
output is byte-identical in every `-s` mode.

**Determinism** — byte-identical self-emission to a fixed point; see below.

**Upgraded showcase examples** — `examples/z98/lisp_interpreter_upgraded` and
`examples/z98/rogue_mud_upgraded` (each with committed canonical/demo goldens and a demo client),
gated by `scripts/closeout/verify_upgraded.sh`.

## Determinism
The self-hosted compiler is deterministic end-to-end. Successive self-host hops emit **byte-identical
C89** and rebuild **byte-identical binaries** — the self-compile fixed point is closed.

- **Current self-compile fixed point:** self-compiled `zig1` binary md5
  `73c75a65e30dfd212fdf93ae1e57a687` (48 module `.c` + 49 module `.h`,
  12,932,829 bytes, 0 `error[`, 0 PANIC; a rebuild from the committed v149
  archive is hop1 == hop2 == `73c75a65e30dfd212fdf93ae1e57a687`), committed
  seed **v149** (`release/seed/zig1-seed.tgz`, archive md5
  `52984a63a5dcdf41e8c4c142e3bb366f`; Win9x zip md5
  `9b9326db35dc3f3a6adffe9a6b9c8e9b`; `lib/manifest.md5` md5
  `b4089e728b41aff27afbeffd9aa7e862`, 65 std files). v149 is the Phase 4 P3
  final-review std-only rotation: it updates `std_ddraw_pal.zig` and
  `std_dsound_pal.zig` with no compiler-source or barrel change, so the fixed
  point stays `73c75a65…` and the 8 emission pins are unchanged; `lib/` remains 65 from v148.
  v147 was the final Phase 3.5
  closeout expected-type contract rotation (Task 12.2-F `2383dc29`);
  it supersedes the invalid v146 seed, restores module-scope unannotated value
  initializers to peer resolution under the explicit
  `none`/`known`/`undetermined` contract, and moves the fixed point from
  `de5e99b6…` to `73c75a65…`. The accepted contract correction also changes a
  module-scope unannotated `if` with string literals from a pointer to a slice;
  that is intentional and is not special-cased back to the pointer form. v146
  was the Phase 3.5
  defect-closure compiler-source rotation (analyzer/lowering/emission fixes
  D3/D4/D5/D7.3/D8/D10/D12/D13/D14/D15) and moved the fixed point from
  `cd8d283b…` to `de5e99b6…`; v145 was a std-only Phase 3.3 HTTP/2 closeout
  rotation that retained the v142-v144 fixed point; v144 was the initial
  Phase 3.3 HTTP/2 rotation and v143 the earlier std-only `std_gpa`
  medium-decommit-failure rotation. The fixed point moved from v141
  `cf68f192…` to v142 `cd8d283b…` by the Task 1/7 compiler-source changes
  (`std_page_prelude.h` emission, `error[3079]`, GPA analyzer ownership
  recognition), not by the std payload. v135-v141 kept `cf68f192…`; v134
  `8dff7650…` was the switch-emission fix
  rotation; the v129 fixed point `c1bb4c0e…` was the 0.21.0 release; v130/v131 were
  the Win9x emission-fix rotations included in that hotfix. Earlier fixed points
  (`18b4b10c…` v128, `45158dce…` M2 T1C-F, `a567926c…` iterative lowering, and the
  v119-v127 payload rotations) are historical.
- **Historical fixed point (0.20.0-era):** `553a39b4…` / seed v27 (45 module `.c` + 46 module `.h`);
  the operator-approved C89-AHEAD closeout (2026-09-13) was at the earlier fixed point
  `1467d932…` / seed v10. The old N-hop chain (seed v26 `f03d8485…` → hop1/hop2 `553a39b4…`) is
  retained here as history only. zig0 is retired; the seed model
  (`scripts/seed/build_from_seed.sh`) is the only rebuild path.
- **Self-emission byte-identity:** the 48-module `.c` + 49 `.h` self-emission set is byte-identical on
  every successive hop (only hidden `.zig1_*.tmp` spill scratch is non-deterministic — compare
  emitted `.c`/`.h` only). Output is byte-identical at every `-s0`…`-s6` spill level and under
  both target flavours (linux / `-osw`).

**4-program emission gate** (Phase 3.5 Task 12 defect-closure re-baseline; md5 of
`zig1 --dump-c89 …`; repo-root CWD; reference `zig1` md5
`73c75a65e30dfd212fdf93ae1e57a687`; rows are the default `-fsafe` emission — the full 8-pin
safe/fast table is in `docs/sf/QUICK_REF.md`):

| Program | md5 (default `-fsafe`) |
|---|---|
| `examples/z98/game_of_life/main.zig` | `0be513f90937621d47a331211bef9d67` |
| `examples/z98/lisp_interpreter_curr/main.zig` | `a2169c2c5b019504eaa9da0a851d8658` |
| `examples/z98/json_parser/main.zig` | `bbcd375f657d168df504d1f4ae06774e` |
| `examples/z98/mud_server/main.zig` | `9691c2878564d61fe4272c3d3b5da253` |

These four hashes were re-recorded at v146 by `gate_lower_depth.sh` case 5 (the Phase 3.5
Task 12 re-baseline; the dump includes the D3/D8/D14/D15 emission changes) and are unchanged
at v147. Analyzer
warnings remain on stderr and do not contaminate the stdout hash; the
runtime goldens remain byte-identical. Corpus/golden
summary: the corpus universe is enumerated by
`scripts/corpus/list_corpus_dirs.sh`; the Phase 4 P2 measurement with the v147 compiler is
1279 dirs = 1093 OK / 63 GREEN / 123 FAIL / 0 ICE / 0 CRASH (class md5
`47cac0ca24240759d0df922e5fd7a976`; the v147 Phase 3.5 anchor was 1278 = 1092 OK / 63 GREEN /
123 FAIL, class md5 `c0c3fdc5dbf09c294b75eac98523cd73`; the added OK entry is the
now-enumerated `examples/z98/z9gb`).
The frozen-1124 subset is `17eb6474b9ff6895cd1b3b3615584e3c` (950 OK / 59 GREEN / 115 FAIL):
one operator-accepted D15 consequence, `switch_case_qualifier_reject_xmod` FAIL→GREEN (the
new `error[3000]` prong-type diagnostic makes the classifier's green-guard rule fire).
Goldens 5/5; example matrix 29/29; stdlib 376/0 + crosscheck 10/10.

## Build Machine & Toolchain
> AMD Ryzen 7 7700X 8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian; gcc/g++ 12.2.0;
> i686-w64-mingw32-gcc 12-win32

The 0.21.2 Linux artifacts were built and measured on this machine: Debian GNU/Linux 12
(bookworm), gcc 12.2.0, `i686-w64-mingw32-gcc` 12-win32, Wine 8.0, `gcc -m32` available; no
MSVC or OpenWatcom locally. Linux builds target 32-bit (`-m32`) C89 output; Windows cross-builds
use `i686-w64-mingw32-gcc` (12-win32). The three Windows compilers were built and manually tested
on the operator's Windows 98 machine with MSVC 6, OpenWatcom 1.9, and MinGW gcc 3.4.5; the
canonical Win9x binary is the OpenWatcom static-CLIB build (no `msvcrt.dll`).

## RAM & Wall-Clock Comparison
Measured on the build machine, each row 3× under `/usr/bin/time -v` in fresh scratch dirs with
fresh output names (no incremental caching); **median** reported. wall = "Elapsed (wall clock)",
RSS = "Maximum resident set size (kbytes)". All runs: rc=0, 0 `error[`, 0 PANIC.

### Current measurements (v135, measured 2026-11-05)

Reference binary `release/staging/0.21.2/zig1_linux32`, md5 `cf68f192900e7f6618c11e1712b74b3a`,
built from `release/seed/zig1-seed.tgz` with two-hop closure `hop1 == hop2`; the same binary is
archived as seed v135. Raw logs are `/tmp/m212/`. The v132 numbers are retained in the 0.21.1
release notes.

| Row | Phase | Wall (s) | Peak RSS (kB) | ≈ MB | Emitted `.c` |
|---|---|---|---|---|---|
| D-safe | `zig1 -s0 --dump-c89` self-emission (default `-fsafe`) | 6.91 | 20,716 | 20.2 | 48 |
| D-fast | `zig1 -s0 -ffast --dump-c89` self-emission | 6.73 | 20,100 | 19.6 | 48 |
| E | gcc `-m32` compile+link of the D-fast output (`sh build_target.sh linux zig1_next`) | 9.56 | 181,564 | 177.3 | (48 in) |

> Row E produces `zig1_next` md5 `44d1bf034c678bde26a4e2ac45eda354` — a build-recipe binary, not
> the fixed point. All three E builds were byte-identical.

#### Current spill ladder (`-s0` … `-s6`), self-emission at v135

RSS is the median of 3; `pool` is copied from the `--markers --track-memory` line (3× identical).
All 21 ladder emissions were byte-identical across levels and repetitions.

| Level | Pool (K) | Max RSS (KiB) | Notes |
|---|---:|---:|---|
| `-s0` | 18,677 | 20,284 | all disk |
| `-s1` | 50,421 | 45,900 | |
| `-s2` | 119,477 | 95,532 | needs `-mm128` |
| `-s3` | 119,477 | 95,180 | needs `-mm128` |
| `-s4` | 123,573 | 99,368 | needs `-mm128` |
| `-s5` | 126,645 | 101,336 | needs `-mm128` |
| `-s6` | 131,765 | 104,080 | all RAM; needs `-mm160` (the 128 MB limit ICEs) |

#### Current deep-input evidence (v135, 1 MB stack)

| Shape | rc @ `ulimit -s 1024` | Max RSS (KiB) | Wall (s) |
|---|---:|---:|---:|
| 120-term runtime-valued `+` chain | 0 | 7,112–7,256 | 0.05 |
| 300-deep nested blocks | 0 | 4,264–4,516 | ~0.00 |

### Historical measurements (0.20.0-era and v123-era; not current)

| Row | Phase | Wall (s) | Peak RSS (kB) | ≈ MB | Emitted `.c` |
|---|---|---|---|---|---|
| A | g++ → zig0 (C++98 bootstrap, 64-bit; historical) | 1.52 | 186,432 | 182.1 | — |
| B | zig0 → gen-0 C89 (historical bootstrap) | 3.10 | 46,704 | 45.6 | 43 |
| C | gcc -m32 compile+link of emitted C89 → zig1 (historical bootstrap) | 1.87 | 87,280 | 85.2 | (43 in) |
| D | zig1 `-s0` self-compile → C89 | 3.90 | 16,376 | 16.0 | 45 module (48 full) |
| E | gcc -m32 compile+link of zig1's self-emitted C89 → zig1_5 | 5.87 | 160,712 | 157.0 | (48 in; 45 module) |

> **Note:** Rows A/B/C are historical 0.20.0-era bootstrap measurements (`zig0` retired; not re-measurable). Rows D/E were current at fixed point `553a39b4…` (historical; superseded by the current v135 measurements above): their Wall/Peak RSS figures are the medians at that fixed point and their emitted `.c` counts are 45 module (48 full) for D and 48 full (45 module) for E.

> **The gcc caveat (current v135 ~177 MB; historical ~85 MB and ~157 MB, all measured).** The gcc
> backend is the memory hotspot of building the compiler from source. At v135, Row E — gcc `-m32`
> over zig1's **own** self-emission — peaks at **~177 MB** (181,564 kB, 9.56 s). The historical
> 0.20.0-era Row C (gcc over the gen-0 C89 that zig0 emitted) peaked at **~85 MB** (linux `-m32`;
> the mingw cross higher, ~168 MB), and the historical Row E at `553a39b4…` peaked at **~157 MB**
> (5.87 s). Because each self-host hop recompiles the same byte-identical self-emission, the
> current Row E figure applies to every `zig1_5`-style next-generation hop and to any
> compiler-from-source build that starts from a self-hosted zig1. Row A (the g++ C++98 bootstrap)
> was ~182 MB, but only matters when rebuilding `zig0` from scratch; 0.21.2 ships no zig0. Rows
> B (~46 MB) and the historical D (~16 MB) fit comfortably in era-class RAM; the current v135 RUN
> figure is ~20 MB (see above).

Supporting data for row D at fixed point `553a39b4…` (historical): `zig1 -s0 --markers --track-memory` self-compile reported
`pool=14145K` (~13.8 MB pool) with RSS ~16.0 MB — that older build **met** the "~16 MB at `-s0`" figure (pool 14,145 K = 2,239 K under; RSS 16,376 kB = 8 kB under, at the boundary). At the **M1 measured** fixed point `21c957…` (historical; see the M1 section below), the measured peak is 20792 KiB RSS with pool 18871K.

### Historical full measured compiler peak (v123-era fixed point `2fc64ffe…`)  [measured 2026-10-27 at seed v123]

**These are historical measurements, taken at seed v123 and superseded by the current v135 rows
above; v132 is recorded in the 0.21.1 release notes.** Measured 2026-10-27 at
`a567926c223492787786dd460563f32a` (seed v123), fixed-point binary
`/tmp/memfix_build/zig1_5_clean` built by
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/memfix_build`
(two-hop closure hop1 == hop2 == `a567926c…`). Every RSS/wall figure is the
**median of 3 runs** under `/usr/bin/time -v` in fresh scratch dirs; arena
figures come from a separate `--markers --track-memory` run (3×, identical).
All raw runs: `.superpowers/sdd/2026-10-26-iterative-lowering-plan/memory-measurements.md`.

| Workload | Max RSS (KiB) | Wall (s) | Arena |
|---|---:|---:|---|
| (a) fixed-point self-emission (`-ffast --dump-c89`) | 20348 | 6.65 | pool=18416K, total=2795K |
| (b) full stdlib gate, compiler-only max (346 invocations) | 16960 | 0.55 | not exposed |
| (c) z9play `main.zig` `-fsafe` emit | 8368 | 0.38 | pool=4993K, total=2190K |

Row (b) is the maximum over the 346 compiler invocations of a full
`scripts/stdlib/verify_stdlib.sh` gate pass (336 fixtures + 10 crosscheck
modules; each compiler call timed through a wrapper), median of 3 gate passes;
**0.55 s is that largest invocation's wall (`stdlib_tls13_handshake_xmod`),
not the full gate wall**. Whole-build and whole-gate process-tree maxima
include gcc and are **not** compiler RSS. Arena `total` is `perm + mod + scr`;
`pool` is reported separately (not part of `total`). No regression vs the
historical M1 figures below: (a) 20348 vs 20792 KiB (0.98×), (b) 16960 vs
28836 KiB (0.59×), (c) 8368 vs 8140 KiB (1.03×).

#### Historical v123 spill ladder (`-s0` … `-s6`), self-emission

Pool from `--markers --track-memory` (3× identical); max RSS / wall are 3×
medians of `-s<N> -ffast --dump-c89` self-emission runs. *Historical; superseded
by the current v135 ladder above.*

| Level | Arena pool | Max RSS (KiB) | Wall (s) | Notes |
|---|---:|---:|---:|---|
| `-s0` | 18416K (18.0 MB) | 20344 | 6.84 | all disk; fits default `-mm` |
| `-s1` | 51407K (50.2 MB) | 45732 | 7.51 | fits default `-mm` |
| `-s2` | 120400K (117.6 MB) | 95764 | 7.70 | needs `-mm128` |
| `-s3` | 120400K (117.6 MB) | 95816 | 7.78 | needs `-mm128` |
| `-s4` | 124496K (121.6 MB) | 99232 | 7.72 | needs `-mm128` |
| `-s5` | 127568K (124.6 MB) | 101664 | 7.78 | needs `-mm128` |
| `-s6` | 130640K (127.6 MB) | 103008 | 7.84 | all RAM; needs `-mm128` |

`-s2`+ abort with `memory limit exceeded` rc=3 under the default 64 MB `-mm`
budget; all ladder figures at `-s2`+ were measured with `-mm128`. Emission is
byte-identical in every mode (known property; not re-verified here).

#### Historical v123 deep-input evidence (iterative lowering) — 1 MB-stack compiles that used to SIGSEGV

| Shape | rc @ `ulimit -s 1024` | Max RSS (KiB) | Wall (s) | Pre-milestone |
|---|---:|---:|---:|---|
| 120-term runtime-valued `+` chain | 0 | 7084 | 0.05 | rc=139 (SIGSEGV) |
| 300-deep nested blocks `{ { { … } } }` | 0 | 4704 | ~0.00 | rc=139 (SIGSEGV) |

The iterative-lowering milestone (continuation stacks for the lowerer) means
these shapes now compile at 1 MB stack (`ulimit -s 1024`, rc=0) where the
pre-milestone lowerer SIGSEGV'd (rc=139). Mechanism: C-stack recursion →
explicit continuation stacks — the lowerer's C stack is now O(1) instead of
~70 KB + ~18 KB per nesting level. Fixtures are the
`scripts/compiler/gate_lower_depth.sh` case 6 / case 10 shapes, run 3× each
(rc identical every run).

### Phase 1 M1 measured compiler peak (historical fixed point `21c957…`)

One run on the build machine at the **M1 measured** seed v111 / fixed point
`21c957730d268f1e7883176fa5413b65`, fixed-point binary `/tmp/m1_build/zig1_5_clean`, under
`/usr/bin/time -v` (not the 3× medians used for the historical table above). **This section is
historical.** The compiler fixed point has since moved on (M2 T1C-F `45158dce…`, then the
iterative-lowering milestone); the v123-era fixed point `2fc64ffe…` is measured (last full
measurements at seed v123) in the section above, and the current v135 fixed point is
`cf68f192…` (re-measured in the current v135 section at the top of this comparison).

| Workload | Max RSS (KiB) | Wall (s) | Arena |
|---|---:|---:|---|
| (a) fixed-point self-emission (`-ffast --dump-c89`) | 20792 | 5.66 | pool=18871K, total=2921K |
| (b) full stdlib gate, compiler-only max (321 invocations) | 28836 | 0.32 | not exposed |
| (c) z9play `main.zig` `-fsafe` emit | 8140 | 0.36 | pool=4609K, total=2032K |

Row (b) is the maximum over 321 compiler invocations in the full `scripts/stdlib/verify_stdlib.sh`
gate; **0.32 s is that largest invocation's wall, not the full gate wall** (~153 s including gcc).
Whole-build and whole-gate process-tree maxima include gcc and are **not** compiler RSS. Arena
`total` is `perm + mod + scr`; `pool` is reported separately (not part of `total`).

Exact recipe, runnable from the repo root:

```bash
# build the fixed-point binary first
# M1 historical measurement; v123-era fixed point is 2fc64ffedb3ba5f4e8adf35896729e54 (figures last measured at seed v123 a567926c…, above); current v135 fixed point is cf68f192900e7f6618c11e1712b74b3a (re-measured in the current v135 section above)
FIXED_POINT_MD5=21c957730d268f1e7883176fa5413b65 \
  bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m1_build

# (a) compiler-only peak RSS + wall
rm -rf /tmp/m1_emit && mkdir -p /tmp/m1_emit
/usr/bin/time -v /tmp/m1_build/zig1_5_clean -ffast --dump-c89 \
  --output-dir /tmp/m1_emit sf/src/main.zig

# arena (separate run; exposes pool/perm/mod/scr/type_db/total)
rm -rf /tmp/m1_emit_arena && mkdir -p /tmp/m1_emit_arena
/tmp/m1_build/zig1_5_clean --markers --track-memory -ffast --dump-c89 \
  --output-dir /tmp/m1_emit_arena sf/src/main.zig 2>&1 | grep 'track-memory:'
```

**Compiler target:** **<16 MB goal; tracked per Phase 1 milestone.** The current v135
fixed-point self-emission fails on both axes: 20,716 KiB RSS (20.2 MB; +4.2 MB over) and
`pool` 18,677K (18.2 MB; +2.2 MB over). The historical v123-era fixed point `2fc64ffe…`
measured 20,348 KiB RSS (19.9 MB; +3.9 MB over) and pool 18,416K (18.0 MB; +2.0 MB over);
the historical M1 (`21c957…`) also failed on both axes: 20,792 KiB RSS (20.3 MB; +4.3 MB
over) and pool 18,871K (18.4 MB; +2.4 MB over).

**Demo RAM budget (Phase 1):** **16 MB target / 32 MB hard ceiling, enforced with
`ulimit -v 32768` + recorded peak RSS**.

## Minimum Requirements
| Requirement | Linux | Windows 9x |
|---|---|---|
| **RUNNING `zig1`** (compiling a program with a released binary) | `zig1` binary + the 65-file `lib/` std set next to it (auto-discovered; current v149 seed); **~20 MB peak RSS at `-s0` at v135** (historical measurement; v144 fixed point `cd8d283b…`; D-safe 20,716 kB / 20.2 MB; D-fast 20,100 kB / 19.6 MB; spill `-s0` pool 18,677K / 18.2 MB); the <16 MB goal is not met | `zig1_w32.exe` + the std set on the search path (`-I <lib>`; win has no exe-relative auto-discovery); **runtime not measured** — Wine is evidence only |
| **BUILDING the compiler from source** | gcc (C89) for the emitted C — gcc backend **~177 MB** peak (Row E, 181,564 kB); rebuild from the committed seed (no zig0) | the three Windows compilers: `zig1_w32.exe` (OpenWatcom static CLIB, canonical), `zig1_w32_msvc.exe` (MSVC 6 `/MT`), and `z98_mingw_crt_w32.exe` (MinGW CRT, requires `msvcrt.dll`); built from the release seed zip (v135 for 0.21.2); cross-compile not measured here |

> **At v135, Linux `zig1` self-compiles at ~20 MB peak RSS / ~18.2 MB pool at `-s0` — the
> <16 MB compiler goal is not met, and the old ~16 MB RUN claim no longer holds.** Building the
> compiler from source remains dominated by the gcc backend (current Row E ~177 MB; historical
> self-host gcc step ~157 MB; see the gcc caveat above), so a 16 MB machine cannot build it from
> source. Running (compiling programs) and building (recompiling the compiler) have different
> memory profiles; do not assume a small-RAM era machine that can run the released binaries can
> also build them.

## PII/PIII Time Estimates
Engineering estimates — not measurements. Clock-scaled from the table above via
`T_p = T_m × f_m/f_p × k` (`k` = 1.0 default uncertainty multiplier; `f_m` = 4.0 GHz conservative
single-core figure for the 7700X; PII representative 300–450 MHz, PIII 700–1000 MHz). Each entry
is a range spanning the clock band; the low end is the k=1.0 clock-only lower bound.

Current v135 estimates (historical 0.20.0-era estimates are retained in the 0.20.0 release notes):

| Row (median `T_m`) | PII 300–450 MHz (s) | PIII 700–1000 MHz (s) |
|---|---|---|
| D-safe — `zig1 -s0` self (6.91 s) | 61.4 – 92.1 | 27.6 – 39.5 |
| D-fast — `zig1 -s0 -ffast` self (6.73 s) | 59.8 – 89.7 | 26.9 – 38.5 |
| E — gcc `-m32` compile+link (9.56 s) | 85.0 – 127.5 | 38.2 – 54.6 |

**Methodology.** Each row was run 3× under `/usr/bin/time -v` on the reference machine (AMD Ryzen 7
7700X — see machine statement), in fresh scratch directories with fresh output names per repetition
to defeat any incremental caching; the median wall-clock ("Elapsed (wall clock)") and median peak
RSS ("Maximum resident set size (kbytes)") are reported. The PII/PIII figures are clock-scaled
engineering estimates computed as `T_p = T_m × f_m/f_p × k`, where `T_m` is the measured median wall
time on the reference machine, `f_m = 4.0 GHz` is a conservative single-core figure for the 7700X,
`f_p` is the target-era representative clock (PII 300–450 MHz; PIII 700–1000 MHz), and `k = 1.0` is
the default uncertainty multiplier. Each entry is a range spanning the platform's clock band; the
low end is the k=1.0 clock-only lower bound. Memory-bound phases (notably Row E, the gcc backend at
~177 MB measured at v135) scale worse than the clock ratio on small-RAM era machines where paging
dominates — apply 1.5–3× as the stated upper rationale. **These are engineering estimates; verify on
the operator's real VM.**

## Getting Started / Building from Source / Building a Program
Two workflows: run a released binary, or build `zig1` from the source archive.

**Build `zig1` from source** — download the release source archive **`zig1_src.tgz`** (linux) or
**`zig1_src.zip`** (win9x-unpackable). It contains the full compiler source tree (`sf/src/*.zig` +
`sf/src/include/`), a `RELEASE_README.txt` with the exact where/how build commands, and a
`lib/` std payload. The current repo seed is **v149** with **65** std files; the historical
0.21.2 release source archive carried 51. This source is a Zig-subset program, **not** directly compilable by a C toolchain: the
seed model is the only rebuild path — rebuild it from the committed seed
`release/seed/zig1-seed.tgz` with only `gcc` via
`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out_dir>` (two-hop fixed-point
closure; zig0 is retired). For the legacy bootstrap (`zig0`) toolchain build, see
[README_zig0_bootstrap.md](README_zig0_bootstrap.md) and [docs/Building.md](docs/Building.md).

**Compile a program with `zig1`** — `zig1 -o <dir> prog.zig` emits a **complete self-contained
C89 tree** (needed-only modules + runtime/platform headers + runtime sources) and a companion
`build_target.sh`. Then build it:
```bash
zig1 -o out hello.zig
sh out/build_target.sh          # or: ./out/build_target.sh after the first run
./out/prog
```
`build_target.sh` compiles the emitted `<dir>/*.c` with `-I .` and links the emitted runtime
objects, so no repo include path and no hand-listed runtime trio are needed. `--dump-c89` is now a
**debug alias**: on its own it writes a single C file to stdout; with `-o <dir>` it writes
per-module `.c`/`.h` files.
(For the current repo seed, install the **65-file `lib/`** — `std.zig` plus 64 `std_*.zig` —
next to the `zig1` binary in a `lib/` dir for `@import("std")`; the historical 0.21.2 release
shipped 51 files. Windows users pass `-I <lib>` explicitly.)
The authoritative, always-verified command set lives in [docs/sf/QUICK_REF.md](docs/sf/QUICK_REF.md);
the build script is `scripts/seed/build_from_seed.sh`. Release binaries (`zig1_linux32` /
`zig1_w32.exe`) ship with a sibling `lib/` and `MANIFEST.txt` (md5/sha256/sizes).

**Historical release artifacts (0.21.2, seed v135; separate from the current v149/65-file repo seed — see [Determinism](#determinism))** — `zig1_linux32` (md5 `cf68f192900e7f6618c11e1712b74b3a`, the v135
fixed point); `zig1_w32.exe` (OpenWatcom static CLIB, md5 `3e944a2c4d4842422ff9108d534a9f42`);
`zig1_w32_msvc.exe` (MSVC 6 `/MT`, md5 `1141ecbf15e720da955b0434eeb8624d`); `z98_mingw_crt_w32.exe`
(MinGW CRT, md5 `f08ddae7fc7924e7a372174c437ed380`; requires `msvcrt.dll`);
`z98-0.21.2-win9x-binaries.zip` (the three compilers + hashes); `src_c_zig1_linux.tgz` /
`src_c_zig1_w32.zip`; `zig1_src.tgz` / `zig1_src.zip`; the v135 seed archives `zig1-seed.tgz` /
`zig1_seed_w9.zip`; the 51-file `lib/` (manifest md5 `62008632c1f057c42b04bf5883f6da5d`); and
`MANIFEST.txt`. No zig0 ships in 0.21.2.

## Command-Line Flags
`zig1`'s flag set (the self-hosted compiler; for the `zig0` bootstrap flags see
[README_zig0_bootstrap.md](README_zig0_bootstrap.md)):

| Flag | Purpose |
|---|---|
| `-o <dir>` / `--output-dir <dir>` | Output dir for emitted `.c`/`.h`; setting it turns on default C89 emission (needed-only modules + self-contained runtime + `build_target.sh`) |
| `--dump-c89` | Emit C89 (debug alias): single-file to stdout, or per-module `.c`/`.h` when `-o` is set |
| `-I <dir>` / `--lib-dir <dir>` | Add a module search dir for `@import` (importer dir, then `-I` dirs in order, then `<exe_dir>/lib`, then CWD) |
| `-osl` / `-osw` | Target OS: linux (default) / windows; folds `@isWindows()` |
| `--target <linux\|windows>` | Alias for the target OS |
| `-fsafe` | **Default.** Enable the six runtime checks (cast / div-mod / shift-count / null-unwrap / index-OOB / integer-overflow) and the `undefined` `0xAA` poison fill |
| `-ffast` | Disable the six runtime checks and poison fill (used for the compiler self-build). `unreachable`/`@panic` still trap in both modes |
| `-s<N>` | Spill level 0–6 (default `-s0`): how many of the six compiler-state spills live in RAM instead of `.zig1_*.tmp` disk files. Deactivation order S-AST → S-LIR → S-HASH → S-RES → S-SIDE → S-EXTRA. Higher `-s` = more RAM, less disk I/O; emission byte-identical in every mode. **Current measured ladder (v135, self-emission `--markers --track-memory` pool):** `-s0` pool=18677K (18.2 MB, all disk); `-s1` pool=50421K (49.2 MB); `-s2`/`-s3` pool=119477K (116.7 MB); `-s4` pool=123573K (120.7 MB); `-s5` pool=126645K (123.7 MB); `-s6` pool=131765K (128.7 MB, all RAM; needs `-mm160` — the 128 MB limit ICEs). Historical (superseded): v123-era `2fc64ffe…` pool=18416K/51407K/120400K/124496K/127568K/130640K; `553a39b4…` ≈ 13.8/33.1/70.0/73.0/74.0/77.0 MB pool; M1 `21c957…` `-s0` pool=18871K. Bare/non-digit/out-of-range `-s` = error rc=1 |
| `-mm<N>` | Hard pool budget in MB (default 64). Levels whose pool exceeds the budget abort with `memory limit exceeded` rc=3 (e.g. `-s2`+ need `-mm128`) |
| `-m <size>` / `--max-mem <size>` | Pool memory budget with k/M/G suffix |
| `--track-memory`, `--markers` | Memory tracking / pipeline markers (e.g. the `pool=` report line) |
| `-e <n>` / `--max-errors <n>` | Maximum errors before abort |
| `-q` / `--quiet` | Quiet mode |
| `-W` / `--warnings-as-errors`, `--warn-all`, `--warn-error` | Warning policy |
| `--color <mode>`, `--error-format <fmt>` | Diagnostic rendering |
| `--no-null-check`, `--no-lifetime-check`, `--no-leak-check` | Disable individual static analyzers |
| `--test`, `--sanity-test` | Compiler self-test / sanity-test mode |

Runtime safety defaults to `-fsafe`. The compiler self-build passes `-ffast`, so the compiler's own emitted C is not check-instrumented; a user program's emitted C (default `-fsafe`) will differ accordingly.

## Running Tests
- **Unit/analyzer tests**: the sf test binaries under `sf/src/tests/` (e.g. the analyzer test bin),
  built via `sf/scripts/build_test.sh`; plus `zig1 --test` / `--sanity-test`.
- **Corpus gate**: the corpus universe is listed by `scripts/corpus/list_corpus_dirs.sh`
  (manifest `repro/mi_matrix/EXPECTED_FAIL.md`, v130) — run `zig1 --dump-c89` + gcc `-c` per dir,
  classified OK/FAIL/GREEN per the QUICK_REF classifier. No corpus total is asserted.
- **Example matrix**: 29 `examples/z98` programs, 29/29 dump/gcc/link.
- **Golden fixtures**: 9/9 golden outputs.
- **Upgraded-showcase gate**: `scripts/closeout/verify_upgraded.sh` (A1–B7) gates
  `lisp_interpreter_upgraded` and `rogue_mud_upgraded` against their committed canonical/demo
  goldens (with `scripts/closeout/flush.c` for timeout-safe server output).
- The bootstrap-era root `./test.sh` runner is gone from this branch; the live suites above are the
  current verification surface. See [docs/sf/QUICK_REF.md](docs/sf/QUICK_REF.md) for exact commands.

## Minimal Distribution
To build a Z98 program on a target machine you need:
1. **`zig1`** (or `zig1_w32.exe`) — the self-hosted compiler binary.
2. **The std modules** — the shipped `lib/` set is **65 files**: `std.zig` plus 64
   `std_*.zig`. `std.zig` re-exports the 17 core modules (`io`, `fmt`, `arena`, `str`,
   `mem`, `math`, `debug`, `net`, `async`, `bits`, `os`, `time`, `page`, `gpa`,
   `pool`, `buf`, `fold`); the by-path modules (38 public + 9 `*_pal` companions) are the same inventory documented
   under [Standard Library](#standard-library) above
   (linux: in a `lib/` dir beside the binary; windows: on the `-I` search path).
3. **Runtime sources & headers** — emitted into the program's output dir by `zig1 -o <dir>`
   (`zig_runtime.c`/`.h`, `zig_pal.c`, `c_exit.c`, `zig_compat.h`, and `net_prelude.h` when
   `std_net` is emitted); the canonical dev copies live in `sf/src/include/`.

## Documentation
- [docs/](docs/) — building, language spec, design, and reference docs.
- [sf/docs/initial_design/](sf/docs/initial_design/) — design intent as first thought (`Design_p2.md`,
  `TYPE_SYSTEM_p2.md`, `LIR_C89_Emission_p2.md`, and the design corpus); [sf/docs/tech_docs/](sf/docs/tech_docs/)
  records the observed implementation. The **QUICK_REF** cheat sheet with the authoritative
  build/compile/gate commands stays in [docs/sf/](docs/sf/).
- [docs/reference/Language_Spec_Z98.md](docs/reference/Language_Spec_Z98.md) — the Z98 language
  specification.
- [sf/docs/tech_docs/12_async_coroutines.md](sf/docs/tech_docs/12_async_coroutines.md) — the
  async/coroutine deep-dive (`@async*` builtins, step machine, `Context` ABI, `std.async`).
- [docs/superpowers/](docs/superpowers/) — plan/spec/design history for the self-hosted era.
- [repro/mi_matrix/EXPECTED_FAIL.md](repro/mi_matrix/EXPECTED_FAIL.md) — the mi_matrix corpus
  manifest (v130), paired with the canonical generator
  [scripts/corpus/list_corpus_dirs.sh](scripts/corpus/list_corpus_dirs.sh).
- [README_zig0_bootstrap.md](README_zig0_bootstrap.md) — the preserved bootstrap-era (`zig0`)
  README, kept byte-verbatim.

## Standard Library  [updated: 2026-11-11 — v149]
The Z98 standard library lives in `sf/src/`. The shipped seed payload is **65**
files: `std.zig` plus **64** `std_*.zig`. `std.zig` re-exports **17** modules
(`io`, `fmt`, `arena`, `str`, `mem`, `math`, `debug`, `net`, `async`, `bits`,
`os`, `time`, `page`, `gpa`, `pool`, `buf`, `fold`); the remaining **47**
`std_*.zig` files are imported by path — **38** public modules (`std_asn1`, `std_base64`,
`std_bencode`, `std_cipher`, `std_crypto`, `std_ddraw`, `std_deflate`, `std_dinput`, `std_dsound`, `std_ecc`, `std_file`, `std_fft`, `std_gfx`,
`std_heap`, `std_hex`, `std_hpa`, `std_hpack`, `std_http`, `std_http2`, `std_lz4`, `std_map`, `std_noise`,
`std_num`, `std_parse`, `std_pathfind`, `std_physics`, `std_rand`, `std_rle`,
`std_sort`, `std_stdin`, `std_stream`, `std_tcpip`, `std_tls`, `std_tls_io`, `std_utf8`,
`std_wireguard`, `std_x509`, `std_zstd`) plus **9** platform companions
(`std_ddraw_pal`, `std_dinput_pal`, `std_dsound_pal`, `std_file_pal`, `std_gfx_pal`, `std_os_pal`, `std_page_pal`, `std_stdin_pal`,
`std_time_pal`). `std_page` provides the portable page reservation API
(`pageInit`/`pageReserve`/`pageCommit`/`pageDecommit`/`pageRelease`), `std_gpa`
the TLSF/medium/large general-purpose allocator (default `target64`: 64 KiB
medium cap, 2 MiB chunks, 64 MB target; `align` a power of two in `[8, 4096]`;
`safe_checks` explicit, not implied by `-fsafe`), and `std_pool` a fixed-block
pool; thread-local storage (TLS) remains design-only and `.encrypted` is deferred. `std_crypto` provides streaming SHA-1/256/384/512, MD5,
CRC-32, HMAC-SHA256, HKDF, BLAKE2s, RC4, modexp, and RSA PKCS#1 v1.5 / PSS verify; `std_cipher`
provides ChaCha20, Poly1305, ChaCha20-Poly1305, AES-128, and AES-128-GCM (const T-tables);
`std_ecc` provides X25519, P-256 keygen/ECDH/ECDSA verify, and P-384 ECDSA verify; `std_asn1`
provides the streaming DER reader and `std_x509` certificate parsing, leaf-to-anchor chain
verification, SAN dNSName hostname matching, and the pinned trust-store loader; `std_tls`
provides the sans-I/O TLS 1.2/1.3 record layer and client handshakes (TLS 1.3 suites,
x25519, HKDF-Expand-Label key schedule, ECDSA/P-384/RSA-PSS CertificateVerify), ALPN
negotiation (`alpn_h2`, `tlsAlpnSelected`), and the opt-in `prefer_chacha20` suite/group
ordering; `std_tls_io` provides the nonblocking `TlsIo` socket driver over `std_net`
(handshake/read/write pumps returning `WouldBlock`); `std_hpack` provides full HPACK
decode with a literal-only encoder; `std_http2` provides the coroutine-driven HTTP/2
client (frames, connection reuse, multiplexing, flow control, TLS+ALPN and h2c prior
knowledge; a non-suspending `http2Pump`, suspending `http2Wait`, leased streams released
with `http2Release`, and caller-owned `out.body` capacity capped at 1 MiB);
`std_wireguard` provides the sans-I/O WireGuard initiator (NoiseIK handshake, transport
data path, timers, replay window, and cookie consumption); and `std_tcpip` provides the
client-only userspace IPv4/TCP/UDP/DNS/ICMP stack driven by a sans-I/O poll pump. See the
guide for the library's model and an index that links each domain's detailed doc:


- [STD_README.MD](STD_README.MD) — the Z98 standard library guide and index.

## Example Showcase
`examples/z98/` carries the maintained example suite (matrix 29/29 dump/gcc/link), including
complete programs that exercise the language-wins features and the PAL/networking runtime:
- **`game_of_life`** — interactive simulation on the PAL UI layer.
- **`lisp_interpreter_curr`** and the upgraded **`lisp_interpreter_upgraded`** — a complete Lisp
  interpreter with tagged unions, deep switches and arena GC (upgraded edition adds committed
  canonical/demo goldens under `demo/`).
- **`json_parser`** — JSON parser exercising optional types and error handling.
- **`demo/tls_demo`** — real HTTPS fetch with the TLS 1.2/1.3 client, X.509
  validation, and the pinned trust store; Linux and `-osw` Win9x builds.
- **`demo/wireguard_demo`** — userspace TCP/IP (`std_tcpip`) through a real
  WireGuard tunnel to `mud_server`; Linux and `-osw` Win9x builds.
- **`mud_server`** — non-blocking telnet server over `std_net`, with one coroutine task per client.
- **`rogue_mud`** and the upgraded **`rogue_mud_upgraded`** — a networked roguelike (A* pathfinding,
  BSP maps, export symbols, coroutine NPC AI / per-client broadcast, and a `demo/` client/server pair
  `net_main.zig` / `net_demo_client.zig` using `std_net.createTcpClient`).
- **`z9git`** — a read-only Git client (local/`file://` plus smart HTTP(S) clone, log, checkout;
  shallow/partial clone, resumable prefix packs, and a bounded external-memory idx writer).
- **`z9zstddecomp`** — a single-shot zstd frame decompressor CLI (`std_zstd` frames, skippable
  frames, checksums, and RFC 8878 magic/raw dictionaries; bounded output and window caps).
- **`z9gb`** — a DMG (original Game Boy) and CGB (Game Boy Color) emulator, now at **P5
  (SM83 dynarec)**: CPU, MMU/timer/serial, scanline PPU, MBC1/MBC3(+RTC)/MBC5, battery
  `.sav`/`.rtc` saves, DMG/CGB APU, CGB color palettes/attributes, VRAM/WRAM banking,
  double-speed, HDMA, a deterministic headless backend, plus a Win32 backend with
  DirectDraw presentation, DirectInput8 keyboard/gamepad (keyboard fallback), QPC pacing,
  DirectSound (WinMM `waveOut` fallback), and wired JOYP input; the Win32/x86 `--dynarec`
  uses a separate 1 MiB executable cache with interpreter fallback. CGB is opt-in with
  `--cgb`; a CGB-only cartridge requires it (`CgbRequired`, exit 2). Gates:
  `tests/tier_dmg.sh` (`--all`, `--gates`), `tests/tier_cgb.sh` (CGB hard gates
  `cgb-acid2`, `cgb_sound`, `interrupt_time`), `tests/tier_dynarec.sh`,
  `tests/tier_smoke.sh`, `tests/tier_audio.sh --gate`, `tests/tier_win32.sh --smoke`,
  `tests/tier_perf.sh` (with `--compat --user-roms` for the dynarec workload matrix),
  plus `tests/measure_rss.sh` (`--cgb` for CGB measurements).
  Build/link prerequisites for Linux/*nix and Win9x are in
  [`examples/z98/z9gb/README.md`](examples/z98/z9gb/README.md).
- Plus the classic single/multi-module programs (`hello`, `prime`, `fibonacci`, `days_in_month`,
  `heapsort`, `quicksort`, `sort_strings`, `mandelbrot`, `lzw`, `func_ptr_return`, `tco_*`).

See `scripts/closeout/verify_upgraded.sh` for the canonical/demo golden gates on the upgraded
showcase programs.
