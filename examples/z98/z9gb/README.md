# z9gb

A DMG (original Game Boy) and CGB (Game Boy Color) emulator shell for Z98.
This example is at **P5: SM83 dynarec**. It runs a DMG/CGB CPU, MMU/timer/serial,
a scanline PPU (BG, window, sprites, DMG palettes, CGB color palettes/attributes,
STAT/LYC and mode-access timing), a 4-channel APU with CGB sound semantics,
CGB double-speed and HDMA, MBC1, MBC3 (+RTC), and MBC5 cartridges, battery
saves, and two backends: a pure-Z98 deterministic headless backend and a Win32
DirectDraw/DirectInput/DirectSound windowed backend with QPC frame pacing.

The **Win32/x86 dynarec** (`--dynarec`) translates SM83 basic blocks and executes
them from a separate 1 MiB `VirtualAlloc` `PAGE_EXECUTE_READWRITE` mapping; the
interpreter remains the correctness oracle and the fallback for non-ROM PCs,
interrupts/DMA, failed cache allocation, and *nix hosts. There is no heap
allocation; the single emulator, framebuffer, audio ring, and platform state are
module-scope statics. `--windowed` requires the Win32 target; the Linux host has
only the headless backend, so `--dynarec` there prints
`dynarec=disabled reason=unsupported-host` and runs the interpreter.


CGB hardware is opt-in: pass `--cgb`. A CGB-only cartridge (header byte
`0x0143` bit 7 set and bit 6 set) refuses to load without `--cgb` and exits 2
with `z9gb: CgbRequired`; a CGB-compatible cartridge loads under either mode
(DMG compat without `--cgb`, color with it).

## P3 playable backend

- **Display:** `IDirectDraw7`/`IDirectDrawSurface7` with integer `--scale 1..4`
  (160x144 source; 320x288, 480x432, or 640x576 output). This needs the
  **DirectX 6+ runtime**; stock Win98 ships DX5 and has no `IDirectDraw7`, so
  `--windowed` fails closed there. Install a DX6+ (practically DX7/8) runtime.
- **Input:** DirectInput8 keyboard plus gamepad, with a `GetAsyncKeyState`
  keyboard fallback when `dinput8.dll`/DInput8 is unavailable. The gamepad path
  needs the **DirectX 8 runtime** (`dinput8.dll`); the keyboard fallback works
  without it.
- **Audio:** DirectSound (DS v1 `DirectSoundCreate`, 44.1 kHz stereo) with a
  WinMM `waveOut` fallback when DirectSound cannot open. Audio can be disabled
  with `--no-audio`; a missing host audio device falls back rather than blocks
  emulation.
- **Pacing:** QPC deadlines at the GB frame clock (59.7275 Hz), `Sleep` while
  ahead and a bounded final spin, with `timeBeginPeriod(1)`. `--turbo` skips
  pacing for throughput runs.
- **Real-hardware caveat:** Wine/cross-build is functional evidence, not Win98
  hardware. Wine numbers are reported as Wine only. Real Win98/Pentium II
  sign-off remains the operator's, and a DX6+ runtime is mandatory for
  `--windowed`.

## P4 CGB support

- **CGB mode:** `--cgb` selects CGB hardware. The cartridge header still chooses
  color (`0x80` set, `0xC0` clear) or DMG compatibility (`0xC0` set). A CGB-only
  cartridge is a hard requirement: without `--cgb` the CLI prints
  `z9gb: CgbRequired` on stdout and exits 2.
- **Color:** CGB background/window tile attributes (palette, VRAM bank, flips,
  priority) and CGB 15-bit BG/OBJ palettes via `BCPS/BCPD` (`0xFF68/0xFF69`)
  and `OCPS/OCPD` (`0xFF6A/0xFF6B`), including auto-increment and the
  mode-3 palette-access block. VRAM is two 8 KiB banks (`VBK`, `0xFF4F`); WRAM
  is eight 4 KiB banks (`SVBK`, `0xFF70`).
- **Double-speed:** `KEY1` (`0xFF4D`) arms a speed switch and reports the
  current speed; the CGB CPU/PPU cycle split halves PPU dots while the CPU runs
  at double speed.
- **HDMA:** general-purpose and HBlank DMA (`HDMA1..HDMA5`, `0xFF51..0xFF55`),
  with block progress/termination reporting and double-speed timing.
- **CGB APU semantics:** CGB wave-RAM access and length-register behavior.

CGB hard gates (all three must be present and passing at P4 closeout):

```sh
ZIG=/path/to/zig1_5_clean
bash examples/z98/z9gb/tests/tier_cgb.sh "$ZIG"          # unit/CLI + hard gates
bash examples/z98/z9gb/tests/run_cgb_acid2.sh "$ZIG"     # cgb-acid2 framebuffer
bash examples/z98/z9gb/tests/run_cgb_sound.sh "$ZIG"     # Blargg cgb_sound
bash examples/z98/z9gb/tests/run_cgb_interrupt_time.sh "$ZIG"
```

