# Z98 0.21.2 "Terephthalic Acid" Release Notes

This release supersedes the 0.21.1 staging and is the first that ships the
**Windows 9x/NT compiler binaries** together with the Linux artifacts. It rolls
up the v133-v135 work: the z9play/z9torr optimizations and example idiom
modernization, plus the switch, negative-case, and enum emission fixes. The
compiler fixed point moves to seed **v135**
(`cf68f192900e7f6618c11e1712b74b3a`).

## 🚀 Timeline

- **2026-11-03** — Z98 0.21.1 "Terephthalic Acid" (hotfix), seed **v132**.
- **2026-11-04** — seed **v133** (`std_fft` + z9play/z9torr optimizations +
  example idioms); seed **v134** (64-bit switch lowering, negative integer case
  items, signed enum backings); seed **v135** (33-63-bit carrier switches,
  parenthesized/bool case items, portable wide enum macros, enum storage
  limits).
- **2026-11-05** — This release: **Z98 0.21.2 "Terephthalic Acid"**, seed
  **v135**, with the operator-built Windows compilers.

## ✨ Headline Capabilities

**Portable switch / case emission**
- `switch` conditions whose C carrier is 64-bit (including 33-63-bit arbitrary
  integers and enums backed by them) lower to a portable `if`/`else if`/`else`
  chain instead of a 64-bit C `switch` (OpenWatcom `E1078`). 32-bit switches are
  byte-identical to the previous release.
- Negative integer case items match: literals, module-level constants, range
  endpoints, and parenthesized forms. A negative item on an unsigned condition
  is a level-0 `error[3062]`; bool items follow the documented rules.

**Enums**
- Signed integer backings and negative discriminants are accepted; labels and
  macros follow the backing's signedness.
- Wide enum macros are portable C89 (`Z98_I64_C`/`Z98_U64_C`, `Z98_I64_MIN`,
  `(-2147483647 - 1)`); `enum_value_table` no longer truncates values above
  `u32`.
- An implicit successor past the i64 storage maximum rejects instead of
  silently duplicating a member; `enum(u64)` above i64 max rejects with a clear
  `error[3000]` (documented limitation D13).

**Performance**
- z9play's Ogg Vorbis IMDCT uses a split-radix FFT with cached window/slope
  tables: about **170x faster** on the 2 s fixture (5.35 s -> 0.031 s); FLAC is
  unchanged (O(n)).
- z9torr uses O(1) piece/block accounting (no per-block rescans; download output
  SHA-1 unchanged).

**Examples**
- Example code uses `for` captures, `defer`/`errdefer`, labeled flow, `switch`
  and tag prongs, and `std.fold`; behavior and outputs are unchanged. 471
  source `= undefined` sites were replaced with explicit or zero initialization,
  and rotating seed-md5 pins were dropped from the tiers.

**Windows binaries**
- `zig1_w32.exe` — OpenWatcom 1.9 static CLIB, canonical Win9x compiler;
  imports KERNEL32 + USER32 only, no `msvcrt.dll`; passes the 9x import gate.
- `zig1_w32_msvc.exe` — MSVC 6 `/MT`, no `msvcrt.dll`; passes the 9x gate.
- `z98_mingw_crt_w32.exe` — MinGW CRT build; requires `msvcrt.dll`; optional
  fallback, not the Win9x static-CRT binary.
- `z98-0.21.2-win9x-binaries.zip` bundles the three binaries and their hashes.
- All three were built on the operator's Windows 98 machine from the v135 seed
  zip and emit C byte-identical to the v135 Linux reference build.

## 🛠️ Build Machine & Toolchain

The Linux release artifacts were built and measured on an **AMD Ryzen 7 7700X
8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian GNU/Linux 12 (bookworm)**
machine with **gcc 12.2.0**, **i686-w64-mingw32-gcc 12-win32**, **Wine 8.0**, and
`gcc -m32` available. The Windows binaries were built and manually tested on the
operator's Windows 98 machine with **MSVC 6**, **OpenWatcom 1.9**, and
**MinGW gcc 3.4.5**; the emitted C from the examples was cross-built with both
MSVC 6 and OpenWatcom 1.9.

## 💾 Minimum Requirements

At v135, RUN is **~20 MB** peak RSS at `-s0`: D-safe **6.91 s / 20,716 kB**,
D-fast **6.73 s / 20,100 kB** (medians of 3). BUILD from source is dominated by
the gcc backend: Row E measured **9.56 s / 181,564 kB** (~177 MB). The Windows
runtime is **not measured**; Wine and the operator's VM are evidence only.

Measured spill ladder at v135 (`-ffast --markers --track-memory`; medians of 3):

| Level | Peak RSS (KiB) | Pool (K) |
|---|---:|---:|
| `-s0` | 20,284 | 18,677 |
| `-s1` | 45,900 | 50,421 |
| `-s2` (`-mm128`) | 95,532 | 119,477 |
| `-s3` (`-mm128`) | 95,180 | 119,477 |
| `-s4` (`-mm128`) | 99,368 | 123,573 |
| `-s5` (`-mm128`) | 101,336 | 126,645 |
| `-s6` (`-mm160`) | 104,080 | 131,765 |

**`-s6` now needs `-mm160`:** the v135 pool peak is 131,765K, above the 128 MB
limit used in earlier ladders (a `-mm128` run ICEs with rc 3).

Optional deep-input evidence at a 1 MB stack: the 120-term `+` chain ran
**0.05 s / 7,112-7,256 kB**; the 300-deep block fixture ran **0.00 s /
4,264-4,516 kB**.

## ⏱️ PII/PIII Time Estimates

Engineering estimates — **not measurements**. Clock-scaled from the v135
medians via `T_p = T_m × f_m/f_p × k` (`k = 1.0`; `f_m` = 4.0 GHz conservative
single-core figure for the 7700X; PII 300-450 MHz, PIII 700-1000 MHz).

| Row | Median `T_m` (s) | PII 300-450 MHz (s) | PIII 700-1000 MHz (s) |
|---|---:|---:|---:|
| D-safe | 6.91 | 61.4 - 92.1 | 27.6 - 39.5 |
| D-fast | 6.73 | 59.8 - 89.7 | 26.9 - 38.5 |
| E (gcc compile+link) | 9.56 | 85.0 - 127.5 | 38.2 - 54.6 |

Row E is the memory-bound row (~177 MB peak RSS) and carries the 1.5-3x
memory-band caveat: roughly up to ~382 s on PII and ~164 s on PIII at the worst
end. D-safe/D-fast peak at ~20 MB and track the clock ratio more closely.

## 📦 Release Artifacts

The staged 0.21.2 set is **zig1 + seed + three Windows compilers, no zig0**
(git-ignored `release/staging/0.21.2/`):

