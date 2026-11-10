# z9gb

A DMG (original Game Boy) emulator shell for Z98. This example is at **P2: DMG
core**. It runs a DMG CPU, MMU/timer/serial, and a scanline PPU (BG, window,
sprites, palettes, STAT/LYC and mode-access timing), with MBC1, MBC3 (+RTC), and
MBC5 cartridges, battery saves, and a pure-Z98 deterministic headless backend.

It does **not** emulate CGB, audio/APU, a windowed Win32/DirectX backend, or a
dynamic recompiler. The only platform is headless; frames are rendered into a
fixed framebuffer and optionally dumped to disk. There is no heap allocation.

## Building with zig1

The compiler is self-hosted. A seed build
(`scripts/seed/build_from_seed.sh`) puts `lib/` next to the `zig1` binary, and
the compiler searches `<exe-dir>/lib` automatically. `-o <dir>` selects the
output directory (create it first) and emits a complete self-contained C89 tree
with a companion `build_target.sh`.

### Linux

```sh
mkdir -p /tmp/z9gb_p2
/path/to/zig1_5_clean -ffast -o /tmp/z9gb_p2 main.zig
sh /tmp/z9gb_p2/build_target.sh linux /tmp/z9gb_p2/z9gb
/tmp/z9gb_p2/z9gb --headless --frames 1 --fb-out /tmp/z9gb_p2.fb
```

The emitted framebuffer file is 92,160 bytes: 160×144 little-endian RGB32
pixels, written identically on every run.

## Usage

```sh
z9gb [--headless] [--frames <n>] [--fb-out <path>] [--rom <path>]
     [--serial] [--turbo] [--mooneye] [--save] [--rtc-fixed <unix>]
```

- `--headless` selects the headless platform (the only backend). It never opens
  a window and imports no Win32 or DirectX header.
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
- `--turbo` skips frame pacing for headless gate runs.
- `--mooneye` stops before the `LD B,B` breakpoint and prints the full
  B/C/D/E/H/L register signature.
- `--save` writes battery RAM (and the `.rtc` file when the cartridge has one)
  at normal exit.
- `--rtc-fixed <unix>` freezes the MBC3 RTC clock to a Unix epoch for
  deterministic runs; without it the RTC uses the host wall clock.

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