`tier_cgb.sh` builds the CGB unit test in fast and safe modes and checks the
`--cgb`/`CgbRequired` CLI contract, then runs `cgb-acid2`, `cgb_sound`, and
`interrupt_time`. A missing external ROM, reference PNG, or golden is a truthful
`SKIP` (exit 77), never a PASS; a skipped CGB hard gate blocks closeout.

The committed `cgb-acid2` golden `testdata/golden/cgb-acid2.fb` is derived from
the official `mattcurrie/cgb-acid2` v1.1 `img/reference.png` (SHA-256
`9ea9c262c5383353e77d715d021a0f7c5ccbe438f88082cb225756e50c4fdf01`) using the
CGB 5-bit expansion `(c << 3) | (c >> 2)` per channel; it is pinned at SHA-256
`0fba336ce7d7cb4ef76049a4548ff0e7a5147be79fb34bfd266ce7bb71fcf9fd`. It is not
generated from this emulator.

**Real-hardware caveat:** P4 evidence is host headless plus Wine cross-build
testing. Wine is functional evidence only, never Win98 hardware. No Win98
real-hardware CGB run was performed; real-hardware sign-off remains the
operator's.

## P5 SM83 dynarec

- **Status:** complete. `--dynarec` is Win32/x86 only; the interpreter remains
  the correctness oracle and the fallback. On *nix the flag is truthfully
  disabled (`dynarec=disabled reason=unsupported-host`) because only Windows
  provides the required `VirtualAlloc` executable mapping.
- **Code cache:** one fixed **1 MiB** mapping from
  `VirtualAlloc(NULL, 1 MiB, MEM_COMMIT | MEM_RESERVE,
  PAGE_EXECUTE_READWRITE)` on Win32 (`mmap` in the native test harness). It is
  **separate from the 1 MiB stack and from static/BSS state**.
- **Fallback:** non-ROM PCs (WRAM/HRAM), interrupts, DMA/HDMA, an allocation
  failure, or a full/invalidated cache run on the interpreter. `--dynarec`
  prints `dynarec=on blocks=N executed=N fallback=N`; `--dynarec-stats` prints
  the same without enabling translation. A failed allocation prints
  `dynarec=disabled reason=cache-alloc-failed` and the interpreter continues.
- **Cache-hit ratio:** not instrumented; the counters above are block
  translations, block executions, and interpreter fallback steps.
- **Real-hardware caveat:** executable `PAGE_EXECUTE_READWRITE` memory is
  unproven on real Win9x. If `VirtualAlloc` fails, dynarec disables itself and
  the interpreter runs; that is not a dynarec PASS claim. Wine numbers are Wine
  evidence only, never Win98 hardware evidence.

Measured accounting and the workload matrix from the 2026-11-12 compat
re-measurement (host load varies). `code_cache_bytes=1048576`,
`stack_limit=1048576`, `static_bytes=9801160`, `dynarec_state_bytes=262196`;
the Dynarec state is a pointer plus entries, so the 1 MiB code cache is not in
BSS and is not a stack allocation.

**Primary dynarec throughput metric:** Wine headless turbo (no display/pacing
throttle), reported as emulated T-cycles/sec = 42,134,400 / wall (600 frames ×
70,224 T-cycles). Each row is the median of three alternating
interpreter/`--dynarec` runs after an unmeasured warmup. The `coverage` column is
the `coverage` permille printed by `--dynarec-stats` (percent in parentheses).

| ROM | Flags | Mode | T-cycles/sec | fps | wall | CPU user/sys | RSS | coverage |
|---|---|---|---:|---:|---:|---:|---:|---:|
| `2048.gb` | — | `--no-dynarec` | 8,181,437 | 116.505 | 5.15 s | 5.11 / 0.01 s | 15,352 KiB | — |
| `2048.gb` | — | `--dynarec` | 8,056,291 | 114.723 | 5.23 s | 5.09 / 0.01 s | 15,508 KiB | 12‰ (1.2%) |
| `p_cry.gbc` (Pokemon Crystal) | `--cgb` | `--no-dynarec` | 9,363,200 | 133.333 | 4.50 s | 4.42 / 0.01 s | 17,268 KiB | — |
| `p_cry.gbc` | `--cgb` | `--dynarec` | 7,646,897 | 108.893 | 5.51 s | 5.36 / 0.01 s | 18,556 KiB | 317‰ (31.7%) |
| `p_pin.gbc` (Pokemon Pinball) | `--cgb` | `--no-dynarec` | 10,666,937 | 151.899 | 3.95 s | 3.92 / 0.01 s | 16,384 KiB | — |
| `p_pin.gbc` | `--cgb` | `--dynarec` | 12,768,000 | 181.818 | 3.30 s | 3.15 / 0.01 s | 17,280 KiB | 973‰ (97.3%) |

The earlier P5 verdict was drawn from `2048.gb` alone, a HALT-heavy workload
that measured at most 6% dynarec coverage (1.2% here), and concluded "no
measurable gain". That conclusion is workload-qualified, not universal:

- `2048.gb` at 1.2% coverage: dynarec is 1.5% slower (8,056,291 versus
  8,181,437 T-cycles/sec); nearly every step falls back to the interpreter.
- Pokemon Crystal at 31.7% coverage: dynarec is 18.3% slower (7,646,897 versus
  9,363,200); translation and dispatch overhead still outweigh translated
  execution.
- Pokemon Pinball at 97.3% coverage: dynarec is 19.7% faster (12,768,000 versus
  10,666,937); with almost all instructions translated, the dynarec is a real
  throughput win.

The corrected conclusion is **workload-dependent**: the dynarec is a gain on
high-coverage ROMs, roughly neutral-to-negative at low coverage, and no fixed
speedup threshold applies. These are Wine numbers and Wine evidence only; no
Win98 hardware claim is made. The corresponding `--dynarec` counters for the
600-frame runs were: `2048` `blocks=192 executed=45382 fallback=10187028
tinstr=129109 minstr=10187028 rejected=11322 coverage=12‰`; Crystal
`blocks=41379 executed=761742 fallback=4681142 tinstr=2174380 minstr=4681142
rejected=73375 coverage=317‰`; Pinball `blocks=40149 executed=1687938
fallback=135400 tinstr=4986874 minstr=135400 rejected=85087 coverage=973‰`.

The following context rows are **not** dynarec throughput judgments: host
headless is unpaced interpreter throughput, and dynarec is unavailable on *nix;
Wine windowed is display-bound evidence only. These are single runs from the
same re-measurement.

| Path | Variant | fps | wall | CPU user/sys | RSS |
|---|---|---:|---:|---:|---:|
| host headless (-O2, unpaced interpreter) | `--no-dynarec` | 833.333 | 0.72 s | 0.70 / 0.00 s | 3,088 KiB |
| host headless (-O2, unpaced interpreter) | `--dynarec` | 857.143 | 0.70 s | 0.70 / 0.00 s | 3,216 KiB |
| Wine windowed (display-bound) | `--no-dynarec` | 47.168 | 12.85 s | 6.75 / 0.05 s | 41,788 KiB |
| Wine windowed (display-bound) | `--dynarec` | 47.622 | 12.74 s | 6.70 / 0.06 s | 41,552 KiB |

The host `--dynarec` row is the interpreter with dynarec disabled
(`reason=unsupported-host`), not translated execution; host dynarec cannot be
judged on *nix. The windowed Wine rows include display overhead, so their
near-identical fps is not a dynarec throughput result. All Wine numbers are Wine
evidence only, never Win98.

## Building with zig1

The compiler is self-hosted. A seed build
(`scripts/seed/build_from_seed.sh`) puts `lib/` next to the `zig1` binary, and
the compiler searches `<exe-dir>/lib` automatically. `-o <dir>` selects the
output directory (create it first) and emits a complete self-contained C89 tree
with a companion `build_target.sh`.

### Prerequisites

**Common**
- A seed-built `zig1_5_clean` with its sibling `lib/` directory (current seed
  is v149, lib 65).
- `bash`, `timeout`, `sha256sum`, `cmp`, and `/usr/bin/time` for the test tiers.
- Optional external ROM tree via `Z9GB_ROM_DIR`; omit it and gate runs report
  truthful `SKIP`, never PASS.

**Linux / *nix host**
- 32-bit C toolchain: `gcc -m32` plus 32-bit libc/multilib
  (`gcc-multilib` or the distro equivalent).
- The Linux build is **headless only**; there is no X11/Wayland windowed
  backend.
- The dynarec is **Win32/x86 only** and is unavailable on *nix; use the
  interpreter.
- For the Win32 cross-build checks: `i686-w64-mingw32-gcc`,
  `i686-w64-mingw32-objdump`, MinGW headers (`ddraw.h`, `dsound.h`,
  `dinput.h`), `wine`, and `xvfb-run` for windowed smoke/perf runs.

**Win9x build and link**
- A seed-built Z98 compiler, or the emitted `build_target.bat` with
  MinGW/OpenWatcom/MSVC as appropriate.
- The emitted Win32 executable is no-CRT: core imports stay
  KERNEL32/WINMM/USER32/GDI32. DDRAW/DINPUT8/DSOUND are loaded dynamically.
- `--windowed` needs a **DirectX 6+ runtime** (`IDirectDraw7`); stock Win98
  ships DX5. The gamepad path needs **DirectX 8** (`dinput8.dll`); the keyboard
  fallback works without it.
- The dynarec requires Win32/x86 `VirtualAlloc` memory with
  `PAGE_EXECUTE_READWRITE`; if allocation fails, `--dynarec` reports
  `dynarec=disabled reason=...` and the interpreter runs.
- Wine/cross-build is functional evidence only, never Win98 hardware sign-off.

### Linux

```sh
mkdir -p /tmp/z9gb_p3
/path/to/zig1_5_clean -ffast -I "$PWD/sf/src" \
    -o /tmp/z9gb_p3 examples/z98/z9gb/main.zig
sh /tmp/z9gb_p3/build_target.sh linux /tmp/z9gb_p3/z9gb
/tmp/z9gb_p3/z9gb --headless --frames 1 --fb-out /tmp/z9gb_p3.fb
```