| File | Size (B) | md5 | Notes |
|---|---:|---|---|
| `zig1_linux32` | 3,614,976 | `cf68f192900e7f6618c11e1712b74b3a` | v135 seed binary; ELF 32-bit i386; equals the fixed point |
| `src_c_zig1_linux.tgz` | 2,059,825 | `6012f66a134236bf201ac910ae9b97a1` | self-emission C89 archive (52 `.c` + 51 `.h` raw; 48 + 49 canonical) |
| `src_c_zig1_w32.zip` | 2,084,208 | `b30b85ddacb3f9f85bb9fa6d79bb7fea` | same C/H set, zip; byte-identical members |
| `zig1_src.tgz` | 1,123,054 | `c374b266a3a096d363b3c29f19cf48c5` | `sf/src` + 52-file `lib/` + `RELEASE_README.txt` (224 files) |
| `zig1_src.zip` | 1,194,171 | `6f114e150addbfda6ca6298d9fcbd230` | identical tree, zip format |
| `zig1-seed.tgz` | 3,737,713 | `c01a8261aa9b9d84f2d414724011b3db` | v135 seed archive |
| `zig1_seed_w9.zip` | 2,622,216 | `49242d99702f0521ac5d06a29c2d96c3` | v135 Win9x companion seed (sources + build scripts; no prebuilt exe) |
| `zig1_w32.exe` | 1,712,128 | `3e944a2c4d4842422ff9108d534a9f42` | OpenWatcom static CLIB Win9x compiler (canonical; no msvcrt) |
| `zig1_w32_msvc.exe` | 1,764,352 | `1141ecbf15e720da955b0434eeb8624d` | MSVC 6 `/MT` Win9x compiler (no msvcrt) |
| `z98_mingw_crt_w32.exe` | 2,750,720 | `f08ddae7fc7924e7a372174c437ed380` | MinGW CRT compiler (requires msvcrt.dll; optional) |
| `z98-0.21.2-win9x-binaries.zip` | 2,742,990 | `5c0bded892f12465a391e13b46fab34c` | bundle of the three Windows compilers + hashes README |
| `W32_BUILDS.md` | 3,592 | `2dc197ce14f32897f152f0a393b64e64` | Windows build provenance, recipes, imports, gate results |

The shipped `lib/` payload is **51** std files (`std.zig` + 50 `std_*.zig`);
`lib/manifest.md5` md5 is `62008632c1f057c42b04bf5883f6da5d`. `zig1_src` ships
224 files (171 `sf/src` + 52 `lib/` + `RELEASE_README.txt`; `lib/` includes
`manifest.md5`). `zig1_w32.exe` is the canonical Win9x static-CRT compiler;
`zig1_w32_msvc.exe` is the MSVC variant; the MinGW build is the optional CRT
fallback that requires `msvcrt.dll`.

## ⚠️ Known Issues

Open-only entries (no fixed defect is listed):

- **D3** — conditional `@import` still parse-loads a sema-dead arm outside the parse probe; false reject only.
- **D4** — static-analyzer cluster (dead-arm parity, unseeded params/returns, capture aliases, provenance lookup, test drift); false diagnostics possible on complex code.
- **D5** — an `extern fn` with a body is accepted then emitted as a declaration only; non-cdecl callbacks cannot be defined.
- **D7.3** — a nested write through `arr[i].field[0..]` can target a by-value temporary; the store is silently lost.
- **D8** — stdout is split between C stdio builtins and PAL `std.fmt`; mixed writes can reorder or lose buffered output on abnormal exit (mitigated in `z9play` only).
- **D10** — no first-class calling conventions; Win32 `WNDPROC`/callbacks need a C trampoline.
- **D12** — a module-scope untyped array literal (`pub var arr: [3]u32 = .{...}`) emits an invalid array-to-array C assignment.
- **D13** — `enum(u64)` discriminants above the i64 storage maximum are unsupported (clean `error[3000]`; no wrong code).

## 🔧 Breaking Changes / Upgrade Notes

- A negative integer case item on an **unsigned** switch condition is now a
  level-0 `error[3062]` (previously accepted with incorrect behavior).
- An enum discriminant, explicit or implicit, beyond the i64 storage maximum is
  now rejected (`error[3000]`); `enum(u64)` above i64 max remains unsupported
  (D13).
- The canonical Win9x compiler is the OpenWatcom static-CLIB build; the MinGW
  CRT build is a separate optional artifact requiring `msvcrt.dll`.
- Programs built with an older 0.21.1 emitted build script should be re-emitted
  with 0.21.2 to pick up the current runtime and link lines.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Zni005 (DeepseekV4+Opencode)*

---

# Z98 0.21.1 "Terephthalic Acid" (hotfix) Release Notes

This is a **hotfix** for **0.21.0 "Terephthalic Acid"**. It fixes programs built
for, or cross-built for, Windows 9x: MinGW chunked links no longer embed CRT
startup, GUI programs no longer depend on a C `WndProc` trampoline or a static
`DDRAW.DLL`, and `z9play` console output is live. There is **no new language
feature and no breaking change**; the compiler fixed point moves to seed
**v132** (`108fed5c1d143d0d905fdb3e2fd120e9`).

## 🚀 Timeline

- **2026-10-29** — Z98 **0.21.0 "Terephthalic Acid"** released (seed v129).
- **2026-11-02** — Win9x emission fixes rotate the seed v130 → v131 (emitted
  scripts self-sufficient, stdout-only logging); they are included here.
- **2026-11-03** — This hotfix: **Z98 0.21.1 "Terephthalic Acid" (hotfix)**,
  seed **v132**; the Win9x link/GUI/console defects from 0.21.0 are fixed.

## ✨ Headline Capabilities

**Win9x link correctness**
- Emitted MinGW partial/chunk links use `-nostdlib`; only the final link keeps
  startup. The no-CRT final link adds `-lwinmm` for the waveOut path.

**no-CRT runtime hardening**
- `strlen`/`memcpy`/`memset`/`strncmp` shims are opaque to `-O2` idiom
  conversion (no self-call recursion), covered by a static self-call gate and a
  Wine `-O2` smoke.

**GUI without the trampoline**
- `std_gfx_pal` registers `DefWindowProcA` and polls `IsWindow`/`GetClientRect`
  for close/minimize/resize; the deleted C `WndProc` shim is no longer shipped
  or required.
- DirectDraw is loaded dynamically (`LoadLibraryA("ddraw.dll")` +
  `GetProcAddress`) with the 16-color GDI fallback; GUI executables import no
  `DDRAW.DLL`. MSVC/MinGW GUI link lines add `user32`/`gdi32`.

**z9play live output**
- Console metadata/status/errors/final output flush immediately, including long
  `--wav` decodes (start + periodic progress lines); the default no-CRT link
  gets a no-op `fflush` shim.

