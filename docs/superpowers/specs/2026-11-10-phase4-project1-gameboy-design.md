# Phase 4 Project 1 — DMG/CGB Game Boy Emulator Design

**Date:** 2026-11-10
**Branch:** `zig1_improvements`
**Baseline:** HEAD `3bc3d6a9`, seed v149, lib 65, corpus 1279
**Status:** design for implementation
**Scope:** original Game Boy (DMG) and Game Boy Color (CGB), not GBA

## 1. Intent

Build a real, playable Game Boy emulator on Z98 for Win9x, with a deterministic
headless backend for Linux testing. The emulator is the Phase 4 flagship: it
proves that the same language and runtime can carry a cycle-sensitive,
memory-tight, graphics- and audio-heavy application down to the metal.

The project is delivered as five sequential plans. Each plan produces working,
testable software on its own:

1. **P1 — platform abstraction + headless backend.**
2. **P2 — headless DMG core (M1–M4).**
3. **P3 — playable DMG (M5–M6).**
4. **P4 — CGB (M7).**
5. **P5 — SM83 dynarec (M8).**

The dynarec is required. It is not an optional showcase.

## 2. Goals

- Run DMG and CGB games and test ROMs accurately enough for the pinned gates.
- Full SM83 CPU, MMU, MBC1/MBC3+RTC/MBC5, scanline PPU, timers, interrupts,
  HALT, OAM DMA, serial harness, APU, battery saves.
- Windowed DirectDraw presentation at integer scale 1x/2x/3x/4x.
- Keyboard and gamepad input through DirectInput8.
- DirectSound audio with a WinMM `waveOut` fallback.
- A deterministic headless backend used by every test tier.
- Zero dynamic allocation in hot paths; fixed static storage; 12 MiB RSS target.
- A full SM83 block dynarec with interpreter fallback, integrated and measured.
- Keep the reusable pieces in the Z98 std layer, not in the emulator:
  raw pixel/DirectDraw surface, DirectSound, DirectInput.

## 3. Non-goals

- No GBA, NDS, or other Nintendo platforms.
- No pixel-FIFO PPU accuracy in this project; scanline rendering is the target.
- No fullscreen exclusive mode, page flipping, or `SetDisplayMode`.
- No D3D, shaders, or texture filtering.
- No save states, rewind, cheats, link cable, or multiplayer.
- No ROM, BIOS, or boot-ROM redistribution. No commercial ROM bytes are tracked.
- No native X11/Wayland backend in Phase 4; Linux is headless. Windowed Linux is
  Wine-only.
- No new compiler features or builtins.
- No thread-based audio; the emulator stays single-threaded.

## 4. Anti-goals

- Shipping a "fast" dynarec that fails test ROMs or falls back silently.
- Shipping a windowed path that only works under Wine and is claimed to work on
  real Win98 hardware without evidence.
- Hiding missing external ROMs as PASS. Missing ROMs are SKIP.
- Letting the emulator allocate per frame or per instruction on the heap.
- Growing the stack to hold ROM, VRAM, framebuffers, or the code cache.
- Turning `std_gfx` (ASCII cells) into the emulator display path.

## 5. Constraints

### 5.1 Language and portability

- Pure Z98: no `@cImport`, `asm`, intrinsics, C macros, generics, methods,
  `anytype`, or `@alignCast`.
- OS bindings use `@cInclude` plus `extern "stdcall"` function pointers and
  hand-written COM vtables, following `sf/src/std_gfx_pal.zig`.
- No Win32 handle, HWND, COM pointer, or DirectX type appears in an app-facing
  struct. Opaque `*void` is allowed only where an OS handoff is unavoidable.
- Win9x build uses the no-CRT `-osw 9x` path. DirectDraw, DirectSound, and
  DirectInput are loaded dynamically; no new static DLL import is required.