That is a bounded single-frame run. Omit `--frames` to run until the process
is terminated; `--fb-out` is only written by a finite run.

### Win32 (no-CRT, Win95/98 target)

```sh
EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
DUMP_TARGET="-osw -I $PWD/sf/src" \
bash scripts/win32_cross/cross_nocrt.sh /path/to/zig1_5_clean \
    examples/z98/z9gb/main.zig /tmp/z9gb_p3w /tmp/z9gb_p3w/z9gb.exe
```

The emitted framebuffer file is 92,160 bytes: 160×144 little-endian RGB32
pixels, written identically on every run.

## Usage

```sh
z9gb [--headless | --windowed] [--cgb] [--scale <1..4>] [--frames <n>]
     [--fb-out <path>] [--rom <path>] [--audio | --no-audio]
     [--serial] [--turbo] [--mooneye] [--save] [--rtc-fixed <unix>]
```

- `--headless` selects the headless platform. It never opens a window and
  imports no Win32 or DirectX header.
- `--cgb` runs on CGB hardware; without it a CGB-only cartridge exits 2 with
  `z9gb: CgbRequired`. A CGB-compatible cartridge still boots in DMG mode
  without the flag.
- `--windowed` selects the Win32 DirectDraw/DirectInput/DirectSound backend.
  It only exists on the Win32 target and needs the DX6+ runtime for
  `IDirectDraw7`; the gamepad additionally needs DX8 `dinput8.dll`.
- `--scale <1..4>` sets the windowed integer scale (default `1`).
- `--audio` / `--no-audio` enables or disables APU output (default on).
- `--frames <n>` runs exactly `n` frames, then exits (writing `--fb-out` when
  given). The default is `0`, which means run until the process is terminated;
  `--frames 0` is explicitly unlimited. Windowed runs also stop on quit/`Esc`.
- `--fb-out <path>` writes the final framebuffer as 160×144 little-endian
  `u32` RGB32 pixels (92,160 bytes). It is written only when a finite
  `--frames` run completes; an unlimited run never writes it.
- `--rom <path>` size-checks (32 KiB to 8 MiB), copies the ROM into the fixed
  **8 MiB** buffer, validates the header/cartridge type, and installs the
  post-boot CPU/PPU state. Files larger than 8 MiB are rejected with
  `ROM too large` and exit code 2. The full 64-bit file size is checked before
  narrowing, so a file at or above 4 GiB cannot truncate into the cap.
- `--serial` mirrors emulated serial bytes to stdout and exits early on a
  terminal `Passed`/`Failed` line.
- `--turbo` skips frame pacing (windowed and headless) for throughput runs.
- `--mooneye` stops before the `LD B,B` breakpoint and prints the full
  B/C/D/E/H/L register signature.
- `--save` writes battery RAM (and the `.rtc` file when the cartridge has one)
  at normal exit.
- `--rtc-fixed <unix>` freezes the MBC3 RTC clock to a Unix epoch for
  deterministic runs; without it the RTC uses the host wall clock.

## Running Game Boy Color ROMs

Use `--cgb` for Game Boy Color software. The `.gbc` extension is not required;
the cartridge header byte `0x0143` decides. A CGB-only cartridge exits 2 with
`z9gb: CgbRequired` if `--cgb` is omitted.

Windows example (run from the directory containing `z9gb.exe`):

```bat
z9gb.exe --windowed --cgb --scale 2 --rom "C:\Games\Pokemon Crystal.gbc" --save
```

- `--windowed` opens the DirectDraw/DirectInput/DirectSound backend; use
  `--headless` for no window.
- `--scale 2` selects integer scaling (1-4).
- `--rom <path>` loads the ROM (32 KiB-8 MiB); `--save` writes battery RAM
  next to the ROM as `.sav` and, for MBC3+RTC cartridges, `.rtc`.
- `--cgb` is required for CGB-only ROMs and selects color mode for
  CGB-compatible ROMs; without it a CGB-compatible ROM runs in DMG mode.
- Cartridge rumble motors are not emulated. Standard CGB video, sound,
  banking, double-speed, HDMA, and MBC3 RTC are supported.

Windowed runs continue until quit (`Esc`); `--frames` is optional there.
Headless runs need an explicit finite `--frames` to exit on their own:

```bat
z9gb.exe --headless --cgb --frames 600 --rom "C:\Games\Pokemon Crystal.gbc"
z9gb.exe --headless --cgb --frames 600 --rom "C:\Games\Pokemon Pinball.gbc"
z9gb.exe --headless --frames 600 --rom "C:\Games\k_dl.gb"
```

### Controls (windowed)

| Key | Game Boy |
|---|---|
| Arrow keys | D-pad |
| `Z` | A |
| `X` | B |
| `Enter` | Start |
| `Backspace` | Select |
| `Esc` | Quit |