**Examples**
- Every `examples/z98/*/README.md` documents working Linux and Windows zig1
  build recipes.

## 🛠️ Build Machine & Toolchain

Unchanged from 0.21.0. The Linux release artifacts were built and measured on an
**AMD Ryzen 7 7700X 8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian
GNU/Linux 12 (bookworm)** machine with **gcc 12.2.0**,
**i686-w64-mingw32-gcc 12-win32**, **Wine 8.0**, and `gcc -m32` available. No
MSVC or OpenWatcom is available locally; the Win9x `zig1_w32.exe` is the
operator-built static-CRT binary. Linux artifacts are `gcc -m32` builds;
Windows archives are built in the `-osw` target flavour.

## 💾 Minimum Requirements

**Unchanged from 0.21.0.** At v132, RUN is **~20 MB** peak RSS at `-s0`: D-safe
**6.85 s / 20,300 kB**, D-fast **6.66 s / 19,920 kB** (medians of 3). BUILD from
source is dominated by the gcc backend: Row E measured **9.28 s / 181,432 kB**
(~177 MB). The Windows runtime is **not measured**; Wine is evidence only.

Measured spill ladder at v132 (`-ffast --markers --track-memory`; medians of 3):

| Level | Peak RSS (KiB) | Pool (K) |
|---|---:|---:|
| `-s0` | 19,844 | 18,645 |
| `-s1` | 45,648 | 50,402 |
| `-s2` (`-mm128`) | 95,152 | 119,394 |
| `-s3` (`-mm128`) | 95,188 | 119,394 |
| `-s4` (`-mm128`) | 98,748 | 123,490 |
| `-s5` (`-mm128`) | 101,272 | 126,562 |
| `-s6` (`-mm128`) | 103,108 | 130,658 |

Optional deep-input evidence at a 1 MB stack: the 120-term `+` chain ran
**0.05 s / 7,064 kB**; the 300-deep block fixture ran **0.00 s / 4,636 kB**.

## ⏱️ PII/PIII Time Estimates

Engineering estimates — **not measurements**. Clock-scaled from the v132
medians via `T_p = T_m × f_m/f_p × k` (`k = 1.0`; `f_m` = 4.0 GHz conservative
single-core figure for the 7700X; PII 300–450 MHz, PIII 700–1000 MHz).

| Row | Median `T_m` (s) | PII 300–450 MHz (s) | PIII 700–1000 MHz (s) |
|---|---:|---:|---:|
| D-safe | 6.85 | 60.9 – 91.3 | 27.4 – 39.1 |
| D-fast | 6.66 | 59.2 – 88.8 | 26.6 – 38.1 |
| E (gcc compile+link) | 9.28 | 82.5 – 123.7 | 37.1 – 53.0 |

Row E is the memory-bound row (~177 MB peak RSS) and carries the 1.5–3×
memory-band caveat: roughly up to ~371 s on PII and ~159 s on PIII at the worst
end. D-safe/D-fast peak at ~20 MB and track the clock ratio more closely.
Verify on the operator's real VM.

## 📦 Release Artifacts

The staged 0.21.1 set is **zig1 + seed, no zig0** (git-ignored
`release/staging/0.21.1/`):

| File | Size (B) | md5 | Notes |
|---|---:|---|---|
| `zig1_linux32` | 3,585,348 | `108fed5c1d143d0d905fdb3e2fd120e9` | v132 seed binary; ELF 32-bit i386; equals the fixed point |
| `src_c_zig1_linux.tgz` | 2,040,283 | `3bbd81a92df14d3a6eff6b2d42e5efe6` | self-emission C89 archive (52 `.c` + 51 `.h` raw; 48 + 49 canonical) |
| `src_c_zig1_w32.zip` | 2,068,392 | `d41f945c4bee2f5206826408311cb6a6` | `-osw` self-emission; byte-identical members to the linux flavour |
| `zig1_src.tgz` | 1,101,827 | `d178e3c0c48939a3fa1cec4672cace05` | `sf/src` + 50-file `lib/` + `RELEASE_README.txt` |
| `zig1_src.zip` | 1,181,078 | `16e848832097c8b18cf451f73d746863` | identical tree, zip format |
| `zig1-seed.tgz` | 3,702,406 | `9244ae831cb41ee9b71b1187a9f23820` | v132 seed archive |
| `zig1_seed_w9.zip` | 2,596,656 | `2cfd893244ff3a7fbc317bb4221babdf` | v132 Win9x companion seed (sources + build scripts; no prebuilt exe) |
| `zig1_w32.exe` | PENDING | operator-built static-CRT; hash to be recorded in MANIFEST.txt after the operator build | PE32 i386 Win9x-class compiler; pending operator build |

The shipped `lib/` payload is **50** std files (`std.zig` + 49 `std_*.zig`);
`lib/manifest.md5` md5 is `a7ada3edfa99ba091a5ef1096550b908` (changed because
`std_gfx_pal.zig` is part of `lib/`). `zig1_w32.exe` is the **operator-built
static-CRT** compiler (MSVC `/MT` or OpenWatcom static CLIB): it embeds the C
runtime, has **no `msvcrt.dll` dependency**, and is verified with the `9x`
import gate when it arrives. The MinGW CRT build is a **separate optional
artifact** that **does require `msvcrt.dll`**; it is not the Win9x binary.
`zig1_src` ships 222 files (170 `sf/src` + 51 `lib/` + `RELEASE_README.txt`):
the obsolete `sf/src/include/zig_gfx_wndproc.c` shim is deleted, so the count is
one lower than 0.21.0's 223.

## ⚠️ Known Issues

Open-only entries after Phase 2.5 (no fixed defect is listed):

- **D3** — conditional `@import` still parse-loads a sema-dead arm outside the parse probe; false reject only.
- **D4** — static-analyzer cluster (dead-arm parity, unseeded params/returns, capture aliases, provenance lookup, test drift); false diagnostics possible on complex code.
- **D5** — an `extern fn` with a body is accepted then emitted as a declaration only; non-cdecl callbacks cannot be defined.
- **D7.3** — a nested write through `arr[i].field[0..]` can target a by-value temporary; the store is silently lost.
- **D8** — stdout is split between C stdio builtins and PAL `std.fmt`; mixed writes can reorder or lose buffered output on abnormal exit. **Mitigated in `z9play` only** (0.21.1 adds explicit flushes); no compiler-level change.
- **D10** — no first-class calling conventions; Win32 `WNDPROC`/callbacks need a C trampoline. 0.21.1 removes the `std_gfx` shim by polling instead, but the language limitation remains.
- **D12** — a module-scope untyped array literal (`pub var arr: [3]u32 = .{...}`) emits an invalid array-to-array C assignment.

## 🔧 Breaking Changes / Upgrade Notes

