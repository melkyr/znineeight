# z9gb

A DMG (original Game Boy) emulator shell for Z98. This example is at **P3:
playable DMG**. It runs a DMG CPU, MMU/timer/serial, a scanline PPU (BG, window,
sprites, palettes, STAT/LYC and mode-access timing), a 4-channel APU, MBC1,
MBC3 (+RTC), and MBC5 cartridges, battery saves, and two backends: a pure-Z98
deterministic headless backend and a Win32 DirectDraw/DirectInput/DirectSound
windowed backend with QPC frame pacing.

It does **not** emulate CGB, a dynamic recompiler, or ship a CGB path. There is
no heap allocation; the single emulator, framebuffer, audio ring, and platform
state are module-scope statics. `--windowed` requires the Win32 target; the
Linux host has only the headless backend.

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

## Building with zig1

The compiler is self-hosted. A seed build
(`scripts/seed/build_from_seed.sh`) puts `lib/` next to the `zig1` binary, and
the compiler searches `<exe-dir>/lib` automatically. `-o <dir>` selects the
output directory (create it first) and emits a complete self-contained C89 tree
with a companion `build_target.sh`.

### Linux

```sh
mkdir -p /tmp/z9gb_p3
/path/to/zig1_5_clean -ffast -I /workspace/znineeight/sf/src \
    -o /tmp/z9gb_p3 examples/z98/z9gb/main.zig
sh /tmp/z9gb_p3/build_target.sh linux /tmp/z9gb_p3/z9gb
/tmp/z9gb_p3/z9gb --headless --frames 1 --fb-out /tmp/z9gb_p3.fb
```

### Win32 (no-CRT, Win95/98 target)

```sh
EXTRA_LIBS="-luser32 -lgdi32 -lwinmm" \
DUMP_TARGET="-osw -I /workspace/znineeight/sf/src" \
bash scripts/win32_cross/cross_nocrt.sh /path/to/zig1_5_clean \
    examples/z98/z9gb/main.zig /tmp/z9gb_p3w /tmp/z9gb_p3w/z9gb.exe
```

The emitted framebuffer file is 92,160 bytes: 160×144 little-endian RGB32
pixels, written identically on every run.

## Usage

```sh
z9gb [--headless | --windowed] [--scale <1..4>] [--frames <n>]
     [--fb-out <path>] [--rom <path>] [--audio | --no-audio]
     [--serial] [--turbo] [--mooneye] [--save] [--rtc-fixed <unix>]
```

- `--headless` selects the headless platform. It never opens a window and
  imports no Win32 or DirectX header.
- `--windowed` selects the Win32 DirectDraw/DirectInput/DirectSound backend.
  It only exists on the Win32 target and needs the DX6+ runtime for
  `IDirectDraw7`; the gamepad additionally needs DX8 `dinput8.dll`.
- `--scale <1..4>` sets the windowed integer scale (default `1`).
- `--audio` / `--no-audio` enables or disables APU output (default on).
- `--frames <n>` runs `n` frames before presenting the framebuffer (default
  `1`).
- `--fb-out <path>` writes the final framebuffer as 160×144 little-endian
  `u32` RGB32 pixels (92,160 bytes).
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
keyboard fallback prints `input=fallback`, and WinMM audio prints `audio=waveout`.

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
  cache** (the code cache is not part of P2).
- The **8 MiB ROM buffer** is a static module-scope buffer inside the single
  `Emu` instance; it is never a stack local and never copied by value.
- The 92,160-byte framebuffer and the platform snapshots are static too.
- P2 performs no heap allocation.

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
cd "${Z9GB_ROM_DIR:-/tmp/z9gb_roms}"
sha256sum -c /workspace/znineeight/examples/z98/z9gb/testdata/roms/manifest.sha256
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
`tier_audio.sh --gate` prints `TIER_AUDIO PASS` (`dmg_sound` sha256
`c34e7406…401630`, `Passed`, `frames=2133 status=0`).

**Authoritative host headless gate.** `tier_perf.sh` measured the host headless
path at **1052.632 fps** (`wall=0.57 s`, `cpu_user=0.57 s`, `cpu_sys=0.00 s`,
`rss_kb=1668`, `-O2` emitted-C build) over `--headless --frames 600 --audio`.
That is **PASS** against the 59.0 fps threshold and is the performance gate.

**Wine windowed evidence (non-authoritative).** The Wine path is a separate
`-O2` no-CRT build, `--windowed --scale 2 --frames 600 --audio`, QPC-timed over
the 600-frame window. Sandbox Wine measured **47.621 fps**
(`qpc_seconds=12.599425`, `wall=12.75 s`, `cpu_user=6.29 s`, `cpu_sys=0.06 s`,
`rss_kb=40528`). Sandbox Wine can start but is painfully slower than
out-of-sandbox Wine; sandbox QPC is non-authoritative. Operator-supplied
out-of-sandbox QPC evidence: 600 frames / 10.438735 s = **57.48 fps**;
120 / 2.411 s = **49.77 fps**; 1800 / 30.5818 s = **58.86 fps**; no-audio
600 frames = 10.438735 s; linear fit ≈ **0.40 s fixed startup + 16.77 ms/frame
= 59.64 fps**. These are Wine evidence, never Win98 or real-hardware evidence;
the operator-supplied numbers are non-authoritative and do not block closeout.
The separate 120-frame windowed smoke (`tier_win32.sh --smoke`) is unaffected.