On a successful windowed open, z9gb prints one startup line reporting the
selected backends, for example `z9gb: input=dinput8 audio=dsound`. A DInput
keyboard fallback prints `input=fallback`, WinMM audio prints `audio=waveout`,
and `--no-audio` prints `audio=off`.

Unknown flags and missing operands exit with code 1; a bad ROM, an unopenable
headless platform, or a failed save exits with code 2.

## Supported cartridges

Header type byte `0x0147` selects the controller:

| Type bytes | Controller | Notes |
|---|---|---|
| `0x00` | no MBC | 32 KiB direct ROM |
| `0x01`–`0x03` | MBC1 | RAM enable, 5-bit bank, secondary bank/mode, RAM banking |
| `0x0F`–`0x13` | MBC3 | RAM/RTC enable, 7-bit bank, 4-bit RAM bank; `0x0F`/`0x10` carry an RTC |
| `0x19`–`0x1E` | MBC5 | 9-bit ROM bank (bit 8 at `0x3000`), 4-bit RAM bank, bank 0 valid |

Unknown types are rejected with `UnsupportedMbc`. ROM size is decoded from
`0x0148` and RAM size from `0x0149`; the ROM must be at least the declared size.
The cartridge RAM backing store is a fixed 128 KiB (MBC5 maximum) and `ram_size`
selects the active prefix.

The MBC3 RTC is a 9-bit day counter with halt and day-carry flags. Writes target
live counters; reads return latched copies. The day counter wraps `511 → 0`,
and the halt bit freezes accumulation.

## Saves

A loaded ROM `path.gb` derives `path.sav`; an MBC3+RTC cartridge also derives
`path.rtc`. `.sav` is the raw active cart-RAM prefix (`ram_size` bytes). `.rtc`
is the 32-byte `Z98RTC1` version-1 header:

| Offset | Contents |
|---|---|
| `0..7` | `"Z98RTC1\0"` |
| `8` | version `1` |
| `9..11` | seconds, minutes, hours |
| `12..13` | days low, days high (bit 0) |
| `14` | flags: bit 0 halt, bit 1 day carry |
| `15` | reserved zero |
| `16..23` | host timestamp anchor (u64 little-endian Unix seconds) |
| `24..31` | reserved zero (no CRC in v1) |

Writes use a Win9x-safe backup dance through `std_file`'s whitelisted
`DeleteFileA`/`MoveFileA` bindings (no `CopyFileA`/`MoveFileExA`): write
`PATH.tmp`, delete `PATH.bak`, rename `PATH → PATH.bak`, rename
`PATH.tmp → PATH`, delete `PATH.bak`. On failure the previous file is restored;
a failed write does not truncate the existing file.

There is a small **rename window**: between the `PATH → PATH.bak` and
`PATH.tmp → PATH` moves the canonical name is temporarily absent (the old file
lives at `PATH.bak`). A crash or power loss in that window can leave only
`.bak`/`.tmp` files. Load-side validation is the real corruption defense: the
`.rtc` magic, version, ranges, flags, reserved bytes, and anchor are checked
before anything is applied, and the `.rtc` is parsed before `.sav`, so a corrupt
`.rtc` never mutates cart RAM. Short or foreign files return `SaveCorrupt`.

## RAM model

- The **1 MiB stack** is a hard limit and is separate from the **1 MiB code
  cache**; the dynarec cache is a fixed `VirtualAlloc`/`mmap` mapping, not BSS
  or stack state.
- The **8 MiB ROM buffer** is a static module-scope buffer inside the single
  `Emu` instance; it is never a stack local and never copied by value.
- The 92,160-byte framebuffer and the platform snapshots are static too.
- No emulator path performs heap allocation; the code cache is the one dynamic
  executable mapping.

## P2 gates

Run from the repository root with a seed-built compiler:

```sh
ZIG=/path/to/zig1_5_clean

# Inline cartridge/CPU/timer/PPU/save tiers, fast + safe:
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all

# External ROM hard gates (Blargg, Mooneye, dmg-acid2):
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates

# Individual gates:
bash examples/z98/z9gb/tests/run_blargg.sh "$ZIG"
bash examples/z98/z9gb/tests/run_mooneye.sh "$ZIG"
bash examples/z98/z9gb/tests/run_acid2.sh "$ZIG"

# Memory + three-run framebuffer determinism:
bash examples/z98/z9gb/tests/measure_rss.sh "$ZIG" /tmp/z9gb_p2_rss
```

`--all` and `--gates` must both print `TIER_DMG PASS`; a skipped hard gate
blocks closeout. P2 hard gates are Blargg `cpu_instrs`, `instr_timing`, and
`mem_timing`; Mooneye timer/MBC1/PPU/OAM subset (15 ROMs); and `dmg-acid2`.
Blargg `interrupt_time` is CGB-only and is not a P2 gate.

`measure_rss.sh` creates its own deterministic synthetic 8 MiB ROM, runs 60
headless frames under `/usr/bin/time`, and requires a byte-identical framebuffer
dump across three runs. It prints `rss_kb`, `fb_bytes`, `rom_bytes`, and
`determinism`; if `/usr/bin/time` is unavailable it prints `SKIP` and exits 77.