**None.** Commands, flags, diagnostics, the language surface, and the 50-file
`lib/` set are unchanged from 0.21.0. Programs built with an older 0.21.0
emitted build script should be re-emitted with 0.21.1 to pick up the MinGW/GUI
link fixes.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Zni005 (DeepseekV4+Opencode)*

---

# Z98 0.21.0 "Terephthalic Acid" Release Notes

We are proud to announce the release of Z98 version **0.21.0**, codenamed **"Terephthalic Acid"** — the first release after **0.20.0 "Oxalic Acid"** and a release built entirely from the committed seed. It covers **1,864 commits** from the 0.20.0 finalize commit (`ab49e167`) to the release content freeze (`d609186c`), plus the Win9x truth hotfix (`cdec5098`, `1e7b303a`): the seed/self-hosting migration with **zig0 retired**, mutable `for` captures and sema-only `--check`, stricter Zig fidelity, continuation-stack lowering, the full secure-networking standard library, the `z9dbg` debugger, the `std_gfx` GUI layer and `z9edit` editor, and the Win9x conformance work. The release ships **zig1 + seed, no zig0**.

## 🚀 Timeline

- **2026-09-06** — Z98 0.20.0 "Oxalic Acid" released: the first fully self-hosted release. There is **no 0.20.0 tag**; provenance is the finalize commit `ab49e167`.
- **2026-09-06 → 2026-10-29** — 0.21.0 development window: **53 days (~7.6 weeks)**, **1,864 commits** from `ab49e167` to the release content freeze `d609186c`, with no merges; the Win9x truth hotfix rounds (`cdec5098`, `1e7b303a`) and seed v129 rotation (`b5580232`) follow the freeze.
- **2026-10-29** — This release: **Z98 0.21.0 "Terephthalic Acid"**.

## ✨ Headline Capabilities

**Self-hosting and seed**
- Rebuild Z98 from the committed **v129** seed with only `gcc`; fixed point `c1bb4c0e7cbb3d9f4a808491f1a5772d`, two-hop closure `hop1 == hop2`; `lib/` now ships **50** std files (`std.zig` + 49 `std_*.zig`).
- `zig0` is retired from the build path; the seed model (`scripts/seed/build_from_seed.sh`) is authoritative.
- Win9x companion seed zip (`zig1_seed_w9.zip`) with static-CRT/MSVC and OpenWatcom build scripts.

**Language and compiler**
- Mutable `for` captures `|*item|`, `|*item, index|`, `|*_|` bind a pointer into the iterable.
- Sema-only `--check` (rc 0/2, all diagnostics) plus `error[3077]` for semantic-analysis depth and `error[3078]` for unsupported mutable captures.
- Stricter Zig fidelity: string literals typed `*const [N]u8`, implicit enum→int rejected without `@enumToInt`, invalid coercions hard `error[3000]`.
- Continuation-stack lowering removes deep-expression C-stack failures; D11 declarations-before-statements, CRLF Windows files, warning-clean emission, and MinGW fallback build scripts.

**Standard library**
- Full Phase 1 secure-networking stack: `std_net`, `std_tcpip`, `std_crypto`, `std_cipher`, `std_ecc`, `std_asn1`, `std_x509`, `std_tls`, `std_http`, `std_wireguard`.
- Codecs and algorithms: `std_noise`, `std_lz4`, `std_zstd`, `std_num`, `std_pathfind`, `std_physics`, `std_hpa`, `std_fold` (re-exported as `std.fold`), plus `std_async` and `std_stream`.

**Debugger**
- `-d`/`--debug` sidecar map emission (`--output-dir` required) and `z9dbg` with Linux ptrace/DWARF and Win98/Win9x COFF/DWARF-in-PE backends.

**GUI and editor**
- `std_gfx`/`std_gfx_pal` windowed DirectDraw7 cell layer with a 16-color GDI fallback, plus `gfx_demo`.
- `z9edit` single-file editor: gap buffer, syntax/declared-identifier colors, bracket matching, undo, clipboard, themes (white/solarized/dark), `z9edit.ini`/`.cfg` config, and F2 switching.

**Win9x conformance**
- 16-color GDI fallback, visible error dialogs, CRLF batch files, `/Za` `/WX` `/za` `/we` removed from generated scripts, warning-clean emission, MinGW CRT/no-CRT fallback scripts, and the Win9x import gate.
- **Win9x truth hotfix**: source identifiers reserved by MSVC 6 / OpenWatcom (`cdecl`, `near`, `far`, `stdcall`, …) and the emitted `Z98_*`/`zig_*`/`pal_*`/`zT_*`/`zF_*`/`zG_*` namespaces are escaped in the raw-mint path; the emitted `.bat` files are `command.com`-safe, stop on `if errorlevel`, never print `Built:` after a failure, and link gcc via `@z98_link.rsp`.

**Async**
- Multi-module `__Z98Step_<f>` emission, pointer-based `std.async` task handles, and suspending `export fn` synchronous drivers.

**Examples**
- `z9play`, `z9torr`, `z9dbg`, `gfx_demo`, `z9edit`, `wireguard_demo`, and the TLS demo.

## 🛠️ Build Machine & Toolchain

The Linux release artifacts were built and measured on an **AMD Ryzen 7 7700X 8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian GNU/Linux 12 (bookworm)** machine with **gcc 12.2.0**, **i686-w64-mingw32-gcc 12-win32**, **Wine 8.0**, and `gcc -m32` available. No MSVC or OpenWatcom is available locally; the Win9x `zig1_w32.exe` is the operator-built static-CRT binary. Linux artifacts are `gcc -m32` builds; Windows archives are built in the `-osw` target flavour. Linux-facing archives are `.tgz`; win-facing archives are `.zip` so they unpack directly on win9x-era targets.

## 💾 Minimum Requirements

**Running** `zig1` measured **~20 MB** peak RSS at `-s0` on v129: D-safe (`-s0`, default `-fsafe`) is **6.82 s / 20,336 kB** (~19.9 MB), and D-fast (`-s0 -ffast`) is **6.68 s / 19,696 kB** (~19.2 MB). The old **~16 MB** RUN claim no longer holds at v129; use the measured ~20 MB figure. **Building** the compiler from source is dominated by the gcc backend: Row E (`sh build_target.sh linux zig1_next`, gcc `-m32` compile+link of the D-fast output) measured **9.57 s / 180,328 kB** (~176 MB). The Row E binary `6d64c270…` is a build-recipe binary, not the fixed point. Windows runtime memory was not measured; Wine is evidence only.

Measured spill ladder at v129 (`-ffast --markers --track-memory`, RSS median / `pool`):