- **Windows runtime floor (operator ruling):** `IDirectDraw7` requires the DX6+
  runtime; `dinput8.dll` requires a DirectX 8 runtime (stock Win98 ships DX5).
  Both are documented requirements. Without `dinput8.dll`, the input layer
  falls back to keyboard-only `GetAsyncKeyState`; a failed DirectDraw7
  `QueryInterface` is a clean, documented open failure ("install the DX6+
  runtime"), not a crash. The gamepad path is DInput8.
- Linux builds the headless backend only. Any Win32-only module is path-imported
  only by the Win32 backend.

### 5.2 Memory model

The binding limits are separate. Do not confuse them.

| Region | Limit | Notes |
|---|---:|---|
| Call stack | **1 MiB** | Only stack frames. Hot paths must not allocate large locals. |
| Dynarec code cache | **1 MiB** | Separate `VirtualAlloc` executable mapping. Not stack. |
| ROM | **8 MiB** | Static/BSS `[8 MiB]u8`. Counts toward RSS. |
| Cart RAM | **128 KiB** | Static `[131072]u8` (MBC5 max); `ram_size` selects the active prefix. |
| Emulator state | fixed | CPU, MMU, PPU, APU, palettes, OAM, HRAM, IO, save-RAM. |
| Framebuffer | **92,160 B** | `[160 * 144]u32`, 0x00RRGGBB. |
| DDraw offscreen | **1,474,560 B** | 640x576x4 max. Driver-owned primary is extra. |

- ROM, VRAM, WRAM, OAM, framebuffer, audio ring, and code cache are **not**
  stack allocations.
- Static/global allocations may exceed 1 MiB. The stack must not.
- Provisional **12 MiB RSS** target. P1 measures headless; P3 measures
  windowed+audio; P4/P5 re-measure. Report stack, cache, static, and driver
  surfaces separately.
- `std.pool`/`std.gpa` are fallback tools only if measurement proves a need.
  The default is fixed arrays.

### 5.3 Test assets and evidence

- No third-party ROM bytes are committed. Track only:
  - `examples/z98/z9gb/testdata/roms/README.md` (provenance and exact versions)
  - `examples/z98/z9gb/testdata/roms/manifest.sha256`
  - a `.gitignore` that excludes `*.gb`, `*.gbc`, `*.sav`, `*.rtc`.
- Synthetic ROMs authored in this repo are tracked under
  `examples/z98/z9gb/testdata/synth/`.
- Missing external ROMs cause a distinct `SKIP`; milestone closeout requires
  present/passing. A missing ROM never prints PASS.
- Pinned external suites:
  - Blargg `retrio/gb-test-roms` commit
    `c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15`.
  - Mooneye `Gekkio/mooneye-test-suite` commit
    `31510e12eea6286d36eea060a6adde755e1067aa`.
  - SameSuite `LIJI32/SameSuite` commit
    `f15645fb049a47ea235f6d2c9a033e72d8087901`.
  - `dmg-acid2` release `v1.0`, file `dmg-acid2.gb`, 32768 bytes.
  - `cgb-acid2` release `v1.1`, file `cgb-acid2.gbc`, 32768 bytes.
- Reference framebuffer goldens for `dmg-acid2`/`cgb-acid2` are committed as
  160x144 RGB32 hashes. They are expected outputs, not ROM bytes. Goldens are
  pinned to exact render settings and capture frame 120 in the plan's harness.
  - `dmg-acid2`: DMG palette `0x009BBC0F`/`0x008BAC0F`/`0x00306230`/
    `0x000F380F` from the reference image.
  - `cgb-acid2`: official `img/reference.png` from `mattcurrie/cgb-acid2` v1.1,
    with each 5-bit CGB component expanded as `(c << 3) | (c >> 2)`.
  If a golden is absent, the visual gate is SKIP.

- Real Win98/Pentium II sign-off is the operator's. Wine/cross-build is
  functional evidence only.

### 5.4 Hard gates

- P2: Blargg `cpu_instrs`, Mooneye timer/PPU subset, `dmg-acid2` framebuffer
  golden, synthetic DMG boot tests.
- P3: full Blargg `dmg_sound` (verdict-harness semantics), named homebrew
  `2048.gb` (`Sanqui/2048-gb`, zlib; user-supplied bytes) **host headless**
  sustained ≥ 59.0 rendered fps at the 59.7275 Hz GB clock; Wine windowed is
  evidence only and never Win98. Sandbox Wine starts but is painfully slower
  than out-of-sandbox runs; operator-supplied Wine numbers are recorded as
  non-authoritative. DirectDraw/Input/Sound import and runtime checks.
- P4: `cgb-acid2` framebuffer golden, `cgb_sound`, CGB `interrupt_time`, CGB benchmark numbers.
- P5: full test-ROM/homebrew parity with the interpreter; no fixed speedup gate.

## 6. Current state

- P1–P3 are complete on `zig1_improvements` at `3bc3d6a9` (P4 not started).
  Seed is v149, `lib/` has 65 std files, and the live corpus has 1279 dirs.
- `examples/z98/z9gb/` contains the P1–P3 emulator: platform table, headless
  backend, DMG CPU/MMU/PPU/timer/serial/MBC1/MBC3/MBC5/saves, APU, Win32
  DirectDraw/DirectInput8/DirectSound backend, JOYP input, and P2/P3 tiers.
- `sf/src/std_ddraw.zig` + `std_ddraw_pal.zig` provide the windowed DirectDraw7
  pixel surface; `std_dinput.zig` + `std_dinput_pal.zig` provide DirectInput8
  keyboard/gamepad; `std_dsound.zig` + `std_dsound_pal.zig` provide DirectSound
  with the WinMM `waveOut` fallback. These are path-imported, not barrel
  exports.
- `sf/src/std_time.zig` exposes `QueryPerformanceCounter`; the Win32 backend
  uses `timeBeginPeriod(1)`/`timeEndPeriod(1)` with a bounded spin tail.
- `scripts/win32_cross/check_win9x_imports.sh` allows KERNEL32, WINMM, WSOCK32,
  DDRAW, GDI32, and USER32; DirectDraw/DirectSound/DirectInput are loaded
  dynamically. No static `DDRAW.DLL`/`DSOUND.DLL`/`DINPUT8.DLL` import is used.
- P2 DMG gates are `cpu_instrs`, `instr_timing`, `mem_timing`, the Mooneye
  timer/PPU/OAM/MBC1 subset, and the `dmg-acid2` golden. P3 gates are
  `dmg_sound` (memory protocol) and host-headless `2048.gb` ≥ 59.0 fps.
- P4 is the remaining CGB work: CGB mode/palettes, VRAM/WRAM banking, double
  speed, HDMA, `cgb-acid2`, `cgb_sound`, and CGB `interrupt_time`.


## 7. Approaches considered

1. **Emulator-local platform only** — fastest to start, no std churn, but the
   DirectDraw/DirectSound/DirectInput bindings would be trapped in the example
   and unavailable to later projects. Rejected.
2. **Extend `std_gfx` cell grid with raw pixels** — reuses the existing window
   and DDraw code, but mixes two incompatible display models and forces the
   emulator through a text API. Rejected.
3. **New std low-level modules + emulator backend table** — chosen. `std_ddraw`
   owns the pixel surface, `std_dsound` owns audio, `std_dinput` owns input, and
   the emulator owns a small backend table. The headless backend lives in the
   emulator and never imports Win32.
4. **Fullscreen/page flip** — era-authentic, but more failure modes and not
   needed for a 160x144 image. Windowed integer scaling with `Blt` is chosen.
5. **DirectSound callback thread / lock-free ring** — lower latency, but adds
   threading and synchronization to a single-threaded emulator. Chosen:
   single-threaded DirectSound secondary buffer refilled from `GetCurrentPosition`
   plus a WinMM `waveOut` fallback.
6. **Dynarec first / interpreter optional** — dynarec can hide correctness bugs.
   Rejected. Interpreter is the oracle; dynarec is added last with full parity.
7. **Pixel FIFO PPU** — more accurate, much more work. Rejected for this
   project. Scanline rendering is the pinned target.
8. **One umbrella plan** — too large to review and recover. Rejected in favor
   of five sequential plans.

## 8. Architecture

### 8.1 Repository layout

```
examples/z98/z9gb/
  main.zig                 CLI, event loop, frame pacing
  emu.zig                  Emu facade, frame stepping, save hooks
  cpu.zig                  SM83 interpreter
  mmu.zig                  64 KiB address space, DMA, IO routing
  cart.zig                 header, MBC1/MBC3/MBC5, RTC, RAM
  ppu.zig                  scanline PPU, DMG/CGB rendering
  apu.zig                  4-channel APU, frame sequencer, mixer
  timer.zig                DIV/TIMA/TMA/TAC
  serial.zig               serial harness
  save.zig                 .sav/.rtc format and atomic persistence
  platform/backend.zig     open/present/poll/audio/close table
  platform/headless.zig    deterministic framebuffer/audio/input backend
  platform/win32.zig       DirectDraw/DirectSound/DirectInput backend
  dynarec/                 P5: cache.zig, x86.zig, block.zig, dynarec.zig
  testdata/                manifests, synthetic ROMs, goldens
  tests/                   tier scripts and expected outputs
```

`examples/z98/z9gb/main.zig` makes the directory a corpus entry automatically.
No `scripts/stdlib/expected_dirs.txt` entry is added for the example.

### 8.2 Emulator facade

```zig
pub const EmuConfig = struct {
    cgb: bool,
    serial_log: bool,
    turbo: bool,
    dynarec: bool,
};

pub const EmuError = error{
    RomTooLarge,
    BadHeader,
    UnsupportedMbc,
    CgbRequired,
    SaveCorrupt,
    Io,
    OutOfMemory,
};

pub const Emu = struct { /* fixed storage; no heap */ };

pub fn emuInit(e: *Emu, cfg: EmuConfig) void;
pub fn emuLoadRom(e: *Emu, path: []const u8) EmuError!void;
pub fn emuReset(e: *Emu) void;
pub fn emuRunFrame(e: *Emu) u32;                 // T-cycles executed
pub fn emuFramebuffer(e: *const Emu) []const u32; // 160*144, 0x00RRGGBB
pub fn emuAudioSamples(e: *Emu, out: []i16) usize;
pub fn emuSetButtons(e: *Emu, bits: u8) void;
pub fn emuTakeSerial(e: *Emu, out: []u8) usize;
pub fn emuSetSavePath(e: *Emu, path: []const u8) void;
pub fn emuSaveBattery(e: *Emu) EmuError!void;
pub fn emuLoadBattery(e: *Emu) EmuError!void;
```

CLI flags: `--headless`, `--windowed`, `--frames N`, `--rom PATH`, `--fb-out`,
`--serial`, `--turbo`, `--cgb` (sets `EmuConfig.cgb`; a CGB-only ROM — header
`0x0143 == 0xC0` — without `--cgb` fails `CgbRequired`), `--dynarec` /
`--no-dynarec` / `--dynarec-stats`, `--scale N` (1..4), `--save`,
`--no-audio`, `--mooneye`.

Button bits, LSB-first:

```
0 right, 1 left, 2 up, 3 down, 4 a, 5 b, 6 select, 7 start
```

`Emu` is allocated once by `main.zig` as a static/global, not on the stack.

### 8.3 Platform backend

The emulator owns a five-field table; it leaks no Win32 types.

```zig
pub const InputState = struct {
    buttons: u8, // same bit order as emuSetButtons
    quit: bool,
};

pub const Platform = struct {
    state: *void,
    open_fn: fn (*void, u32, u32, u32) bool,   // width, height, scale
    present_fn: fn (*void, []const u32) void,  // 160*144 RGB32
    poll_fn: fn (*void, *InputState) bool,
    audio_fn: fn (*void, []const i16) void,    // stereo interleaved
    close_fn: fn (*void) void,
};

pub fn platformHeadless() *Platform;
pub fn platformWin32() *Platform; // P3, Win32 only
```

The caller keeps the `Platform` alive for the process lifetime. `poll_fn`
returns `true` when an event was consumed. The headless backend returns `false`
and reads input from CLI/test hooks.

### 8.4 Reusable std modules

P3 adds these path-imported modules. They are not barrel-exported.

**`sf/src/std_ddraw.zig` + `std_ddraw_pal.zig`**

```zig
pub const DdrawError = error{ OpenFailed, SurfaceFailed, NotSupported };

pub const DdrawEvent = struct {
    kind: u8,     // 0 key-down, 1 key-up, 2 close, 3 focus
    key: u16,     // VK code for key events
    close: bool,
};

pub const Ddraw = struct { opaque: *DdrawState };

pub fn ddrawOpen(title: []const u8, src_w: u32, src_h: u32, scale: u32) DdrawError!*Ddraw;
pub fn ddrawPresent(d: *Ddraw, pixels: []const u32) bool;
pub fn ddrawPoll(d: *Ddraw, ev: *DdrawEvent) bool;
pub fn ddrawSetScale(d: *Ddraw, scale: u32) bool;
pub fn ddrawWindow(d: *Ddraw) *void;
pub fn ddrawClose(d: *Ddraw) void;
```

- 32-bit `0x00RRGGBB` source pixels.
- Offscreen surface is 640x576 maximum, locked and written through the real
  `IDirectDrawSurface7::Lock`/`Unlock` slots; present is `Blt` to the primary
  with `DDBLT_WAIT`.
- Integer scales 1/2/3/4 only. Window client is `src_w*scale` x `src_h*scale`.
- No fullscreen, no `Flip`, no `BltFast`, no `SetDisplayMode`.
- `src_w`/`src_h` are fixed for the lifetime of the surface.

**`sf/src/std_dinput.zig` + `std_dinput_pal.zig`**

```zig
pub const DinputError = error{ OpenFailed, NotSupported };

pub const Dinput = struct { opaque: *DinputState };

pub fn dinputOpen(window: *void) DinputError!*Dinput;
pub fn dinputPoll(d: *Dinput, out: *Buttons) void;
pub fn dinputClose(d: *Dinput) void;

pub const Buttons = struct {
    right: bool, left: bool, up: bool, down: bool,
    a: bool, b: bool, select: bool, start: bool,
    quit: bool,
};
```

- Primary path: dynamically loaded `dinput8.dll`, `DirectInput8Create`,
  keyboard + first attached gamepad, non-exclusive foreground.
- Fallback: if `dinput8.dll` is missing or `DirectInput8Create` fails, use
  `GetAsyncKeyState` for keyboard. Gamepad is unavailable in fallback.
- Default keys: arrows = D-pad, Z = A, X = B, Enter = Start, Backspace = Select,
  Escape = quit. Gamepad mapping is fixed in the module docs.
- No Win32 device pointer or `GUID` leaves the module.

**`sf/src/std_dsound.zig` + `std_dsound_pal.zig`**

```zig
pub const DsoundError = error{ OpenFailed, BufferFailed, Lost };

pub const Dsound = struct { opaque: *DsoundState };

pub fn dsoundOpen(window: *void, sample_rate: u32, channels: u16) DsoundError!*Dsound;
pub fn dsoundWrite(d: *Dsound, samples: []const i16) usize; // i16 elements consumed
pub fn dsoundQueued(d: *Dsound) usize;                      // i16 elements
pub fn dsoundBackendKind(d: *const Dsound) u8;              // 1 DirectSound, 2 waveOut
pub fn dsoundClose(d: *Dsound) void;
```

- Format: signed 16-bit PCM, stereo interleaved, 44,100 Hz.
- DirectSound path: `DirectSoundCreate`, `IDirectSoundBuffer`, 2,048 stereo
  frames (8,192 bytes, 46.4 ms), `DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_GLOBALFOCUS`,
  prefill one buffer at `Play`, looping `Play`, refill from `GetCurrentPosition`.
- `dsoundWrite` never blocks and may consume fewer samples than offered.
- If DirectSound creation or buffer creation fails, fall back to WinMM
  `waveOut` with the same API. The fallback uses two buffers.
- No callback thread, no lock-free cross-thread ring.

### 8.5 CPU and memory

- SM83 instruction-granularity interpreter, one global T-cycle counter.
- Primary opcode `switch` plus nested `0xCB` `switch`; every switch has `else`.
- Module-scope opcode constants and cycle tables; case labels cannot be local
  `const`.
- 256-entry instruction-length table and 256-entry base-cycle table.
- Post-boot state: `A=0x01, F=0xB0, B=0x00, C=0x13, D=0x00, E=0xD8, H=0x01,
  L=0x4D, SP=0xFFFE, PC=0x0100`; I/O registers at documented DMG defaults;
  `LY=0x91`.
- HALT bug (PC double-fetch in the fetch path), EI delay, interrupt dispatch,
  and OAM DMA implemented explicitly. Timer glitch edges are implemented:
  DIV-write reset and TAC-write mux changes can spuriously tick TIMA, and
  TIMA holds 0 for one M-cycle (4 T-cycles) before the TMA reload + IF raise.
- Address map:
  - `0000-3FFF` ROM0, `4000-7FFF` switchable ROM
  - `8000-9FFF` VRAM, `A000-BFFF` cart RAM
  - `C000-DFFF` WRAM, `E000-FDFF` echo
  - `FE00-FE9F` OAM, `FEA0-FEFF` unusable
  - `FF00-FF7F` I/O, `FF80-FFFE` HRAM, `FFFF` IE.
- `*volatile T` is used only for the I/O window. Main ROM/RAM/VRAM/WRAM are
  plain arrays indexed directly.

### 8.6 PPU

- DMG scanline renderer: 456 T-cycles per line, 154 lines.
- Modes 0 (HBlank), 1 (VBlank), 2 (OAM), 3 (VRAM); STAT interrupts for mode
  0/1/2 and LYC=LY.
- CPU OAM access is blocked in modes 2 and 3; CPU VRAM access is blocked in
  mode 3. Blocked reads return `0xFF`, blocked writes are ignored; modes 0/1
  and LCD-off remain accessible. OAM DMA uses the raw path and is not blocked.
- Background, window, 8x8/8x16 sprites, sprite priority, DMG palettes.
- Framebuffer is RGB32, 160x144, top-left origin.
- `dmg-acid2` golden is a 160x144 RGB32 hash; gate fails on any byte mismatch.
- CGB adds VRAM bank 1 attributes, CGB palettes, and priority rules in P4.

### 8.7 Cartridge, MBC, RTC, saves

- Header at `0x0100-0x014F`; reject ROMs larger than 8 MiB or shorter than
  32 KiB. Read the title for diagnostics only.
- MBC type mapping:
  - `0x00` no MBC
  - `0x01-0x03` MBC1
  - `0x0F-0x13` MBC3 with RTC for `0x0F`/`0x10`
  - `0x19-0x1E` MBC5
- MBC1 hardware edges (gated by Mooneye `emulator-only/mbc1/*`): the 5-bit
  register value 0 reads as 1 before combining (banks `0x20/0x40/0x60` are
  unreachable), the 2-bit register contributes ROMX bits 5-6 in **both** modes,
  and in mode 1 it additionally banks the ROM0 window (`0000-3FFF`).
- RTC advances by **delta accumulation** against a host timestamp anchor
  (add elapsed whole seconds at observation, re-anchor immediately). Writes
  target live counters; reads return latched copies; the halt flag freezes
  accumulation; the day counter wraps 511→0. Headless/test runs freeze the
  clock (`rtc_fixed`) for determinism.
- RAM size from header; zero RAM is allowed **unless the cartridge type
  includes RAM**. In that case the type is authoritative for physical RAM:
  the declared size is used when nonzero, otherwise an 8 KiB compatibility
  floor is inferred (`ram_inferred=true`). MBC2's built-in 512x4 RAM is the
  exception and does not use this floor. Types without RAM remain unmapped
  at `$A000-$BFFF`, even when a stray declared RAM size is nonzero. Synthetic
  fixtures must declare a matching type (MBC5+RAM is `0x1A`, not `0x19`).
- `.sav` path: replace the ROM extension with `.sav` unless
  `emuSetSavePath` overrides it.
- `.rtc` path: same stem, `.rtc`.
- `.sav` is the raw cart RAM image. `.rtc` is 32 bytes:
  ```
  0..7   "Z98RTC1\0"
  8      version = 1
  9      seconds
  10     minutes
  11     hours
  12     days low
  13     days high
  14     flags: bit0 halt, bit1 day carry
  15     reserved zero
  16..23 host timestamp anchor (u64 LE unix seconds)
  24..31 zero
  ```
- Save writes use temp file + rename. A corrupt or short `.rtc` is
  `SaveCorrupt`; never overwrite a corrupt file silently.
- Battery write policy: on ROM unload/close and on explicit `--save`; no
  per-frame writes.

### 8.8 APU and timing
- Four channels: two square, wave, noise; frame sequencer at 512 Hz. Hardware
  quirks pinned: sweep shadow frequency + negate-after-enable disable quirk,
  noise width-7 LFSR feedback into bit 6, DMG wave-RAM read-during-playback
  garbage, NRxx read masks / NR52 power-off values, length-counter extra
  clock on NRx4 writes.
- Mixer outputs stereo 16-bit at 44,100 Hz.
- APU sample and frame clocks derive from emulator dot-rate time and are
  unchanged by CGB double speed.
- P3 hard gate: full Blargg `dmg_sound` via the Blargg SRAM memory protocol:
  status `$A000`, signature `DE B0 61` at `$A001-$A003`, text at `$A004`;
  turbo until terminal `Passed`/`Passed all tests.`, cap-without-verdict = FAIL.
- P4 hard gate: `cgb_sound` uses the same Blargg SRAM memory protocol
  (`$A000` status, `$A001-$A003` signature, `$A004` text), not serial. The
  harness runs `--cgb --turbo --frames 200000`; status `0` + terminal
  `Passed`/`Passed all tests.` + no `Failed` = PASS. Per Pan Docs, double
  speed does **not** change any sound timing: the APU stays at its normal rate
  (only CPU/timer/serial/OAM-DMA run 2x).
- P4 hard gate: Blargg `interrupt_time` in CGB mode — CGB-only ROM (header
  `0xC0`) exercising DMG-speed and double-speed interrupt latency; run with
  `--cgb --turbo --frames 200000` using the same `$A000` memory protocol as
  `cgb_sound`/`dmg_sound`, not serial. PASS requires status `0` and terminal
  `Passed`/`Passed all tests.`; cap without a verdict = FAIL. Missing ROM =
  SKIP and P4 closeout cannot claim PASS.
- Frame pacing: QPC deadline; `timeBeginPeriod(1)` (whitelisted WINMM symbol)
  plus a bounded ≤2 ms spin tail, since Win9x `Sleep(1)` quantizes to the
  ~55 ms tick; no unbounded busy-spin.
- If audio falls behind, drop samples; never block the emulator.

### 8.9 Serial harness and memory-protocol verdicts

- `--serial` enables the test serial log.
- On a write to `SC` with bit 7 set:
  - append `SB` to the serial log
  - clear bit 7
  - request the serial interrupt after 8 T-cycles
- `emuTakeSerial` drains the log; the CLI can mirror it to stdout.
- Serial Blargg gates detect the terminal `Passed` or `Passed all tests.`
  verdict; `Failed` is a fail. These runs use turbo with a generous frame cap
  and may exit early once a terminal verdict appears; a capped run without a
  verdict is FAIL.
- CGB `cgb_sound` and `interrupt_time` are **memory-protocol** gates, not
  serial gates: poll `$A000` status, require the `DE B0 61` signature at
  `$A001-$A003`, read the zero-terminated text at `$A004`, and require status
  `0` plus terminal `Passed`/`Passed all tests.` with no `Failed`.


- `--mooneye` enables the Mooneye magic breakpoint: when the next opcode is
  `0x40` (`LD B,B`), stop and report the full Fibonacci register signature
  `B=3, C=5, D=8, E=13, H=21, L=34` as pass; any other register set is a fail.
  This mode is test-only; normal games run `LD B,B` as a NOP.
- The harness is test-only and has no link-cable peer.

### 8.10 Dynarec

- Target: Win32/x86 only. Linux uses the interpreter.
- Fixed **1 MiB** executable mapping via `VirtualAlloc(NULL, 1 MiB,
  MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE)`. This mapping is separate
  from the 1 MiB stack and from static state.
- Block cache: direct-mapped table keyed by **`(rom_bank, pc)`** (keying by PC
  alone would flush the whole cache on every MBC switch), 4,096 entries; block
  max 4 KiB; per-slot replacement; per-bank invalidation on bank switches; full
  arena/table reset only when the 1 MiB arena is exhausted.
- Translation unit: basic block from PC until branch/call/ret/HALT/STOP, `EI`,
  `DI`, `RETI`, an IO write, a cart-control write, or 64 instructions (the
  boundary rules bound interrupt-service drift).
- Generated code caches the CPU pairs in callee-saved host registers
  (`BC→ebx`, `DE→esi`, `HL→edi`, `SP→ebp`) across the block, with `A`/`F` in
  `Cpu` (or `A` in a volatile reg). Memory operands use an inline page-table
  fast path (`bus->pages[addr >> 8]` — 256 entries of 256-byte pages, direct
  `base[addr & 0xFF]` for ROM/WRAM/cart-RAM/**HRAM/echo**; stack ops never
  call helpers) and call helpers only for IO/OAM/VRAM edges (VRAM carries the
  mode-3 lockout check). After every cycle-charging helper, generated code
  tests the pending-interrupt condition (`ime` + `if & ie & 0x1F`) and jumps
  to the block epilogue — without this, interrupt dispatch drifts up to a
  full block and latency gates fail. Blocks chain directly to already-translated
  successors behind a bank/PC guard; `CALL` links to the translated callee the
  same way, and `RET` links through a one-entry return-address cache
  (`ret_target`/`ret_bank`); otherwise blocks return to the dispatcher.
- ABI: `DynCtx` holds `cpu: *Cpu`, `bus: *Bus`, and `cycles: u32`.
  A generated block is `fn (*DynCtx) u32`, cdecl, returning T-cycles. Compiled
  via `@ptrCast` to a function pointer; no inline asm.
- Interpreter remains the oracle and fallback. Any unsupported opcode or
  translation failure runs the interpreter for that instruction.
- Translation covers ROM space (`0000-7FFF`) only; a PC in WRAM/HRAM/VRAM runs
  the interpreter (RAM self-modifying code is a non-problem by construction).
  Any cart-control write ends the containing block at the write and flushes the
  cache. Generated bytes are followed by `FlushInstructionCache` on the range.
- Anti-vacuous contract: `--dynarec` prints `blocks`/`executed`/`fallback`
  counters and `dynarec=disabled reason=...` on failure; a `--dynarec` gate run
  where nothing translated (or dynarec silently disabled) **fails**, never
  passes as interpreter-vs-interpreter.
- P5 parity: all P2–P4 gates pass with dynarec enabled and disabled.
- No fixed speedup gate. Report measured wall/CPU/RSS and correctness.

### 8.11 Test tiers and commands

Each plan adds tier scripts under `examples/z98/z9gb/tests/`:

- `tier_smoke.sh` — build, headless self-test, deterministic framebuffer hash.
- `tier_dmg.sh` — CPU/MMU/PPU/serial gates; SKIP if external ROMs absent.
- `tier_audio.sh` — APU and `dmg_sound`; SKIP if ROM absent.
- `tier_win32.sh` — `-osw` cross-build, import gate, Wine windowed smoke.
- `tier_cgb.sh` — CGB gates.
- `tier_dynarec.sh` — dynarec parity and measurements.

The build recipe is:

```sh
zig1 -ffast -o /tmp/z9gb examples/z98/z9gb/main.zig
sh /tmp/z9gb/build_target.sh linux /tmp/z9gb/z9gb
```

For Win9x:

```sh
zig1 -ffast -osw -o /tmp/z9gbw examples/z98/z9gb/main.zig
# use the emitted MingW/no-CRT recipe
bash scripts/win32_cross/check_win9x_imports.sh <exe> 9x
```

Tests run sequentially, never in parallel, because spill files collide.

## 9. Milestones and plans

| Plan | Deliverable | Hard gate |
|---|---|---|
| P1 | std-free platform table + headless backend + RSS harness | deterministic headless self-test |
| P2 | DMG CPU/MMU/PPU/timer/serial/MBC/saves | `cpu_instrs`, Mooneye subset, `dmg-acid2` hash |
| P3 | DirectDraw/DInput/DirectSound + APU + frame loop | `dmg_sound`; host headless `2048.gb` ≥ 59.0 fps (Wine evidence only) |
| P4 | CGB palettes, banking, double speed | `cgb-acid2`, `cgb_sound`, `interrupt_time` |
| P5 | dynarec with interpreter fallback | full parity, measured |

Plan files:

- `docs/superpowers/plans/2026-11-10-phase4-p1-platform-headless-plan.md`
- `docs/superpowers/plans/2026-11-10-phase4-p2-dmg-core-plan.md`
- `docs/superpowers/plans/2026-11-10-phase4-p3-playable-dmg-plan.md`
- `docs/superpowers/plans/2026-11-10-phase4-p4-cgb-plan.md`
- `docs/superpowers/plans/2026-11-10-phase4-p5-dynarec-plan.md`

## 10. Risks

1. **PPU accuracy.** Scanline rendering may fail edge-case PPU tests. The
   Mooneye subset and `dmg-acid2` are the enforceable bar; pixel FIFO is out.
2. **DirectSound on Win9x.** `dsound.dll` behavior and buffer latency are
   unverified on real hardware. Wine is the functional gate; hardware is the
   operator's.
3. **DirectInput8 runtime.** `dinput8.dll` is a DX8 component. Win98 without
   DX8 gets keyboard-only fallback, not gamepad.
4. **DirectDraw stretch `Blt`.** Some drivers may not stretch reliably. P3 has
   a 1x path and fails closed to `OpenFailed`; the headless path is the
   correctness gate.
5. **1 MiB stack.** Large local arrays in the CPU/PPU/audio paths can overflow.
   All large state is static; stack use is reviewed.
6. **12 MiB RSS.** 8 MiB ROM plus 1.5 MiB surface plus 1 MiB cache plus stack
   and state is tight. P1/P3 measure; target may be revised upward with data,
   not assumed.
7. **Dynarec correctness.** Generated code can diverge silently. Parity is the
   gate; the interpreter remains the oracle.
8. **Executable memory on Win9x.** `VirtualAlloc` `PAGE_EXECUTE_READWRITE` is
   unproven on real hardware. If it fails, dynarec disables itself and the
   interpreter runs; this is not a PASS claim for dynarec.
9. **ROM availability.** External suites are not tracked. Missing ROMs are
   SKIP, and milestone closeout requires the operator to provide them.

## 11. Design calls left to the plans

- Exact tick budgets and test counts.
- Exact PPU sprite penalty and mode-3 length approximations.
- Exact APU mixer scaling and high-pass filter.
- Exact dynarec block IR and helper table.
- Exact seed rotation timing if a plan changes std (`std_ddraw`,
  `std_dsound`, `std_dinput` land in P3; one seed rotation follows that plan).

Anything that changes a public API in this spec is a spec amendment and needs
operator approval.