## P3 gates

```sh
ZIG=/path/to/zig1_5_clean

# Full Blargg dmg_sound, memory protocol ($A000/$A004):
bash examples/z98/z9gb/tests/tier_audio.sh --gate "$ZIG"

# Win32 probes, z9gb windowed smoke, and the 2048.gb Wine gate:
bash examples/z98/z9gb/tests/tier_win32.sh "$ZIG"
bash examples/z98/z9gb/tests/tier_win32.sh --smoke "$ZIG"
bash examples/z98/z9gb/tests/tier_win32.sh --perf "$ZIG"

# Host headless 2048.gb throughput + Wine windowed performance:
bash examples/z98/z9gb/tests/tier_perf.sh "$ZIG"
```

P3 hard gates are `dmg_sound` (status 0, terminal `Passed`, no `Failed` under
the documented memory protocol) and the named homebrew `2048.gb`
(`Sanqui/2048-gb`, commit `e44f94f898c1e0de7caa1160c82c0da36ff5eb05`, sha256
`3ea2376b…d66d3d7f`, 32,768 bytes). The authoritative performance gate is
**host headless** `--headless --frames 600 --audio`: sustained rendered fps over
the 600-frame window at the 59.7275 Hz GB clock, threshold **59.0 fps**.
`tier_perf.sh` builds that host output at `-O2`. The **Wine windowed**
`--windowed --frames 600 --audio` path is measured **evidence only**: it never
changes the host threshold and never fails closeout on fps, although a Wine
build failure, missing/mismatched ROM, failed run, missing QPC timing, or
missing framebuffer still fails. Missing ROMs are `SKIP` and block closeout; a
hash mismatch is `FAIL`. Wine numbers are Wine evidence only, never Win98 or
real-hardware evidence.

### External ROM setup

No third-party ROM bytes are committed. The gate runners read
`Z9GB_ROM_DIR` and fall back to `/tmp/z9gb_roms` when it exists, otherwise to
`examples/z98/z9gb/testdata/roms`. Populate that tree using the pinned sources
in [`testdata/roms/README.md`](testdata/roms/README.md), then verify:

```sh
REPO="$PWD"
cd "${Z9GB_ROM_DIR:-/tmp/z9gb_roms}"
sha256sum -c "$REPO/examples/z98/z9gb/testdata/roms/manifest.sha256"
```

The committed `dmg-acid2` framebuffer golden lives at
`testdata/golden/dmg-acid2.fb`; it is derived from the author's reference PNG,
not from this emulator. No ROM or reference PNG is committed.

## P2 closeout evidence (2026-11-10)

Compiler: `/tmp/z9gb_p2_seed/zig1_5_clean` (v147, md5
`73c75a65e30dfd212fdf93ae1e57a687`). ROM root: `/tmp/z9gb_roms`.

```sh
$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all
...
== tier_dmg summary: 41 passed, 0 failed ==
TIER_DMG PASS
# rc=0
# CPU 1838 checks, timer 110, PPU 126, save 101 (fast + safe)

$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates
...
blargg: 3 passed, 0 failed, 0 skipped
mooneye: 15 passed, 0 failed, 0 skipped
acid2: PASS c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083
== tier_dmg summary: 3 passed, 0 failed, 0 skipped ==
TIER_DMG PASS
# rc=0

$ bash examples/z98/z9gb/tests/measure_rss.sh "$ZIG" /tmp/z9gb_p2_rss
rss_kb=9916
fb_bytes=92160
rom_bytes=8388608
determinism=identical (3 runs)
# rc=0
```

Per-run peak RSS was 9916 / 9668 / 9768 KiB, all below 12000. The three
framebuffer dumps are byte-identical (three-run `cmp`): 92,160 bytes each.

Corpus classification (`scripts/corpus/classify` with the same compiler):
`rc=0`, 1279 dirs = **1093 OK / 63 GREEN / 123 FAIL / 0 ICE / 0 CRASH**
(class md5 `47cac0ca24240759d0df922e5fd7a976`). This is the v147 1278-dir
anchor plus the new `examples/z98/z9gb` corpus entry (OK); the example matrix
remains **29/29** dump/gcc/link.

## P3 gate evidence (2026-11-11)

Compiler `/tmp/z9gb_p2_seed/zig1_5_clean`, ROM root `/tmp/z9gb_roms`.
These are single measured runs from the final fix-wave verification on
2026-11-11; they are not guarantees and vary with host load.
`tier_audio.sh --gate` prints `TIER_AUDIO PASS` (`dmg_sound` sha256
`c34e7406…401630`, `Passed`, `frames=2133 status=0`).

**Authoritative host headless gate.** `tier_perf.sh` measured the host headless
path at **1034.483 fps** (`wall=0.58 s`, `cpu_user=0.58 s`, `cpu_sys=0.00 s`,
`rss_kb=1904`, `-O2` emitted-C build) over `--headless --frames 600 --audio`.
That is **PASS** against the 59.0 fps threshold and is the performance gate.