| Level | Peak RSS (KiB) | Pool (K) |
|---|---:|---:|
| `-s0` | 19,740 | 18,633 |
| `-s1` | 46,368 | 51,414 |
| `-s2` (`-mm128`) | 95,868 | 120,406 |
| `-s3` (`-mm128`) | 95,732 | 120,406 |
| `-s4` (`-mm128`) | 99,420 | 124,502 |
| `-s5` (`-mm128`) | 100,988 | 126,550 |
| `-s6` (`-mm128`) | 103,008 | 130,646 |

Optional deep-input evidence at a 1 MB stack: the 120-term `+` chain ran **0.05 s / 7,040 kB**; the 300-deep block fixture ran **0.00 s / 4,496 kB**. All numbers are medians of 3 at v129; see `measurements.md` for the raw logs.

## ⏱️ PII/PIII Time Estimates

Engineering estimates — **not measurements**. Clock-scaled from the v129 medians via `T_p = T_m × f_m/f_p × k` (`k = 1.0` clock-only lower bound; `f_m` = 4.0 GHz conservative single-core figure for the 7700X; PII 300–450 MHz, PIII 700–1000 MHz). Memory-bound phases scale worse by the stated 1.5–3× upper rationale.

| Row | Median `T_m` (s) | PII 300–450 MHz (s) | PIII 700–1000 MHz (s) |
|---|---:|---:|---:|
| D-safe | 6.82 | 60.6 – 90.9 | 27.3 – 39.0 |
| D-fast | 6.68 | 59.4 – 89.1 | 26.7 – 38.2 |
| E (gcc compile+link) | 9.57 | 85.1 – 127.6 | 38.3 – 54.7 |

Row E is the memory-bound row (~176 MB peak RSS) and carries the 1.5–3× memory-band caveat; D-safe/D-fast peak at only ~20 MB and track the clock ratio more closely. Verify on the operator's real VM.

## 📦 Release Artifacts

The staged 0.21.0 set is **zig1 + seed, no zig0** (git-ignored `release/staging/0.21.0/`):

| File | Size (B) | md5 | Notes |
|---|---:|---|---|
| `zig1_linux32` | 3,560,024 | `c1bb4c0e7cbb3d9f4a808491f1a5772d` | v129 seed binary; ELF 32-bit i386; equals the fixed point |
| `src_c_zig1_linux.tgz` | 2,028,819 | `98e38b070fb7b02f2352a98c9b09beab` | self-emission C89 archive (52 `.c` + 51 `.h` raw; 48 + 49 canonical) |
| `src_c_zig1_w32.zip` | 2,056,674 | `48c229b674343deddf2a7f7dda69bdd9` | `-osw` self-emission; byte-identical members to the linux flavour |
| `zig1_src.tgz` | 1,099,651 | `edeca691a0740ed8e4f32eacf9690e29` | `sf/src` + 50-file `lib/` + `RELEASE_README.txt` |
| `zig1_src.zip` | 1,179,334 | `fa8d63da5759039407248c34a60b5f3c` | identical tree, zip format |
| `zig1-seed.tgz` | 3,681,168 | `af4a480f16e833a26f29210fec9a30b5` | v129 seed archive |
| `zig1_seed_w9.zip` | 2,581,045 | `f6aa60cb05e7533b9f24afa1040ad0d3` | v129 Win9x companion seed (sources + build scripts; no prebuilt exe) |
| `zig1_w32.exe` | PENDING | operator-built static-CRT; hash to be recorded in MANIFEST.txt after the operator build | PE32 i386 Win9x-class compiler; pending operator build |

The shipped `lib/` payload is **50** std files (`std.zig` + 49 `std_*.zig`); `lib/manifest.md5` md5 is `8b78593a7dabb86f9f01cd9e7994ab9f`. `zig1_w32.exe` is the **operator-built static-CRT** compiler (MSVC `/MT` or OpenWatcom static CLIB): it embeds the C runtime, has **no `msvcrt.dll` dependency**, and is verified with the `9x` import gate when it arrives. The MinGW CRT build is a **separate optional artifact** that **does require `msvcrt.dll`**; it is not the Win9x binary and is not shipped as one. A future packaging task will offer OWC/MSVC/MinGW variants for users to choose.

## ⚠️ Known Issues

Open-only entries after Phase 2.5 (no fixed defect is listed):

- **D3** — conditional `@import` still parse-loads a sema-dead arm outside the parse probe; false reject only.
- **D4** — static-analyzer cluster (dead-arm parity, unseeded params/returns, capture aliases, provenance lookup, test drift); false diagnostics possible on complex code.
- **D5** — an `extern fn` with a body is accepted then emitted as a declaration only; non-cdecl callbacks (e.g. Win32 `stdcall`) cannot be defined.
- **D7.3** — a nested write through `arr[i].field[0..]` can target a by-value temporary; the store is silently lost.
- **D8** — stdout is split between C stdio builtins and PAL `std.fmt`; mixed writes can reorder or lose buffered output on abnormal exit.
- **D10** — no first-class calling conventions; Win32 `WNDPROC`/callbacks need a C trampoline.
- **D12** — a module-scope untyped array literal (`pub var arr: [3]u32 = .{...}`) emits an invalid array-to-array C assignment.

## 🔧 Breaking Changes / Upgrade Notes

- **Implicit `enum`→`int`** now requires `@enumToInt`; other previously tolerated invalid coercions are now `error[3000]`.
- **String literals** are typed `*const [N]u8`; code depending on the old bare pointer type may need an annotation or coercion.
- **`-d`/`--debug`** requires `--output-dir`.
- **`zig0` is retired**; the shipped seed archive is the supported rebuild path (there is no zig0 in the release).
- **Generated Windows scripts** no longer pass `/Za`, `/WX`, `/za`, or `/we`.
- **Additional verified strictness**: two-argument `@ptrFromInt` is rejected; assignment used as an expression is rejected; type values in value position, `[_]T` outside inferred-length positions, and `anytype` in signatures are rejected.
- **Tooling note**: depth-limit trips are now `error[3077]` (limit class), not the old `error[3043]` ICE classification.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Zni005 (DeepseekV4+Opencode)*

---

# Z98 0.20.0 "Oxalic Acid" Release Notes

We are proud to announce the release of Z98 version **0.20.0**, codenamed **"Oxalic Acid"** — a **major** release and the first fully self-hosted release of Z98. The self-hosted `zig1` compiler — written in Z98 itself and running from the ANSI C89 it emits — now builds itself, deterministically. The 0.20.0 binaries in this release are produced entirely by the self-hosted chain (Z98 source emitted to C89, compiled with `gcc`); the C++98 bootstrap compiler (`zig0`) is no longer part of building the compiler.

## 🚀 Timeline

