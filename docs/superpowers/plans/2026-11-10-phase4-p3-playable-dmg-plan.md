# Phase 4 P3 — Playable DMG Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the DMG playable on Win9x: DirectDraw pixel presentation, DirectInput8 keyboard/gamepad, QPC frame pacing, APU, and DirectSound with a WinMM fallback. Add the reusable `std_ddraw`, `std_dinput`, and `std_dsound` modules.

**Architecture:** `std_ddraw` owns a scalable 32-bit DirectDraw surface; `std_dinput` owns DInput8 devices with a keyboard fallback; `std_dsound` owns a looping DirectSound secondary buffer with a `waveOut` fallback. The emulator's Win32 backend wires those modules into the P1 `Platform` table; the APU fills a static stereo ring.

**Tech Stack:** Z98, `std_ddraw`/`std_ddraw_pal`, `std_dinput`/`std_dinput_pal`, `std_dsound`/`std_dsound_pal`, `std_time`, `std_page`; MinGW headers; Wine; Win9x no-CRT gate.

**Spec:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`

## Global Constraints

- Pure Z98; no `@cImport`, `asm`, intrinsics, macros, generics, methods, `anytype`, or `@alignCast`.
- Public APIs must not leak Win32 handles, COM pointers, or `GUID`.
- DirectDraw/DirectSound/DirectInput load DLLs dynamically. No static `dsound`/`dinput8` import; the Win9x gate must stay green.
- **Windows runtime floor (operator ruling):** `IDirectDraw7` needs the DX6+ runtime (`ddraw.dll` with `DirectDrawCreate` + QI) and `DirectInput8Create` needs `dinput8.dll` (DX8 runtime) — stock Win98 ships DX5. This is a documented requirement: the README must state "requires the DirectX 6/8 runtimes (standard on game-era installs; DX8 runtime provides dinput8)". Missing `dinput8.dll` falls back to the keyboard-only `GetAsyncKeyState` path; a failed DirectDraw7 QI is a documented hard open failure with a clear "install DX6+ runtime" message, not a crash.
- Windowed display is windowed `DDSCL_NORMAL` only. No fullscreen, no `Flip`, no `SetDisplayMode`, no `BltFast`.
- Integer scale 1/2/3/4 only.
- DirectSound path is single-threaded: looping secondary buffer, `GetCurrentPosition` refill. No callback thread and no lock-free cross-thread ring.
- APU output is stereo signed 16-bit PCM at 44,100 Hz.
- 1 MiB stack limit; audio ring/framebuffer/surfaces are static, not stack.
- `dmg_sound` is a hard gate. The pinned Blargg `dmg_sound.gb` reports through its documented SRAM memory protocol, not serial: magic `0xDE,0xB0,0x61` at `0xA001..0xA003`, status at `0xA000`, text at `0xA004`. Run `--turbo --frames 200000`; PASS requires status 0 and terminal `Passed` with no `Failed`; cap without verdict = FAIL. A missing ROM is `SKIP`, never `PASS`, and cannot close the milestone.
- New COM vtables copy slot order **verbatim from the MinGW headers** (`dsound.h`, `dinput.h`) at Task 0 probe time: unused slots are kept as correctly-typed `fn` placeholders, exactly like `sf/src/std_gfx_pal.zig` does for DirectDraw. Expected slot counts to verify and pin: `IDirectSound` 11, `IDirectSoundBuffer` 21, `IDirectInput8A` 11, `IDirectInputDevice8A` 32 — STOP on mismatch.
- The P3 seed rotation is the only seed rotation in Phase 4 unless a later plan changes `sf/src`.
- No `std.zig` barrel change; the three new modules are path-imported and move no emission pins.
- The opaque `Ddraw`/`Dinput`/`Dsound` handles are backed by exactly one module-scope static state each. No heap allocation and no stack-backed state; `*Open` returns `error.OpenFailed` if the module is already open.
- Until seed v148, Tasks 1-6 resolve the new `sf/src/std_ddraw*`, `std_dinput*`, and `std_dsound*` modules with an explicit `-I <repo>/sf/src` on every build/probe command (or an explicit `$ZIG1/lib` refresh). Seed Task 7 is the packaging step.
- Task 0 must obtain and pin both hard-gate assets: `dmg_sound/dmg_sound.gb` from Blargg and `2048.gb` from Sanqui. If either cannot be obtained, STOP and report.

## Review Focus

1. DirectDraw `Lock`/`Unlock` pitch and `Blt` stretch correctness at 1x/2x/3x/4x.
2. DirectInput8 device creation, focus loss/reacquire, keyboard fallback, and no Win32 type leakage.
3. DirectSound buffer wrap math and nonblocking `dsoundWrite`; `waveOut` fallback parity.
4. APU channel timing, frame sequencer, and `dmg_sound`; no host-time audio dependency.
5. Frame pacing: QPC deadline loop; `timeBeginPeriod(1)`/`timeEndPeriod(1)` (WINMM whitelist grows by exactly these two symbols) or a bounded ≤2 ms spin tail when the call is unavailable; no unbounded busy-spin, no late-frame accumulation; audio underrun does not block the CPU.

---

### Task 0: Probe Win32 graphics/audio/input availability

**Files:**
- Temporary only: `/tmp/phase4_p3_probe/*`

**Interfaces:**
- Consumes: P2 headless build; `/tmp/z9gb_p2_seed/zig1_5_clean`; `/tmp/z9gb_roms`.
- Produces: recorded capability matrix; pinned asset hashes; exact vtable slot counts; module-resolution decision.

- [ ] **Step 1: Probe MinGW headers**
Confirm `/usr/i686-w64-mingw32/include/ddraw.h`, `dsound.h`, and `dinput.h` exist. Expected: all present.
- [ ] **Step 2: Probe Wine DLLs**
Run `WINEDEBUG=-all wine --version`; inspect for `ddraw.dll`, `dsound.dll`, and `dinput8.dll` under the Wine prefix. Expected: record which are present; missing `dinput8.dll` means keyboard fallback is the only Wine evidence.
- [ ] **Step 3: Probe DirectDraw dynamic loading**
Compile the existing `gfx_demo` with `-osw` and run its import gate. Expected: `DDRAW.DLL` is not in the static import table; Wine smoke passes.
- [ ] **Step 4: Probe DDraw raw pixel path**
Build a temporary Z98/C probe under `/tmp/phase4_p3_probe` that dynamically creates `IDirectDraw7`, a 160x144 32-bit system-memory offscreen, calls `Lock`/`Unlock` honoring pitch, and does one hardware stretch `Blt` from `0,0,160,144` to a 2x and 4x primary/client rect. Record success/failure. If Lock/Unlock or stretch `Blt` fails under Wine, STOP and report; do not substitute a different display path.
- [ ] **Step 5: Probe `VirtualAlloc` executable mapping (for P5, not used here)**
Call `VirtualAlloc(NULL, 1 MiB, MEM_COMMIT|MEM_RESERVE, PAGE_EXECUTE_READWRITE)` under Wine, write one byte, and free. Expected: record success/failure; P5 uses this result.
- [ ] **Step 6: Probe DirectSound/DirectInput and timer availability**
Under Wine, dynamically create `IDirectSound` and `IDirectInput8A`, create a keyboard device, and record which DLLs/devices are actually available. Confirm `waveOut*` fallback symbols and static `timeBeginPeriod`/`timeEndPeriod` are linkable from `winmm`; record. Missing `dinput8.dll` is fallback evidence, not a STOP; missing `timeBeginPeriod`/`timeEndPeriod` is a STOP.
- [ ] **Step 7: Probe exact vtable slot counts**
Compile a temporary C probe against the MinGW headers that prints each vtable slot count (`sizeof(Vtbl) / sizeof(void*)`). Expected and pinned: `IDirectSound` 11, `IDirectSoundBuffer` 21, `IDirectInput8A` 11, `IDirectInputDevice8A` 32. Any mismatch is a STOP.
- [ ] **Step 8: Probe module resolution**
Compile a temporary program with `-I <repo>/sf/src` that imports `std_time.zig` and `std_page.zig`; expected rc 0. Record this as the pre-v148 include path for the new `std_ddraw`/`std_dinput`/`std_dsound` modules. If `-I` does not resolve, STOP.
- [ ] **Step 9: Probe hard-gate assets**
Download and verify:
  - `dmg_sound/dmg_sound.gb` from Blargg commit `c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15`, sha256 `c34e740664eb14b42c39750434e3e105fc92d774a98fb671594a48e972401630`, 65,536 bytes.
  - `2048.gb` from `Sanqui/2048-gb` commit `e44f94f898c1e0de7caa1160c82c0da36ff5eb05`, sha256 `3ea2376b15b34bd26b10e6b31d2753bf8b086098dbdb5ee84d9c0f03d66d3d7f`, 32,768 bytes.
  Place both under `/tmp/z9gb_roms` and record the exact source URL and hash. Any hash/size mismatch is a STOP.
- [ ] **Step 10: Baseline P1/P2 tiers**
Run P2 `tier_smoke.sh` and `tier_dmg.sh --all` at P3 base `8a5f7aa7` with `/tmp/z9gb_p2_seed/zig1_5_clean`; expected both PASS. Record output.
- [ ] **Step 11: Record**
Write the matrix, exact Wine version, slot counts, asset hashes, include-path result, and baseline results into the task report. If DDraw import-gate behavior changed, STOP.

---

### Task 1: Add `std_ddraw` raw pixel surface

**Files:**
- Create: `sf/src/std_ddraw.zig`
- Create: `sf/src/std_ddraw_pal.zig`
- Create: `examples/z98/z9gb/tests/run_ddraw_probe.sh`
- Modify: `scripts/win32_cross/check_win9x_imports.sh` (GDI32 whitelist += `GetPixel` for the readback probe)
- Test: `examples/z98/z9gb/tests/tier_win32.sh`

**Interfaces:**
- Consumes: `std_ddraw_pal` Win32 externs/vtables.
- Produces:
  - `pub const DdrawError = error{ OpenFailed, SurfaceFailed, NotSupported };`
  - `pub const DdrawEvent = struct { kind: u8, key: u16, close: bool };`
  - `pub const Ddraw = struct { opaque: *DdrawState };`
  - `pub fn ddrawOpen(title: []const u8, src_w: u32, src_h: u32, scale: u32) DdrawError!*Ddraw;`
  - `pub fn ddrawPresent(d: *Ddraw, pixels: []const u32) bool;`
  - `pub fn ddrawPoll(d: *Ddraw, ev: *DdrawEvent) bool;`
  - `pub fn ddrawSetScale(d: *Ddraw, scale: u32) bool;`
  - `pub fn ddrawWindow(d: *Ddraw) *void;`
  - `pub fn ddrawClose(d: *Ddraw) void;`

- [ ] **Step 1: Write the failing probe**
`run_ddraw_probe.sh` builds a Win32-only probe that opens a 160x144 surface at scale 2, presents a solid color, and dumps the first pixel through `--fb-out`. Expected: fails because the modules do not exist.
- [ ] **Step 2: Implement the COM surface**
Hand-write the `IDirectDraw7` and `IDirectDrawSurface7` vtables with exact slot order from MinGW `ddraw.h`. Dynamically load `ddraw.dll`, resolve `DirectDrawCreate`, QI to `IDirectDraw7`, set `DDSCL_NORMAL`, create a **160x144 32-bit system-memory offscreen** (frequent `Lock` writes; system memory is the right choice for the source) plus a clipper. Create a 640x576 staging offscreen lazily only if the software-scale fallback is needed.
- [ ] **Step 3: Implement `Lock`/`Unlock` presentation**
`ddrawPresent` locks the 160x144 offscreen with `DDLOCK_WAIT`, copies the 92,160 bytes row by row honoring destination pitch, unlocks, then does a single **hardware stretch `Blt`** from source `0,0,160,144` to the primary at the window's client rect (`scale` = 1..4). If the stretch `Blt` returns a failure indicating unsupported/failed stretch, fall back once to **software nearest-neighbour scaling into the 640x576 staging offscreen** (4-byte writes per source pixel block) followed by a 1:1 `Blt`. `DDERR_SURFACELOST` calls `Restore` and retries once. Never per-pixel `Lock`/`Unlock`; never software-scale the primary by default.
- [ ] **Step 4: Implement window and scale**
Window client is `160*scale x 144*scale`; `ddrawSetScale` resizes the window and rebuilds the clipper; the 160x144 source offscreen is size-independent (the 640x576 staging surface is created only for the software-scale fallback). Scale outside 1..4 returns false.
- [ ] **Step 5: Add the Win32 tier**
`tier_win32.sh` builds `-osw`, runs `check_win9x_imports.sh <exe> 9x`, and runs the probe under Wine with `--scale 2 --frames 1`. The probe must read back the presented window pixels (GDI `GetDC`/`GetPixel`) and assert the known color at scale 2 and after `ddrawSetScale(4)`; `GetPixel` is added to the GDI32 whitelist in this task's commit. Expected: import gate PASS; probe exits 0; readback assertion passes.
- [ ] **Step 6: Commit**
```bash
git add sf/src/std_ddraw.zig sf/src/std_ddraw_pal.zig scripts/win32_cross/check_win9x_imports.sh examples/z98/z9gb/tests/run_ddraw_probe.sh examples/z98/z9gb/tests/tier_win32.sh
git commit -m "feat(std): add DirectDraw pixel surface"
```

---

### Task 2: Add `std_dinput` keyboard and gamepad

**Files:**
- Create: `sf/src/std_dinput.zig`
- Create: `sf/src/std_dinput_pal.zig`
- Create: `examples/z98/z9gb/tests/run_dinput_probe.sh`
- Test: `examples/z98/z9gb/tests/tier_win32.sh`

**Interfaces:**
- Consumes: opaque window handle from `std_ddraw.ddrawWindow`.
- Produces:
  - `pub const DinputError = error{ OpenFailed, NotSupported };`
  - `pub const Buttons = struct { right: bool, left: bool, up: bool, down: bool, a: bool, b: bool, select: bool, start: bool, quit: bool };`
  - `pub const Dinput = struct { opaque: *DinputState };`
  - `pub fn dinputOpen(window: *void) DinputError!*Dinput;`
  - `pub fn dinputPoll(d: *Dinput, out: *Buttons) void;`
  - `pub fn dinputClose(d: *Dinput) void;`
  - `pub fn dinputMapKeys(keys: []const u8, out: *Buttons) void;` (test seam: maps a synthetic 256-byte key array; no Win32 types)
  - `pub fn dinputBackendKind(d: *const Dinput) u8;` (1 = DInput8, 2 = `GetAsyncKeyState` fallback)

- [ ] **Step 1: Write the failing probe**
"Simulated `DIK_LEFT`" is defined as a deterministic unit test, not a synthetic input injection: `run_dinput_probe.sh` builds a tiny test binary that feeds a synthetic 256-byte `GetDeviceState` key array (byte `DIK_LEFT` set) and a zero array through the keymap function and prints `keyboard=0` / `keyboard=1`; the Wine smoke only asserts the `dinput=ok` or `dinput=fallback` backend line. Expected: fails because the modules do not exist.
- [ ] **Step 2: Implement DInput8 keyboard**
Dynamically load `dinput8.dll`, resolve `DirectInput8Create`, create `IID_IDirectInput8A`, create the keyboard with `GUID_SysKeyboard`, `SetDataFormat(c_dfDIKeyboard)`, set foreground/non-exclusive, `Acquire`. Poll `GetDeviceState(256)`. Vtables follow the Global Constraints slot-order rule (`IDirectInput8A` 11 / `IDirectInputDevice8A` 32 slots copied verbatim from MinGW `dinput.h`, unused slots kept as typed placeholders).
- [ ] **Step 3: Implement gamepad**
Enumerate `DI8DEVCLASS_GAMECTRL`; select the first attached device; set `c_dfDIJoystick`; `SetCooperativeLevel(DISCL_BACKGROUND | DISCL_NONEXCLUSIVE)`; `Acquire`. `dinputPoll` calls `Poll()` on the joystick device before `GetDeviceState` (required for buffered devices; keyboard needs no `Poll`), and on `DIERR_INPUTLOST`/`DIERR_NOTACQUIRED` re-`Acquire`s once and treats that frame as neutral. Map axes to D-pad with a dead zone of 25%; buttons 0=A, 1=B, 8=Select, 9=Start, Escape/quit from keyboard. The keyboard device uses `DISCL_FOREGROUND | DISCL_NONEXCLUSIVE` and also re-`Acquire`s on focus loss.
- [ ] **Step 4: Implement keyboard fallback**
If `dinput8.dll` or `DirectInput8Create` fails, use `GetAsyncKeyState` for arrows, Z, X, Enter, Backspace, and Escape. Gamepad is unavailable; `Dinput` still opens. `GetAsyncKeyState` is a static USER32 import and is **not** currently in the USER32 whitelist (`scripts/win32_cross/check_win9x_imports.sh:35`): add exactly `GetAsyncKeyState` to that list in this task's commit (USER32 is already an allowed DLL; only the symbol list grows). Note the commit message includes the gate change.
- [ ] **Step 5: Run the tier**
Expected: import gate PASS; Wine probe prints `dinput=ok` or `dinput=fallback`; no static `DINPUT8.DLL`.
- [ ] **Step 6: Commit**
```bash
git add sf/src/std_dinput.zig sf/src/std_dinput_pal.zig scripts/win32_cross/check_win9x_imports.sh examples/z98/z9gb/tests/run_dinput_probe.sh examples/z98/z9gb/tests/tier_win32.sh
git commit -m "feat(std): add DirectInput8 keyboard and gamepad"
```

---

### Task 3: Add `std_dsound` with waveOut fallback

**Files:**
- Create: `sf/src/std_dsound.zig`
- Create: `sf/src/std_dsound_pal.zig`
- Create: `examples/z98/z9gb/tests/run_dsound_probe.sh`
- Test: `examples/z98/z9gb/tests/tier_win32.sh`

**Interfaces:**
- Consumes: opaque window handle.
- Produces:
  - `pub const DsoundError = error{ OpenFailed, BufferFailed, Lost };`
  - `pub const Dsound = struct { opaque: *DsoundState };`
  - `pub fn dsoundOpen(window: *void, sample_rate: u32, channels: u16) DsoundError!*Dsound;`
  - `pub fn dsoundWrite(d: *Dsound, samples: []const i16) usize;`
  - `pub fn dsoundQueued(d: *const Dsound) usize;`
  - `pub fn dsoundBackendKind(d: *const Dsound) u8;`
  - `pub fn dsoundClose(d: *Dsound) void;`

- [ ] **Step 1: Write the failing probe**
Probe opens 44,100 Hz stereo, writes 2,048 stereo frames (4,096 i16 zeros), prints `backend=<1|2> queued=<n>`, and closes. Expected: fails on missing modules.
- [ ] **Step 2: Implement DirectSound**
Dynamic `dsound.dll` -> `DirectSoundCreate` -> `SetCooperativeLevel(DSSCL_PRIORITY)` -> create a **2,048-stereo-frame** (4,096 i16 samples, 8,192 B, **46.4 ms** at 44.1 kHz — matches the spec) 16-bit buffer, zeroed (silence) at open, with `DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_GLOBALFOCUS` -> **prefill one full buffer of silence/samples** -> `Play(0,0,DSBPLAY_LOOPING)` (prefill prevents the initial underrun; `timeBeginPeriod(1)` + the QPC spin tail bound mid-run stalls). Vtables follow the Global Constraints slot-order rule (`IDirectSound` 11 / `IDirectSoundBuffer` 21 slots copied verbatim from MinGW `dsound.h`, unused slots kept as typed placeholders). Power-of-two size so ring arithmetic uses masks.
- [ ] **Step 3: Implement nonblocking write**
`GetCurrentPosition` gives play cursor. Maintain masked `write_cursor`; compute free frames from play vs write cursor; `Lock` only the free region as at most **two wrapped spans**, copy, `Unlock`. Never clear or refill the whole buffer per frame; fill only free frames. On underrun, write silence for the gap rather than blocking or rewinding the ring. `dsoundWrite` returns i16 elements consumed; it never sleeps.
- [ ] **Step 4: Implement waveOut fallback**
If DirectSound creation/buffer creation fails, use `waveOutOpen` with **two 2,048-stereo-frame buffers** (~46 ms each), `waveOutPrepareHeader`/`waveOutWrite`, and `WHDR_DONE` polling (proven z9play pattern); silence-fill an unready buffer instead of blocking. `dsoundBackendKind` returns 2.
- [ ] **Step 5: Run the tier**
Expected: import gate PASS; Wine probe runs; if DirectSound is absent, `backend=2` and no failure.
- [ ] **Step 6: Commit**
```bash
git add sf/src/std_dsound.zig sf/src/std_dsound_pal.zig examples/z98/z9gb/tests/run_dsound_probe.sh examples/z98/z9gb/tests/tier_win32.sh
git commit -m "feat(std): add DirectSound with waveOut fallback"
```

---

### Task 4: APU and audio ring

**Files:**
- Create: `examples/z98/z9gb/apu.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/mmu.zig` (route `FF10-FF3F` to `apuRead`/`apuWrite`)
- Create: `examples/z98/z9gb/tests/apu_test.zig`
- Create: `examples/z98/z9gb/tests/tier_audio.sh`
- Test: `examples/z98/z9gb/tests/tier_audio.sh`

**Interfaces:**
- Consumes: `Bus` I/O, CPU cycle counter.
- Produces:
  - `pub fn apuReset(a: *Apu, sample_rate: u32) void;`
  - `pub fn apuTick(a: *Apu, cycles: u32) void;`
  - `pub fn apuRead(a: *Apu, addr: u16) u8;`
  - `pub fn apuWrite(a: *Apu, addr: u16, value: u8) void;`
  - `pub fn apuSamples(a: *Apu, out: []i16) usize;`
  - `pub fn emuAudioSamples(e: *Emu, out: []i16) usize;` (spec §8.2 facade — **produced here**, this task wires `emu.zig` to drain `apuSamples`; P5 consumes it)
  - static ring capacity `32768` i16 (16,384 stereo frames).

- [ ] **Step 1: Write the failing unit test**
Tests: channel 1 square duty/frequency; channel 2; wave RAM; noise LFSR (width-7 feedback into bit 6); NR52 power (off read values, length counters); frame sequencer length/envelope/sweep (shadow-register sweep + negate-after-enable disable quirk); wave-RAM read-during-playback garbage; NRxx read masks; length-counter extra clock on NRx4 write; mixer DC-free output; `apuSamples` drains exactly the produced count. Expected: fails on missing `apu.zig`.
- [ ] **Step 2: Implement channels**
Two square channels with duty, frequency, length, envelope, sweep; wave channel with 32 4-bit samples; noise channel with 15/7-bit LFSR. **Algorithm:** each channel keeps its own period/frequency divider decremented by elapsed T-cycles (subtract-and-compare, not a per-T-cycle loop); the frame sequencer runs at 512 Hz from a cycle accumulator. Length/envelope/sweep are updated on frame-sequencer steps. Wire `mmu.zig`'s `FF10-FF3F` window to `apuRead`/`apuWrite` (NR10-NR52 + wave RAM `FF30-FF3F`). **Hardware quirk checklist (pinned; `dmg_sound` sub-tests gate these):**
  1. sweep uses a **shadow frequency register**; retriggering with negate-after-enable (sweep enabled + negate then re-enabled) **disables channel 1** on DMG;
  2. noise LFSR width-7 mode feeds back into **bit 6** (not bit 7);
  3. **wave-RAM reads during playback return garbage** on DMG (emulate the documented on-chip fetch corruption, not plain wave RAM);
  4. **NRxx read masks** (unused bits read as 1/0 per register) and **NR52 power-off read values** (length counters readable while APU is off, other regs masked/zero);
  5. **length-counter extra clock** on NRx4 writes while the frame sequencer edge coincides.
- [ ] **Step 3: Implement the mixer**
Generate samples with a **16.16 fixed-point 44,100 Hz accumulator** (`cycles_per_sample ≈ 95.1`): accumulate emulated cycles, emit one stereo sample per crossing. Mix enabled channels through small LUTs — **duty LUT `[4][8]`**, volume/envelope LUT `[16][4]`, wave nibble LUT — and an integer one-pole DC blocker. No floating point, no per-T-cycle sample mixing, no host time.
- [ ] **Step 4: Implement the ring**
`apuSamples` copies up to `out.len` from a static **power-of-two ring (32,768 i16 / 16,384 stereo frames)** using masked head/tail indices; overflow drops oldest samples. No allocation, no per-sample modulo.
- [ ] **Step 5: Run the test**
Expected: PASS under `-ffast` and `-fsafe`; no trap on shift/mix.
- [ ] **Step 6: Add `dmg_sound` gate**
`tier_audio.sh --gate` uses the pinned Blargg `dmg_sound` memory protocol (the ROM writes no serial bytes). Run `--turbo --frames 200000`; poll `0xA000` status and `0xA004` text after magic `0xDE,0xB0,0x61` at `0xA001..0xA003`. PASS requires status 0, terminal `Passed`, and no `Failed`; reaching the frame cap without a verdict is FAIL (timeout). Missing ROM = `SKIP` (exit 77) and cannot close the milestone.
- [ ] **Step 7: Commit**
```bash
git add examples/z98/z9gb/apu.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/mmu.zig examples/z98/z9gb/tests/apu_test.zig examples/z98/z9gb/tests/tier_audio.sh
git commit -m "feat(z9gb): add DMG APU and audio ring"
```

---

### Task 5: Win32 platform and frame loop

**Files:**
- Create: `examples/z98/z9gb/platform/win32.zig`
- Modify: `examples/z98/z9gb/main.zig`
- Modify: `examples/z98/z9gb/emu.zig`
- Modify: `examples/z98/z9gb/tests/tier_win32.sh`
- Modify: `scripts/win32_cross/check_win9x_imports.sh` (WINMM whitelist += `timeBeginPeriod` `timeEndPeriod`)
- Test: `examples/z98/z9gb/tests/tier_win32.sh`

**Interfaces:**
- Consumes: `std_ddraw`, `std_dinput`, `std_dsound`, P1 `Platform`.
- Produces:
  - `pub fn platformWin32() *Platform;`
  - CLI `--windowed`, `--scale N`, `--audio`, `--no-audio`, `--turbo`.
  - QPC frame deadline: `period_ticks = highResFreq() * 70224 / 4194304`.

- [ ] **Step 1: Write the failing smoke**
`tier_win32.sh --smoke` builds `-osw`, runs under Wine for 120 frames, and requires exit 0 and a non-empty framebuffer log. Expected: fails because `platformWin32` does not exist.
- [ ] **Step 2: Implement the backend**
Open DDraw 160x144 at the requested scale; open DInput with the DDraw window; open DSound at 44,100 stereo. `present_fn` calls `ddrawPresent`. `poll_fn` maps buttons and quit. `audio_fn` calls `dsoundWrite`. `close_fn` closes all three.
- [ ] **Step 3: Implement frame pacing**
Run one frame (70,224 T-cycles); present; drain APU samples to the audio backend; poll input; compute the next QPC deadline. Win9x `Sleep(1)` quantizes to the ~55 ms system tick and will burst frames; call `timeBeginPeriod(1)` at open and `timeEndPeriod(1)` at close (WINMM whitelist grows by exactly these two symbols in this task's commit — `scripts/win32_cross/check_win9x_imports.sh:28` currently lists only `waveOut*`). `timeBeginPeriod`/`timeEndPeriod` are pinned as static WINMM imports; Win9x provides them in `winmm.dll`; no dynamic `GetProcAddress` fallback. If `timeBeginPeriod` returns failure, ignore it and use the bounded spin tail alone. Then `sleepMs` while ahead by more than 2 ms and finish the last ≤2 ms with a bounded QPC spin. No unbounded busy-spin; no late-frame accumulation (drop the deadline to now). In `--turbo`, skip sleeping.
- [ ] **Step 4: Implement window/audio flags**
`--scale` accepts 1..4. `--no-audio` skips APU output. `--audio` is default on Win32. Missing DDraw/DInput/DSound is a hard open failure for `--windowed`, except DInput keyboard fallback.
- [ ] **Step 5: Verify**
Run Wine smoke for 120 frames; check `rss_kb`; check the framebuffer matches headless for the same ROM/frame. Expected: PASS; no import of `DSOUND.DLL`/`DINPUT8.DLL`.
- [ ] **Step 6: Commit**
```bash
git add examples/z98/z9gb/platform/win32.zig examples/z98/z9gb/main.zig examples/z98/z9gb/emu.zig examples/z98/z9gb/tests/tier_win32.sh scripts/win32_cross/check_win9x_imports.sh
git commit -m "feat(z9gb): add Win32 display/input/audio backend"
```

---

### Task 6: Playable gates and performance evidence

**Files:**
- Modify: `examples/z98/z9gb/tests/tier_audio.sh`
- Modify: `examples/z98/z9gb/tests/tier_win32.sh`
- Create: `examples/z98/z9gb/tests/tier_perf.sh`
- Modify: `examples/z98/z9gb/testdata/roms/manifest.sha256` (add `dmg_sound/dmg_sound.gb` from Blargg `c240dd7d700e5c0b00a7bbba52b53e4ee67b5f15`, sha256 `c34e740664eb14b42c39750434e3e105fc92d774a98fb671594a48e972401630`; add `2048.gb` from `Sanqui/2048-gb` commit `e44f94f898c1e0de7caa1160c82c0da36ff5eb05`, sha256 `3ea2376b15b34bd26b10e6b31d2753bf8b086098dbdb5ee84d9c0f03d66d3d7f`, 32768 bytes)
- Modify: `examples/z98/z9gb/README.md`
- Test: `examples/z98/z9gb/tests/tier_audio.sh`, `tier_win32.sh`, `tier_perf.sh`

**Interfaces:**
- Consumes: P3 backend and APU.
- Produces: gate and performance evidence.

- [ ] **Step 1: Run `dmg_sound`**
`tier_audio.sh --gate` requires `dmg_sound.gb` and the memory-protocol verdict from Task 4 Step 6 (magic `0xDE,0xB0,0x61` at `0xA001..0xA003`, status 0 at `0xA000`, terminal `Passed` at `0xA004`, no `Failed`). Expected: PASS; missing ROM = SKIP, and closeout cannot claim the audio gate.
- [ ] **Step 2: Run homebrew (named ROM: 2048-gb)**
The homebrew gate ROM is **`2048.gb`** built from `Sanqui/2048-gb` (commit pinned in `testdata/roms/manifest.sha256`; zlib license; the canonical emulator-bring-up homebrew — user-supplied bytes, never committed). Run `--windowed --frames 600` under Wine **and** `--headless --frames 600` on the host. Metric: the GB frame clock is 59.7275 Hz (not 60); the gate is **sustained ≥ 59.0 rendered fps** (frames/wall over the 600-frame window) with audio on, measured by QPC. Record measured fps, CPU, RSS; label host vs Wine numbers separately and never label Wine numbers as Win98. Missing ROM = SKIP; closeout cannot claim the performance gate.
- [ ] **Step 3: Add `tier_perf.sh`**
Measure `--headless --frames 600` wall, CPU, and RSS with `/usr/bin/time`; measure `--windowed` frames. Report measured numbers only; label estimates as estimates.
- [ ] **Step 4: Update docs**
README: P3 status, the **DX6+/DX8 runtime requirement** (`IDirectDraw7` needs the DX6+ runtime; `dinput8.dll` for gamepad needs the DX8 runtime; keyboard fallback works without it), audio fallback, scale flags, gate commands, real-hardware caveat.
- [ ] **Step 5: Commit**
```bash
git add examples/z98/z9gb/tests/tier_audio.sh examples/z98/z9gb/tests/tier_win32.sh examples/z98/z9gb/tests/tier_perf.sh examples/z98/z9gb/testdata/roms/manifest.sha256 examples/z98/z9gb/README.md
git commit -m "test(z9gb): add playable DMG and performance gates"
```

---

### Task 7: Seed v148 and P3 closeout

**Files:**
- Modify: `scripts/seed/build_from_seed.sh`
- Modify: `scripts/seed/archive_seed.sh`
- Modify: `STD_README.MD`
- Modify: `docs/sf/QUICK_REF.md`
- Modify: `README.md`
- Modify: `release/seed/CHANGELOG.md`
- Replace: `release/seed/zig1-seed.tgz`, `release/seed/zig1_seed_w9.zip`
- Test: seed two-hop build and P3 tiers

**Interfaces:**
- Consumes: all P3 std modules.
- Produces: seed v148, lib 65, docs truth.

- [ ] **Step 1: Verify std changes are complete**
Run `git diff --name-only <P3-base>..HEAD -- sf/src` and confirm only `std_ddraw*`, `std_dinput*`, `std_dsound*`. No `std.zig` change.
- [ ] **Step 2: Add modules to seed copy lists**
Add six `.zig` files to `build_from_seed.sh` and `archive_seed.sh`: `std_ddraw.zig`, `std_ddraw_pal.zig`, `std_dinput.zig`, `std_dinput_pal.zig`, `std_dsound.zig`, `std_dsound_pal.zig`. Update the count 59 -> 65 in all live strings and the archive README template.
- [ ] **Step 3: Rotate seed v148**
Run `bash scripts/seed/archive_seed.sh`; record archive md5, zip md5, manifest md5, lib count 65, gen counts, fixed point. Run `build_from_seed.sh` two-hop; require `hop1 == hop2`.
- [ ] **Step 4: Verify anchors**
Run `gate_lower_depth.sh`; expect pins unchanged (no barrel change). Run `check_emit_support`; expected 9/9. The compiler fixed point must be unchanged.
- [ ] **Step 5: Update docs**
CHANGELOG v148 records DirectDraw/DirectInput/DirectSound additions, no compiler change, no pin movement. QUICK_REF/README/STD_README counts 65.
- [ ] **Step 6: Run P3 tiers**
Run `tier_audio`, `tier_win32`, `tier_perf`, and `tier_smoke`. Expected: PASS/SKIP truthfully reported.
- [ ] **Step 7: Commit**
```bash
git add scripts/seed/build_from_seed.sh scripts/seed/archive_seed.sh STD_README.MD docs/sf/QUICK_REF.md README.md release/seed/CHANGELOG.md release/seed/zig1-seed.tgz release/seed/zig1_seed_w9.zip
git commit -m "chore(seed): rotate v148 (DirectDraw/DirectInput/DirectSound)"
```