**Wine windowed evidence (non-authoritative).** The Wine path is a separate
`-O2` no-CRT build, `--windowed --scale 2 --frames 600 --audio`, QPC-timed over
the 600-frame window. Sandbox Wine measured **47.651 fps**
(`qpc_seconds=12.591563`, `child_rc=0`, `wall=12.76 s`, `cpu_user=6.26 s`,
`cpu_sys=0.07 s`, `rss_kb=40348`). Sandbox Wine can start but is painfully
slower than out-of-sandbox Wine; sandbox QPC is non-authoritative.
Operator-supplied out-of-sandbox QPC evidence from earlier measured runs:
600 frames / 10.438735 s = **57.48 fps**;
120 / 2.411 s = **49.77 fps**; 1800 / 30.5818 s = **58.86 fps**; no-audio
600 frames = 10.438735 s; linear fit ≈ **0.40 s fixed startup + 16.77 ms/frame
= 59.64 fps**. These are Wine evidence, never Win98 or real-hardware evidence;
the operator-supplied numbers are non-authoritative and do not block closeout.
The separate 120-frame windowed smoke (`tier_win32.sh --smoke`) is unaffected.

## P4 CGB closeout evidence (2026-11-11)

Compiler `/tmp/z9gb_p2_seed/zig1_5_clean`, ROM root `/tmp/z9gb_roms`,
CGB reference `/tmp/phase4_p4_probe/reference/cgb-acid2-reference.png`. These
are single measured runs from the P4 closeout; they are not guarantees and vary
with host load.

```sh
$ bash examples/z98/z9gb/tests/tier_smoke.sh "$ZIG"
== tier_smoke summary: 18 passed, 0 failed ==
TIER_SMOKE PASS
# rc=0

$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG"
== tier_dmg summary: 49 passed, 0 failed ==
TIER_DMG PASS
# rc=0

$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates
blargg: 3 passed, 0 failed, 0 skipped
mooneye: 15 passed, 0 failed, 0 skipped
acid2: PASS c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083
== tier_dmg summary: 3 passed, 0 failed, 0 skipped ==
TIER_DMG PASS
# rc=0

$ bash examples/z98/z9gb/tests/tier_audio.sh "$ZIG"
== tier_audio summary: 10 passed, 0 failed, 0 skipped ==
TIER_AUDIO PASS
# rc=0

$ bash examples/z98/z9gb/tests/tier_win32.sh "$ZIG"
== tier_win32 summary: 35 passed, 0 failed, 0 skipped ==
TIER_WIN32 PASS
# rc=0

$ bash examples/z98/z9gb/tests/tier_cgb.sh "$ZIG"
== tier_cgb summary: 18 passed, 0 failed, 0 skipped ==
TIER_CGB PASS
# rc=0
```

The CGB hard gates all passed: `cgb-acid2` framebuffer SHA-256
`0fba336ce7d7cb4ef76049a4548ff0e7a5147be79fb34bfd266ce7bb71fcf9fd`;
Blargg `cgb_sound` sha256 `de2101eb…82053b`, `Passed`,
`frames=2183 status=0`; Blargg `interrupt_time` sha256 `1a8f8f3b…3424929`,
`Passed`, `frames=30 status=0`. The `cgb-acid2` golden comes from the official
`mattcurrie/cgb-acid2` v1.1 reference PNG (SHA-256
`9ea9c262c5383353e77d715d021a0f7c5ccbe438f88082cb225756e50c4fdf01`), not from
this emulator.

```sh
$ bash examples/z98/z9gb/tests/measure_rss.sh "$ZIG" /tmp/z9gb_p4_rss --cgb
rss_kb=10288
fb_bytes=92160
rom_bytes=8388608
cgb=1
determinism=identical (3 runs)
# rc=0
```

CGB-measured host performance: `tier_perf.sh "$ZIG" --cgb` measured
**983.607 fps** (`wall=0.61 s`, `cpu_user=0.61 s`, `cpu_sys=0.00 s`,
`rss_kb=1896`, `-O2` emitted-C build) over `--headless --cgb --frames 600
--audio` on `2048.gb`. That is **PASS** against the unchanged 59.0 fps
threshold. **Wine windowed DMG-mode evidence (non-authoritative):** the Wine path
delegates to `tier_win32.sh --perf`, does not receive `--cgb`, and runs the
DMG-compatible workload; it measured **47.620 fps** (`qpc_seconds=12.599755`,
`child_rc=0`, `wall=12.88 s`, `cpu_user=6.31 s`, `cpu_sys=0.05 s`,
`rss_kb=40248`). This is Wine evidence only, never Win98 or real-hardware
evidence, and never a threshold change.

## P5 dynarec closeout evidence (2026-11-12)

Compiler `/tmp/z9gb_p2_seed/zig1_5_clean`, ROM root `/tmp/z9gb_roms`.
These are single measured runs from the P5 closeout; they are not guarantees and
vary with host load. No external hard gate was skipped.