- **2025-12-07** — repository created and the bootstrap (`zig0`) era begins (`b1ad10be` "Initial commit").
- **2026-04-27** — bootstrap era ends and zig1 development begins: the `zig1_start` branch is created from `main` (the last `main` commit is the same day), and the first self-hosted commit `cb11d5c6` ("Self hosting initial milestone0 commit") lands.
- **2026-09-06** — today: **1500** commits on `zig1_start` since `main`.

Elapsed: the project overall spans 2025-12-07 → 2026-09-06 (~9 months). The bootstrap era ran ~4.7 months (2025-12-07 → 2026-04-27). The self-hosted / 0.20.0 development window ran ~4.3 months (2026-04-27 → 2026-09-06).

## ✨ Headline Capabilities

- **Deterministic self-hosting**: `zig1` self-compiles to a byte-identical fixed point. The 4-program dump gate (game_of_life, lisp_interpreter_curr, json_parser, mud_server) is byte-stable, the goldens are 9/9 and the target matrix 21/21, and the corpus (428 repros, `-s0`) stands at OK=406 / FAIL=13 / GREEN=9 (EXPECTED_FAIL v70). The emission chain gen-0 → zig1 → self-emission → fixed point (`9c1d956a` → `e791ffd2` → `c0102983` → `10f0ca2b`) is byte-identical at every hop.
- **Language builtins**: `@offsetOf` / `@bitSizeOf` / `@bitOffsetOf`, `@intFromPtr` / `@ptrFromInt` / `@fieldParentPtr`, `@bitCast`; `export fn` / `export var`; cross-module `pub var` stores; `switch` case ranges; clean diagnostics.
- **Target model**: `-osl` (linux) / `-osw` (windows) with the `--target linux|windows` alias select the compile target; `@isWindows()` is target-aware.
- **std_net**: rewritten as target-selected extern `wsock32` (windows) / libc (POSIX) bindings with `WSAStartup` initialisation, `createTcpClient`, and `htonsManual` / `htonlManual`; the 11 `@socket*` builtins were removed from the compiler, so networking programs now use the std library.
- **Upgraded showcase examples**: `lisp_interpreter_upgraded` and `rogue_mud_upgraded` (with committed canonical and demo goldens) plus a net demo client and the `verify_upgraded.sh` closeout harness.

## 🛠️ Build Machine & Toolchain

The 0.20.0 binaries were built on an **AMD Ryzen 7 7700X 8-core/16-thread up to ~5.58 GHz, 32 GB RAM, Debian** box with **gcc/g++ 12.2.0** and **i686-w64-mingw32-gcc 12-win32**. Linux artifacts are `gcc -m32` builds; Windows artifacts are cross-built with `i686-w64-mingw32-gcc` in the `-osw` target flavour. Linux-facing archives are `.tgz`; the win-facing archives are `.zip` so they unpack directly on the win9x-era targets.

## 💾 Minimum Requirements

Running `zig1` fits within ~16 MB at `-s0`: the self-compile pool measures ≈14.5 MB and the measured peak RSS is ~13 MB. Building the compiler from source is dominated by the gcc backend, which needs ~80 MB when compiling and linking the emitted C89 (~85 MB measured peak for the gen-0 hop; the g++ bootstrap step measures ~182 MB). The next-generation (`zig1_5`) hop — gcc over zig1's own self-emitted C89, a ~2.3× larger C set — measures **~166 MB peak at 3.46 s** and is the figure that applies to every self-host next-generation build. A 16 MB machine can run `zig1`, but it cannot build the compiler from source.

Wall-clock and peak RAM were re-measured on the build machine (median of 3 under `/usr/bin/time -v`):

| Build step | Wall (s) | Peak RAM |
|---|---|---|
| g++ → zig0 (bootstrap) | 1.52 | ~182 MB |
| zig0 → emitted C89 | 3.10 | ~46 MB |
| gcc compile+link → zig1 | 1.87 | ~85 MB |
| zig1 `-s0` self-compile | 1.12 | ~13 MB |
| gcc compile+link of zig1's self-emitted C89 → zig1_5 | 3.46 | ~166 MB |

Clock-scaled engineering estimates for period hardware (PII ~300–450 MHz, PIII ~700–1000 MHz; method as in the README) put the whole battery at ~1.1–1.7 min on a PII and ~30–44 s on a PIII at the clock-only lower bound, with the memory-bound phases (gcc, g++) scaling worse (1.5–3×). These are estimates for the operator's real VM, not measurements.

## 📦 Release Artifacts

Eight artifacts plus MANIFEST.txt are staged for this release (git-ignored `release/staging/`):

- `zig0_linux32`, `zig0_w32.exe` — the C++98 bootstrap, retained for the bootstrap-era build path.
- `zig1_linux32` — the self-hosted compiler; its md5 `10f0ca2b…` reproduces the recorded self-compile fixed point byte-for-byte.
- `zig1_w32.exe` — the self-hosted compiler, Windows (`-osw`) flavour.
- `src_c_zig1_linux.tgz`, `src_c_zig1_w32.zip` — the fixed-point self-emission C89 set (83 files; byte-identical across both target flavours).
- `zig1_src.tgz`, `zig1_src.zip` — the Z98 source tree (`sf/src/*.zig` + `sf/src/include/`) plus `RELEASE_README.txt`; both formats carry identical content.

Win-facing artifacts are `.zip` (win9x-unpackable). There is no `zig0` source archive in this release: `zig1_src` is compiled with a `zig0_linux32` / `zig0_w32.exe` bootstrap binary from the same release (exact steps in the archive's `RELEASE_README.txt`), observing the gcc ~80 MB memory caveat above.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Zni005 (DeepseekV4+Opencode)*

---

# Z98 0.13.0 “2-Propanol” Release Notes

We are proud to announce the release of Z98 version **0.13.0**, codenamed **“2-Propanol”**.

Version 0.13.0 represents the most stable and robust version of the Z98 bootstrap compiler to date. This release focuses on "Hardening" the core semantic engine and implementing critical memory optimizations, ensuring stable multi-module compilation for large-scale projects like the stage 1 Zig compiler.

## 🚀 Memory Optimization Excellence

Version 0.13.0 brings several critical memory optimizations that further solidify Z98's ability to run on 16MB-64MB Pentium I/II hardware.
- **Token Arena Reset**: The token arena is now reset immediately after parsing all modules. This frees approximately **1MB** of memory that is no longer needed during semantic analysis.
- **Shared Emitter Buffer**: We've refactored the `C89Emitter` to use a single shared buffer across all generated files. This eliminates the 128KB-per-file static overhead, saving up to **2.8MB** in large projects.
- **AST Block Reuse**: The `ControlFlowLifter` now reuses existing block nodes instead of cloning them during expression-to-statement transformation, reducing peak memory usage by approximately **0.5MB**.
- **Chunk Size Tuning**: The default arena chunk size has been tuned to 256KB to minimize internal fragmentation and improve memory granularity.

## 🛡️ Systemic Symbol Table Hardening

We have resolved a critical class of bugs related to "Symbol Corruption" that occurred during complex cross-module imports.
- **Preserved Type Metadata**: `Scope::insert` is now hardened to preserve existing type metadata. If an incoming symbol lacks type information, the existing resolved type is maintained, ensuring that once a type is resolved, it remains stable.
- **Pre-Insertion Strategy**: Local variables are now inserted into the symbol table *before* their initializers are resolved. This ensures the variable's name is known even if the initializer contains an error, preventing confusing "undeclared identifier" cascades.
- **Forced Resolution Pass**: At the end of every block, the compiler performs a second pass on any variables that still have an undefined type, ensuring every local variable has a concrete type before static analysis.

## 🏗️ Production-Grade Module Identity

We have overhauled how the compiler tracks and identifies modules to ensure 100% reliable type deduplication across complex import graphs.
- **Canonical Module Identity**: The `TypeRegistry` now uses **Canonical Module Paths** (absolute, normalized, and case-insensitive) as unique keys for type lookups, ensuring that `std.zig` is always `std.zig`, regardless of how it was imported.

## 🛠️ Robust Alias & Placeholder Resolution

The resolution of transitive type aliases and mutually recursive structures has been significantly strengthened.
- **Fixed-Point Placeholder Resolution**: Phase 0.5 now utilizes a **Fixed-Point Iteration** strategy, iterating until convergence to handle even the deepest chains of cross-module type aliases.
- **Deep Alias Unwrapping**: The compiler now deeply unwraps `TYPE_TYPE` chains during type constant resolution, allowing the `TypeChecker` to see through alias layers immediately.

## 📦 Hardening C89 Compatibility

### 📦 Aggregate Initializer Lifting
The `ControlFlowLifter` now automatically identifies aggregate literals (structs, unions, tuples) in non-constant expression contexts and "lifts" them into uniquely named temporary variables. These are then decomposed into field-by-field assignments, ensuring 100% ANSI C89 compliance.

### 🏷️ Enhanced Tagged Union Coercion
Z98 now supports distributed coercion for tagged unions within control-flow expressions. You can return "naked" tag literals (e.g., `.Alive`) from branches of an `if` or `switch`, provided the expected result type is a tagged union.

## 🔍 Static Analyzer Decoupling

The `LifetimeAnalyzer` and `NullPointerAnalyzer` have been decoupled from the lexical scoping system to improve reliability.
- **Post-Check Safety**: Analyzers now rely on the `getRootSymbol` utility, which extracts variable identity directly from AST metadata, ensuring stability even after lexical scopes are discarded.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---

# Z98 0.12.0 “Isophthalic acid” Release Notes

We are proud to announce the release of Z98 version **0.12.0**, codenamed **“Isophthalic acid”**.

**Isophthalic acid** marks a monumental milestone in the Z98 project. This release represents the final feature-set for our C++ bootstrap compiler (`zig0`) and the official commencement of our journey toward a self-hosted Zig compiler. This release introduces fundamental language features like Tuples, a robust Networking PAL, and a significant evolution in our static analysis capabilities.

## 🛡️ Double-Free Analyzer 2.0

Stability and memory safety are paramount when targeting resource-constrained legacy systems. In this release, the `DoubleFreeAnalyzer` has undergone a major upgrade (Phases 5-8), transforming it from a basic check into a sophisticated static analysis tool:

- **Composite Tracking**: The analyzer now tracks lifetimes across complex aggregate members (e.g., `s.ptr`) and nested structures (arrays, tuples).
- **Transfer History Diagnostics**: Error messages now include a complete transfer history, showing exactly where ownership was originally established and through which assignments it was transferred before a violation occurred.
- **Path-Aware `errdefer`**: The analyzer now correctly understands that `errdefer` blocks only execute on error paths, eliminating false positives in complex cleanup logic.
- **Arena Leak Detection**: Introducing the `-Warena-leak` flag, which helps developers identify memory that was allocated in an arena but never properly managed, ensuring peak efficiency.

## 🏗️ Expanding the Language: Tuples & Networking

### 🧊 Full Tuple Support
Z98 now supports **Tuples**. This includes tuple types (`struct { i32, f32 }`), literals (`.{ 42, 3.14 }`), and zero-indexed member access (`t.0`). In the C89 backend, tuples are lowered into specialized structs with indexed fields, providing a seamless and efficient mapping to the target hardware.

### 🌐 Networking PAL & Socket API
To support the next generation of Z98 applications, we have introduced a minimal **Socket API** to our Platform Abstraction Layer (PAL). This API provides a cross-platform interface for TCP server creation, non-blocking I/O via `select()`, and standard `send`/`recv` operations. It is fully compatible with both Winsock 1.1 on Windows 95/98 and standard POSIX sockets.

## 🔌 Compatibility & Tooling

### 🛠️ OpenWatcom 1.9 Support
Continuing our commitment to legacy toolchains, the bootstrap compiler and its generated code are now fully compatible with the **OpenWatcom 1.9** compiler suite. We have included optimized build scripts (`build_openw.bat`) and standardized PAL headers to ensure a smooth development experience on native 90s hardware.

### 📜 100% Test Stability
The Z98 test suite now comprises **82 batches** of tests, all of which are passing with 100% stability. This includes rigorous verification of the new Tuple support, Networking PAL, and advanced static analysis rules.

## 🚀 The Road to Self-Hosting
With the completion of Milestone 11, we are freezing the feature set of the bootstrap compiler. Our focus now shifts to the **Self-Hosting Phase**. We have already drafted comprehensive design documents for the self-hosted compiler, covering the new LIR-based architecture, advanced type system, and modular design. These documents can be found in `docs/sf/`.

## 📂 New & Updated Examples
- **[MUD Server](examples/mud_server/)**: A minimal telnet Multi-User Dungeon server demonstrating the new Networking PAL and Tuple support.
- **[Game of Life](examples/game_of_life/)**: Enhanced with patterns and optimized C89 lowering.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---

# Z98 0.11.0 “para-Cresol” Release Notes

We are proud to announce the release of Z98 version **0.11.0**, codenamed **“para-Cresol”**.

Following the foundational work of "Xylene", **para-Cresol** represents a phase of refinement and aromatic enhancement. Just as para-cresol is an essential precursor in the creation of fine fragrances and antioxidants, this release focuses on smoothing out the remaining rough edges of the bootstrap compiler and introducing the final set of language features required for the next stage of our journey: the self-hosted Zig compiler.

This release completes Milestone 11, bringing a suite of quality-of-life improvements and robustness fixes that make the Z98 subset feel more expressive and reliable.

## ✨ Milestone 11: The Refinement Phase

### 🎨 Expressive Control Flow
Z98 now supports **Braceless Control Flow**. For simple `if`, `while`, `for`, and `defer` statements, braces are now optional, allowing for more concise and idiomatic Zig code. The compiler's lifting pass has been updated to handle these cases seamlessly, ensuring they are correctly transformed into safe C89 blocks.

### 🔢 Switch Enhancements
We have introduced support for **Switch Ranges**. You can now use inclusive (`...`) and exclusive (`..`) ranges within switch prongs, significantly simplifying logic for character classes and numeric intervals.

### 🎣 Robust Payload Captures
Payload captures are now fully supported in both `while` loops and `switch` expressions. This allows for safe and elegant unwrapping of Optional types and Tagged Unions, with the compiler ensuring that captures are correctly scoped and initialized even in complex nested loops.

### 🖨️ Print Lowering
A major architectural addition in this release is **Print Lowering**. Calls to `std.debug.print` are now automatically decomposed by the compiler into a series of efficient, direct runtime calls (`__bootstrap_print`, `__bootstrap_print_int`). This eliminates the need for a complex `printf` implementation in the bootstrap runtime and improves reliability on legacy systems.

## 🛠️ Stabilization & Compatibility

### 🏗️ C89 Compliance: Block-Top Declarations
To adhere to the strictest C89 standards (and ensure compatibility with MSVC 6.0), the `C89Emitter` now guarantees that all compiler-generated temporary variables—such as those used for loop indices or expression lifting—are declared at the absolute top of their respective C blocks.

### 🔄 Recursion & Type Resolution
This release fully resolves several deep-seated issues related to recursion. The Lisp interpreter example now runs flawlessly thanks to a "mutable slot" strategy for recursive definitions and a more robust `TYPE_ANONYMOUS_INIT` resolution system for nested aggregate initializers.

### 🔌 Standardized Runtime API
We have standardized the signatures of our core runtime IO functions. `__bootstrap_print`, `__bootstrap_write`, and `__bootstrap_panic` now consistently use `const char*` signatures, resolving signedness warnings and improving interop with standard C libraries.

## 📂 New & Updated Examples
- **[Mandelbrot](examples/mandelbrot/)**: A new example demonstrating floating-point performance and the new braceless syntax.
- **[Lisp Interpreter](examples/lisp_interpreter_curr/)**: Now fully functional with recursive `define` and improved 32-bit alignment.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent)*

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project. It continues to serve as a bridge between the modern world of Zig and the classic hardware of the late 90s.