```sh
$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all
== tier_dmg summary: 49 passed, 0 failed ==
TIER_DMG PASS

$ bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates
blargg: 3 passed, 0 failed, 0 skipped
mooneye: 15 passed, 0 failed, 0 skipped
acid2: PASS c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083
== tier_dmg summary: 166 passed, 0 failed, 0 skipped ==
TIER_DMG PASS

$ bash examples/z98/z9gb/tests/tier_cgb.sh "$ZIG"
== tier_cgb summary: 39 passed, 0 failed, 0 skipped ==
TIER_CGB PASS

$ bash examples/z98/z9gb/tests/tier_smoke.sh "$ZIG"
== tier_smoke summary: 18 passed, 0 failed ==
TIER_SMOKE PASS

$ bash examples/z98/z9gb/tests/tier_audio.sh --gate "$ZIG"
== tier_audio summary: 9 passed, 0 failed, 0 skipped ==
TIER_AUDIO PASS

$ bash examples/z98/z9gb/tests/tier_dynarec.sh "$ZIG"
== tier_dynarec summary: 26 passed, 0 failed, 0 skipped ==
TIER_DYNAREC PASS

$ bash examples/z98/z9gb/tests/tier_win32.sh "$ZIG"
== tier_win32 summary: 39 passed, 0 failed, 0 skipped ==
TIER_WIN32 PASS

$ bash examples/z98/z9gb/tests/tier_win32.sh --smoke "$ZIG"
== tier_win32 summary: 18 passed, 0 failed, 0 skipped ==
TIER_WIN32 PASS
```

`tier_perf.sh` measured the host headless `--no-dynarec` gate at **833.333 fps**
(`wall=0.72 s`, `cpu_user=0.70 s`, `cpu_sys=0.00 s`, `rss_kb=3088`, `-O2`
emitted-C build); the same host path with `--dynarec` is the interpreter with
dynarec disabled as `reason=unsupported-host` (857.143 fps in this run). Those
host rows are unpaced interpreter throughput; host dynarec is unavailable on
*nix, so they cannot judge dynarec. The Wine windowed evidence measured 47.168
fps (`--no-dynarec`) and 47.622 fps (`--dynarec`); those rows are display-bound
evidence only.

The primary throughput measurement uses `tier_perf.sh --throughput-only`, which
warms up wineserver/exe, then runs three alternating measurements per mode:

```sh
$ bash examples/z98/z9gb/tests/tier_perf.sh "$ZIG" --throughput-only
wine_headless_turbo median mode=no-dynarec runs=3 fps=115.385 tcycles_per_sec=8102769 wall=5.20s cpu_user=5.13s cpu_sys=0.01s rss_kb=15556
wine_headless_turbo median mode=dynarec runs=3 fps=113.852 tcycles_per_sec=7995142 wall=5.27s cpu_user=5.12s cpu_sys=0.01s rss_kb=15468 dynarec=on blocks=192 executed=45382 fallback=10187028 tinstr=129109 minstr=10187028 rejected=11322 coverage=12‰
== tier_perf summary: 2 passed, 0 failed, 0 skipped ==
TIER_PERF PASS
```

On `2048.gb` these medians are 7,995,142 (`--dynarec`) versus 8,102,769
(`--no-dynarec`) T-cycles/sec at 1.2% coverage, i.e. the dynarec is 1.3% slower
on this HALT-heavy workload. The old P5 "no measurable gain" wording came from
this 2048-only, ≤6%-coverage workload and is superseded by the workload matrix
above: at high coverage the dynarec is a real gain (Pinball 97.3% coverage,
19.7% faster), while low/moderate coverage is neutral-to-negative (2048 1.2%,
1.5% slower; Crystal 31.7%, 18.3% slower). No fixed speedup threshold applies.

The full compat matrix is measured with:

```sh
$ bash examples/z98/z9gb/tests/tier_perf.sh "$ZIG" --compat \
    --user-roms /path/to/user/roms
== tier_perf summary: 16 passed, 0 failed, 0 skipped ==
TIER_PERF PASS
```

User ROMs are never committed; a missing user ROM is a truthful `SKIP`, not a
PASS. `tier_perf.sh --cgb` passed 8/0/0 as well; the authoritative host headless
threshold is unchanged at 59.0 fps. All Wine numbers are Wine evidence only,
never Win98.

Anti-vacuous dynarec counters from the final `--dynarec` runs:
`tier_dynarec` 2048 `blocks=192 executed=45382`; `tier_audio` `dmg_sound`
`blocks=210 executed=1165539916`; `tier_cgb` `cgb_sound` `blocks=226
executed=1165245746`, `cgb-acid2` `blocks=114 executed=50018`, and
`interrupt_time` `blocks=8 executed=10265`; `tier_win32` and `--smoke`
`blocks=2 executed=176641`; `tier_perf` Wine 2048 `blocks=192 executed=45382`.
The DMG external gates reported nonzero dynarec counters for each of the 166
checks (for example 15/8227, 57/38370, 62/39639, 65/40589, 112/35003,
126/101700, 148/39306, 154/39252, 163/234417, 178/882783540, 191/869196630).