***

# Z98 0.10.0 “Xylene” Release Notes

We are pleased to announce the first official release of the Z98 compiler, version **0.10.0**, codenamed **“Xylene”**.

Z98 is an independent, self‑hosting subset of the Zig language, designed to target 1998‑era hardware and software (Windows 95/98/ME). By generating clean, portable ANSI C89 code, Z98 brings a selection of modern language features—error unions, `defer`, slices—to legacy systems with extreme resource constraints.

The name **Xylene** (pronounced *ZY-leen*) was chosen because, like the chemical compound, this release serves as a fundamental building block for the Z98 ecosystem—a stable, essential foundation upon which future stages will be built. Xylene is also a solvent used to dissolve complex substances; similarly, this release aims to dissolve the complexity of bringing modern language concepts to older platforms.

## 🚀 Hero Milestone: Cross‑Compiler Stability
The primary goal of this release is to establish a rock‑solid bootstrap compiler. We have focused on making `zig0` itself compile and run reliably across a variety of environments, verifying that:

- It builds with **G++**, **Clang++**, and **MinGW‑w64** (with minor identifier adjustments to avoid collisions with Windows headers).
- The generated C89 code compiles cleanly with **`gcc -m32`**, **`musl‑gcc`**, and is designed to be compatible with **MSVC 6.0**.
- Peak memory usage stays well below **16 MB**, making it viable for actual Pentium‑class hardware with limited RAM.

We consider this the most important achievement of the release: a compiler that can be built and run on the systems it targets, and whose output is portable C89.

For detailed test results, see [Cross-Compatibility Tests](docs/reference/cross_compatibility_tests.md).

## ✨ Key Features

### 📦 Separate Compilation & Multi‑Module Support
The compiler now fully supports multiple modules. It resolves `@import` dependencies, emits each module as its own `.c` and `.h` file, and automatically generates `build_target.sh` / `build_target.bat` scripts to build the final executable. This reflects the way real‑world C projects are structured and paves the way for larger applications.

### 🛠️ AST Lifting (Expression‑to‑Statement Transformation)
Zig’s expression‑oriented syntax doesn’t always map directly to C89’s statement‑based nature. We implemented an **AST Lifting** pass that transforms expression‑form `if`, `switch`, `try`, `catch`, and `orelse` into safe, statement‑based blocks with temporary variables. This allows these constructs to be used in complex contexts while keeping the generated C code simple and C89‑compliant.

### ⚠️ Advanced Error Handling
The compiler now supports error unions (`!T`), `try`, `catch`, and full `defer` / `errdefer` semantics. These features are not just parsed; they are correctly lowered to C89 code that runs on the target platforms. `errdefer` execution is conditional on error returns, which is handled by a per‑function error flag.

### 🧬 Rich Type System
- **Slices (`[]T`)**: First‑class support for pointer+length pairs, with slicing syntax `arr[start..end]` and automatic array‑to‑slice coercion.
- **Tagged Unions (`union(enum)`)**: Safe unions with payload captures in `switch` statements.
- **Optional Types (`?T`)**: Type‑safe nullability with the `orelse` operator.
- **Recursive Types**: Complex, mutually recursive structures are handled via a two‑phase placeholder resolution system.

## 📚 Documentation
- [Z98 Language Specification](docs/reference/Language_Spec_Z98.md)
- [C89 Emission Reference](docs/reference/c89_emission.md)
- [Building Z98](docs/Building.md)
- [Z98 Design Philosophy](docs/design/DESIGN.md)

## 📂 Featured Examples
- **[Hello World](examples/hello/)**: The classic starting point.
- **[Prime Sieve](examples/prime/)**: Basic arithmetic and loops.
- **[Heapsort](examples/heapsort/)**: In‑place sorting with arrays.
- **[Quicksort](examples/quicksort/)**: Function pointers and recursion.
- **[Lisp Interpreter](examples/lisp_interpreter_curr/)**: A non‑trivial application that exercises the type system, error handling, and memory management.

## 👥 Contributors
Z98 is made possible by the dedicated work of its contributors.

*@melkyr-Andres Hernandez*
*Jules (AI-Agent used to help out)*

---
**Note:** Z98 is an independent project and is not affiliated with the official Zig project. It does not aim to replace Zig or C89, but rather to offer a compatible subset that can run on extremely limited hardware. This release is the first step in that journey; we expect it to have limitations and welcome feedback.
