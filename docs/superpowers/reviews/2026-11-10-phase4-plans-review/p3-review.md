# P3 Plan Review — Playable DMG (M5–M6)

**Reviewer:** independent plan reviewer (opencode, mimo-v2.6-pro)
**Date:** 2026-11-10
**Plan under review:** `docs/superpowers/plans/2026-11-10-phase4-p3-playable-dmg-plan.md` (305 lines)
**Authority:** `docs/superpowers/specs/2026-11-10-phase4-project1-gameboy-design.md`
**Prior reviews read:** `p1-review.md`, `p2-review.md` (P1/P2 amended per those findings)
**Mode:** REVIEW-ONLY. No plan/spec/source edits. This file is the only write target.

## Status Table (filled incrementally)

| # | Dimension | Status | Section |
|---|---|---|---|
| 1 | Objective coverage (M5–M6 → tasks) | DONE | §1 |
| 2 | Interface consistency (P2→P3→P4) | DONE | §2 |
| 3 | Win9x soundness (DX/DLL/COM/whitelist) | DONE | §3 |
| 4 | Achievability under pure Z98 | DONE | §4 |
| 5 | Test evidence quality (arithmetic, gates) | DONE | §5 |
| 6 | Memory model (12 MiB RSS / 1 MiB stack) | DONE | §6 |
| 7 | Dependencies / ordering | DONE | §7 |
| 8 | Plan structure quality | DONE | §8 |
| 9 | Fact table | DONE | §9 |
| 10 | Caveat list | DONE | §10 |

---
## 1. Objective coverage (spec M5–M6 → P3 task mapping)

| Spec requirement | P3 coverage | Verdict |
|---|---|---|
| §2/§8.4 DirectDraw windowed Blt, integer scale 1x/2x/3x/4x, Lock/Unlock pitch | Task 1 | MAPPED |
| §2/§8.4 DirectInput8 keyboard + gamepad, `GetAsyncKeyState` fallback | Task 2 | MAPPED |
| §2/§8.4 DirectSound secondary buffer + waveOut fallback | Task 3 | MAPPED |
| §8.8 4-channel APU, frame sequencer, 44,100 Hz stereo mixer, cycle-driven sample clock | Task 4 | MAPPED |
| §8.8 QPC frame deadline, sleep-only-when-ahead, `--turbo` | Task 5 | MAPPED |
| §8.3 `platformWin32()` wired to P1 `Platform` table | Task 5 | MAPPED |
| §8.11 `tier_win32.sh` cross-build + import gate + Wine smoke | Tasks 1–5 | MAPPED |
| §5.4 hard gate "full Blargg `dmg_sound`" | Tasks 4 Step 6, 6 Step 1 | MAPPED but semantics wrong (below) |
| §5.4 hard gate "homebrew at 60 fps on the host" | Task 6 Step 2 | MAPPED with drift (below) |
| §5.4 "windowed smoke under Wine" | Task 5 Steps 1/5 (120 frames) | MAPPED |
| §5.4 "DirectDraw/Input/Sound import and runtime checks" | `tier_win32.sh` import gate + probes | MAPPED |
| §5.1 dynamic DLL load, no static `dsound`/`dinput8` import | Global Constraints; Tasks 1–3 | MAPPED |
| §8.4 std modules path-imported, "not barrel-exported" | Global Constraints line 25 | MAPPED (convention PROVED, §2) |
| §5.2 "P3 measures windowed+audio" RSS | Task 5 Step 5, Task 6 Step 3 | MAPPED but unbounded (§5) |
| §5.3 "missing ROM is SKIP, never PASS" | Global Constraints line 23; Tasks 4/6 | MAPPED |
| §8.2 `pub fn emuAudioSamples(e: *Emu, out: []i16) usize` | **no task Produces block lists it** | **UNMAPPED** (grep: spec line 242 is its only occurrence across spec + P1–P5) |
| §11 "one seed rotation" for the sf/src additions | Task 7 | MAPPED |
| P3 deliverable "APU/CGB hooks for P4" (§9 table) | APU API is P4's hook (P4 Task 2 modifies `apu.zig`) | MAPPED |

**Hard-gate unambiguity — `dmg_sound`:**
- ROM identity: upstream multi-ROM is `dmg_sound/dmg_sound.gb`, **65,536 bytes** (MBC1), at pinned commit `c240dd7d…` (GitHub contents API, PROVED). The plan (Task 4 Step 6) says bare `dmg_sound.gb` with no manifest path; the manifest convention (`blargg/dmg_sound/dmg_sound.gb`) is never stated. Ambiguous but resolvable.
- **Run semantics: repeats the pre-amendment P2 mistake.** Task 4 Step 6: "`tier_audio.sh` runs `dmg_sound.gb` with `--serial --frames 1200` and requires `Passed`". The amended P2 harness style (p2 plan line 388) is `--serial --turbo --frames 200000` + early exit on the terminal verdict + explicit rule "**reaching the frame cap without a verdict is FAIL (timeout), never PASS**". P3 uses: no `--turbo`, a fixed 1,200-frame cap (≈20.05 emulated s — recomputed §5), no early-exit, and no no-verdict=FAIL rule. The upstream readme (pinned commit) gives no runtime bound ("runs all the tests … many tests need to run for a while") and the multi-ROM reports "all tests passed" or the first failed test number as the result code — exact serial bytes are unpinned (inherits p2-review fact 8). A correct APU can false-FAIL at the cap, or the executor silently raises the number (gate drift). Task 6 Step 1 re-runs the gate with `--gate` and restates **no** run semantics at all.
- Verdict strings: "requires `Passed`" without a pinned per-ROM expected string — same gap p2-review flagged as fact 8; P2's amendment pinned the harness but the plan text here does not inherit it.

**Hard-gate unambiguity — homebrew 60 fps:**
- Task 6 Step 2: "Use a user-supplied homebrew `.gb` **from the manifest**" — but the manifest (spec §5.3) tracks only the five pinned suites (Blargg/Mooneye/SameSuite/2×acid2); **no homebrew ROM is pinned in the spec or any manifest row**. As written the gate names no ROM and no hash → it can permanently `SKIP` with zero closeout pressure (spec §5.3 closeout pressure applies to "external ROMs"; homebrew is never defined as one). Not a real gate until an exact ROM + sha (or an explicit operator-provisioned path convention with closeout-blocking) is pinned.
- "Expected: 60 fps average over 10 seconds" — measurement method (frames/wall? logged where?), and tolerance, are unstated; and the GB frame rate is **59.73 Hz** (4,194,304/70,224), so 600 paced frames take 10.05 s — a naive 60 fps check false-fails (see §5).
- Placement drift: spec §5.4 lists "homebrew at 60 fps **on the host**" and "windowed smoke under Wine" as separate gates; Task 6 Step 2 runs the homebrew `--windowed` **under Wine**, merging them. Defensible (Wine is the only windowed path on the dev host; §5.1 Linux is headless-only) but the mapping should be stated.

**Verdict:** all M5–M6 feature work is mapped; three spec items are weak or unmapped: the `emuAudioSamples` facade, the `dmg_sound` run semantics (repeats the fixed-budget anti-pattern), and the homebrew gate (unnamed ROM, undefined metric).

---
## 2. Interface consistency (P2→P3→P4, repo conventions)

**P3 consumes exactly what amended P2/P1 produce (PROVED):**
- Emu facade: P1 was amended to spec §8.2 exact signatures incl. `emuSetButtons`/`emuTakeSerial`/`emuLoadRom`/`emuReset` (p1 plan:118–133), `EmuConfig` now `{cgb, serial_log, turbo, dynarec}` and `EmuError` now includes `CgbRequired` (p1 plan:119–120) — both p1-review drift findings fixed. P3 Task 5 "poll_fn maps buttons" against `emuSetButtons` bit order — consistent.
- Pixel format: P2 `emuFramebuffer` `[]const u32`, 160×144, `0x00RRGGBB` (p2 plan:301; spec §8.2) == P3 `present_fn(*void, []const u32)` and `ddrawPresent(pixels: []const u32)` (spec §8.4 verbatim). Consistent.
- APU sample API: P3 **creates** it (`apuSamples`, static ring 32,768 i16). The spec facade wrapper `emuAudioSamples` (spec §8.2) is produced by **no** plan — Task 4/5 modify `emu.zig` but no Produces block declares it; P5 parity compares "APU sample count" (p5:236) and will need it. Gap (also §1).
- Bus consumption: P2 `ioRead`/`ioWrite`/`busTick` (p2 plan:210–212) match Task 4's "Consumes: Bus I/O, CPU cycle counter" — but see the `mmu.zig` wiring gap in §7.

**New std modules vs repo conventions (all PROVED unless noted):**
- Naming `std_ddraw`/`std_ddraw_pal`, `std_dinput`/`std_dinput_pal`, `std_dsound`/`std_dsound_pal` matches `std_gfx`/`std_gfx_pal`, `std_file`/`std_file_pal`, `std_time`/`std_time_pal` convention. ✓
- "No `std.zig` barrel change; path-imported" — PROVED as convention: `sf/src/std.zig` is a **17-entry** barrel (io/fmt/arena/…/fold) and does **not** list `std_gfx`, `std_file`, etc.; `examples/z98/gfx_demo/main.zig:16` uses `@import("std_gfx")` (path/search-path import, no `.zig` suffix). Adding nothing to the barrel is consistent; "no emission pins move" matches the seed fixed-point check (Task 7 Step 4 `gate_lower_depth.sh` exists at `scripts/compiler/gate_lower_depth.sh`). ✓
- Opaque handle `pub const Ddraw = struct { opaque: *DdrawState }` matches `std_gfx.zig:77` `pub const Gfx = struct { opaque: *GfxState }`. ✓
- Error sets match spec §8.4 verbatim (`DdrawError{OpenFailed,SurfaceFailed,NotSupported}`, `DinputError{OpenFailed,NotSupported}`, `DsoundError{OpenFailed,BufferFailed,Lost}`). One trivial drift: plan `dsoundQueued(d: *const Dsound)` vs spec §8.4 `dsoundQueued(d: *Dsound)` (const qualifier only; `dsoundBackendKind` already `*const` in the spec). Spec §11 technically requires operator approval even for this; practical risk ≈ 0.
- Public API leaks: only `*void` window handoff (`ddrawWindow`, `dinputOpen(window)`, `dsoundOpen(window)`) — allowed by spec §5.1 ("OS handoff is unavoidable"). No HWND/COM/GUID in public structs. `Buttons` struct matches spec §8.4 incl. `quit: bool`. ✓
- Seed accounting: Task 7 adds exactly 6 files; `scripts/seed/build_from_seed.sh:24` says "59 std .zig" and the copy line 146 lists `std.zig` + 58 `std_*` = 59 → 65 ✓ arithmetic correct; "lib 65" strings update is correctly scoped.

**P3 → P4/P5 (cross-plan):**
- P4 consumes `apu.zig` directly (p4 Task 2 modifies it for double-speed: "APU frame sequencer follows the CGB clock", `apuTick(a, cycles)` takes CPU cycles — divisor change is P4-internal). No P3 API change needed. ✓ No inversion.
- P4/P5 consume the display/input/audio backends unchanged. P5 consumes audio sample count for parity — blocked on `emuAudioSamples` (above).
- Cross-plan flag only: P4's `cgb_sound` gate (`--serial --frames 1800`, p4:198) uses the same fixed-budget, non-turbo, no-verdict-rule pattern this review condemns in P3 Task 4; if P3 adopts the amended harness style, P4 must too.

**Verdict:** interfaces are spec-exact and convention-clean; the real holes are `emuAudioSamples` (unproduced) and the `mmu.zig` APU-I/O wiring file omission (§7).

---
## 3. Win9x soundness (MOST IMPORTANT)

### 3.1 DirectX DLL/interface reality on Win98 (DX5-era)

| Component | Stock Win98 (DX5) | Plan behavior | Verdict |
|---|---|---|---|
| `ddraw.dll` | present (DX5) | dynamic load, `DirectDrawCreate`, **QI `IDirectDraw7`** (Task 1 Step 2) | **IDirectDraw7/IDirectDrawSurface7 are DX6+ interfaces.** On stock DX5, the QI fails → `ddrawOpen` → `OpenFailed` → `--windowed` is a hard failure (Task 5 Step 4). Goal "playable on Win9x" therefore requires a **DX6+ runtime** (DX7/8 was common by 1999–2001, but "stock Win98" is DX5). No `IDirectDraw2`/v1 fallback exists; spec §10 risk register covers the `dinput8` DX8 case (risk 3) but **not** this; Task 6 Step 4 README duty mentions only "dinput8.dll for gamepad". Undocumented runtime requirement; also engages spec anti-goal 2 ("claimed to work on real Win98 hardware without evidence") if not called out. |
| `dsound.dll` | present (DX5) exporting `DirectSoundCreate` (DirectSound v1) | `DirectSoundCreate` + `IDirectSound` v1 vtable + `IDirectSoundBuffer` (Task 3) | **PROVED DX5-compatible** — the plan correctly avoids `DirectSound8Create`/`IDirectSound8` (which *are* DX8-only). Fallback: creation/buffer failure → waveOut ✓ (Task 3 Step 4); a machine without `dsound.dll` degrades to `backend=2`, no failure ✓. |
| `dinput8.dll` | **absent** (DX8+ component) | dynamic load; on failure → `GetAsyncKeyState` keyboard-only fallback; "Dinput still opens" (Task 2 Step 4) | **PROVED correct** per spec §5.1/§10 risk 3. Gamepad unavailability is explicitly stated ✓. No DI1–7 (`dinput.dll`) fallback — acceptable per spec. |
| `timeBeginPeriod` | WINMM | **not used** (verified: absent from plan text; WINMM whitelist is `waveOut*`-only, check_win9x_imports.sh:28) | consistent — but see the pacing consequence in 3.5. |

### 3.2 COM vtable slot-order / ABI (MinGW headers are the source of truth)

- MinGW headers **present** at `/usr/i686-w64-mingw32/include/{ddraw.h,dsound.h,dinput.h}` (2754/1885/2714 lines) — Task 0 Step 1 expectation PROVED.
- Task 1 mandates "exact slot order from MinGW `ddraw.h`" — correct rule. **Tasks 2 and 3 never state the analogous rule** for `dinput.h`/`dsound.h` (gap). Slot orders verified from the MinGW headers and worth pinning in the plan, because two are counter-intuitive:
  - `IDirectSound` = IUnknown + 8 = **11 slots** (dsound.h:575–590): `CreateSoundBuffer, GetCaps, DuplicateSoundBuffer, SetCooperativeLevel, **Compact**, GetSpeakerConfig, SetSpeakerConfig, Initialize` — `Compact` sits *after* `SetCooperativeLevel`, easy to mis-transcribe from older docs.
  - `IDirectSoundBuffer` = IUnknown + 18 = **21 slots** (dsound.h:686–713): `GetCaps, GetCurrentPosition, GetFormat, GetVolume, GetPan, GetFrequency, GetStatus, Initialize, Lock, Play, SetCurrentPosition, SetFormat, SetVolume, SetPan, SetFrequency, Stop, Unlock, Restore`. `Lock` is **7 args** (offset, bytes, ptr1*, bytes1*, ptr2*, bytes2*, flags) and `Unlock` 4.
  - `IDirectInput8A` = IUnknown + 8 = **11 slots** (dinput.h: `CreateDevice, EnumDevices, GetDeviceStatus, RunControlPanel, Initialize, FindDevice, EnumDevicesBySemantics, ConfigureDevices`).
  - `IDirectInputDevice8A` = IUnknown + 29 = **32 slots** (dinput.h:1943–1987); `Poll` is vtable index **25** — and see 3.6: the gamepad path must actually call it.
- The pattern itself is proven in-tree: `sf/src/std_gfx_pal.zig:375–462` hand-writes `IDirectDraw7`/`IDirectDrawSurface7`/`IDDClipper` vtables as structs of `extern "stdcall" fn` pointers with placeholder `fn() void` in unused slots "so the field indices" stay aligned (std_gfx_pal.zig:11–12). Note: its `Lock`/`Unlock` are exactly such placeholders (`fn() void`, :455, :462) — spec §6 confirms std_gfx_pal "has no Lock/Unlock". P3 must type real `Lock`/`Unlock` per `ddraw.h` (7-arg `Lock`, `Unlock(LPRECT)`) — new work, not copy-paste.
- GUIDs are module-local 16-byte values (IID_IDirectDraw7 precedent std_gfx_pal.zig:238–245) — same approach works for `IID_IDirectInput8A`, `GUID_SysKeyboard`, `c_dfDIKeyboard`'s DIDATAFORMAT (note: `c_dfDIKeyboard`/`c_dfDIJoystick` are **data exports** of `dinput8.dll` — `GetProcAddress` returns the data address, or hand-write the DIDATAFORMAT; the plan is silent).

### 3.3 Import whitelist delta — verified

The plan's claim (Task 2 Step 4): `GetAsyncKeyState` is "not currently in the USER32 whitelist (`scripts/win32_cross/check_win9x_imports.sh:35`): add exactly `GetAsyncKeyState`". Verification:
- Line 35 `USER32_ALL` contains `GetKeyState`, **not** `GetAsyncKeyState` — claim PROVED, line ref exact.
- I enumerated every static import P3 can produce: windowing = `std_gfx_pal`'s proven set (RegisterClassA/CreateWindowExA/DefWindowProcA/PeekMessageA/TranslateMessage/DispatchMessageA/ShowWindow/UpdateWindow/GetClientRect/AdjustWindowRect/DestroyWindow/PostQuitMessage/LoadCursorA/GetDC/ReleaseDC/SetWindowPos — all in USER32_ALL:35; `SetWindowPos` covers `ddrawSetScale` resize ✓); KERNEL32 = `LoadLibraryA`/`GetProcAddress`/`FreeLibrary` (dynamic DX), `Sleep`/`GetTickCount`/`QueryPerformanceCounter`/`QueryPerformanceFrequency`, file I/O — all in KERNEL32_9X:26 ✓; WINMM = exactly the six `waveOut*` in WINMM_ALL:28 ✓ (z9play uses precisely these); DDRAW = **no static import** (std_gfx_pal loads `ddraw.dll` dynamically, std_gfx_pal.zig:491–492, 994 — Task 0 Step 3 expectation "DDRAW.DLL not in the static import table" is PROVED consistent).
- **Conclusion: `GetAsyncKeyState` is the only whitelist delta needed** — provided the implementer adds nothing beyond the plan (no `MapVirtualKey`/`SetTimer`/`GetKeyboardState`/`waveOutGetNumDevs`/`SendInput`; none are required by the plan text).

### 3.4 DirectDraw Lock/Unlock/pitch/scaling

- "copies 160x144 pixels honoring pitch" (Task 1 Step 3) — correct; pitch ≥ width×4 on real drivers, row-by-row copy is the right shape. `DDLOCK_WAIT` ✓. `DDERR_SURFACELOST` → `Restore` + one retry ✓ — but *which* surface is restored is unspecified; in practice it is usually the **primary** that is lost (nit).
- Scaling math PROVED (§5): 2x=320×288, 3x=480×432, 4x=640×576; `Blt` source rect `0,0,160,144` → dest `0,0,160*s,144*s` is a driver stretch Blt — spec §10 risk 4 covers unreliable stretch with a 1x path and fail-closed; the plan's `ddrawPresent` returns `bool` but no step defines behavior when `Blt` persistently fails at scale > 1 (nit; spec says "fails closed to `OpenFailed`" — `OpenFailed` is an open-time error, so the mapping of a present-time stretch failure to UX is undefined).
- Offscreen: Task 1 Step 2 fixes a **640×576** offscreen while the written source is only 160×144 (Blt source rect is 160×144) — 1.4 MiB reserved where 92 KB suffices (spec §5.2 says "640x576 **maximum**", so this is legal but pessimistic on a 12 MiB budget / 32 MB machine). Task 1 Step 4 "ddrawSetScale resizes and recreates **only the offscreen if needed**" is contradictory: with a fixed 640×576 offscreen nothing ever needs recreation; with a scaled offscreen the Blt source rect changes too. Ambiguous (Minor).

### 3.5 QPC pacing on Win9x — real-hardware defect

- `period_ticks = highResFreq() * 70224 / 4194304` (Task 5) is correct structure; QPC exists on Win9x (8254-backed) and `std_time.highRes/highResFreq` is the proven wrapper (`sf/src/std_time.zig:72`, with the QPC/QPF coherence fix documented at :30–33). Recomputed: at 1,193,182 Hz the integer period is 19,977 ticks = 16.7420 ms vs a true 16.7427 ms — truncation drift ≈ 0.7 µs/frame (≈ 2.7 ms/min, sub-frame; harmless if deadlines are `start + n*period`, which the plan should say).
- **The sleep is the problem.** `sleepMs(1)` → `@sleepMs` → Win32 `Sleep` (std_time.zig:124–127). On Win9x, `Sleep` granularity is the system tick (~55 ms) unless `timeBeginPeriod(1)` lowers the multimedia timer — and `timeBeginPeriod` is deliberately absent (3.1). Result on real Win98: "sleep while ahead by more than 1 ms" oversleeps up to ~55 ms per call → frames execute in clumps of 3–4 at ~18–55 ms jitter. Under Wine, `Sleep(1)` ≈ 1 ms → **every tier gate stays green while the real machine is jerky**. The plan's "never busy-spin" is stricter than spec §8.8 ("no busy-spin **when idle**"), which leaves room for the standard fix (bounded spin for the final ≤ 2 ms before the deadline). Operator decision required: whitelist `timeBeginPeriod`/`timeEndPeriod` (WINMM delta), allow a bounded deadline spin, or accept and document degraded pacing.
- "no late-frame accumulation" (Review Focus 5) — no step defines deadline resync when the emulator falls behind (e.g., reset deadline to now after a >1-frame stall). Unspecified.

### 3.6 DirectInput specifics

- **Gamepad `Poll()` missing.** For polled devices (all gamepads), `IDirectInputDevice8::Poll` (vtable index 25) must be called before `GetDeviceState` or state is stale. Task 2 Step 3 ("acquire. Map axes…") never calls `Poll` — likely broken gamepad on real hardware; Wine may paper over it.
- **Focus loss/reacquire missing.** Review Focus 2 demands "focus loss/reacquire" but no step handles `DIERR_NOTACQUIRED` → re-`Acquire` (via the pump's WM_ACTIVATE). After alt-tab, input silently dies.
- Keyboard `GetDeviceState(256)` with `c_dfDIKeyboard` ✓ correct shape; foreground/non-exclusive ✓.
- Fallback `GetAsyncKeyState` for arrows/Z/X/Enter/Backspace/Escape ✓ spec §8.4 default map matches.

### 3.7 DirectSound specifics

- Buffer math PROVED (§5): 2,048 stereo frames = 8,192 B ≈ 46 ms at 44.1 kHz; `DSBCAPS_GETCURRENTPOSITION2 | DSBCAPS_GLOBALFOCUS`, looping `Play`, nonblocking `GetCurrentPosition` refill — single-threaded, no callback thread ✓ (spec §7 option 5; **no single-threaded assumption is violated** — no DirectSound notifications/events, waveOut uses `WHDR_DONE` polling on the same thread, z9play precedent).
- `SetCooperativeLevel` **level is never specified** (Task 3 Step 2). `DSSCL_NORMAL` is the natural choice for a secondary-only buffer; pin it (nit).
- waveOut fallback vs z9play's proven pattern (`examples/z98/z9play/platform/audio_win9x.zig`): z9play uses **two 500 ms** buffers and **blocks** (polls `WHDR_DONE`, sleeps 1 ms) when all are queued (audio_win9x.zig:10–16, 125–132); its `*_pal` file (audio_win9x_pal.zig:20–36) is the exact six-extern stdcall pattern to copy. P3's fallback uses two **1,024-frame (~23 ms)** buffers and must honor `dsoundWrite`'s "never sleeps / may consume fewer samples" contract — i.e., an **adaptation**, not a copy: on full buffers it must short-consume/drop (spec §8.8 "If audio falls behind, drop samples"). The plan says "with the same API" but never spells out the nonblocking waveOut semantics; with 2×23 ms buffers and once-per-frame (16.7 ms) polling, glitch margin on a slow frame is thin. Flag as Important-lite.

### 3.8 32-bit / 32 MB

- See §6 for the RSS composition. On a 32 MB machine the 640×576 offscreen may live in driver memory *or* system memory (DDraw sys-mem fallback on old cards) — if system memory it counts against the process. Spec §5.2 already says the 12 MiB target may be revised with data; P3's measurement is the decision point.

**Verdict for §3:** dynamic-load + fallback architecture is sound and gate-compatible with exactly one whitelist delta (`GetAsyncKeyState`, PROVED); `DirectSoundCreate` is correctly DX5-era. Three real Win9x defects remain: **IDirectDraw7 is DX6+ (undocumented)**, **Sleep-based pacing collapses without `timeBeginPeriod`**, and **DInput gamepad `Poll()`/reacquire are missing**.

---
## 4. Achievability under pure Z98

- **COM vtable structs with `extern "stdcall"` fn pointers** — PROVEN in-tree: `sf/src/std_gfx_pal.zig:375–462` (vtable structs), :493 (`DirectDrawCreateFn` stdcall fn-pointer type), :495–497 (`LoadLibraryA`/`GetProcAddress`/`FreeLibrary` externs); language rules: calling convention is carried in the fn-pointer type and matched at calls (`docs/reference/Language_Spec_Z98.md:575`, :370 for stdcall definitions), manual vtable precedent `Language_Spec_Z98.md:486` (§6.2). PROVED.
- **No custom WndProc — message pump pattern** — PROVEN and, in fact, **mandated by a language limit**: "Z98 cannot define a stdcall callback", so the class proc is `DefWindowProcA` registered directly via `@ptrCast` (std_gfx_pal.zig:550, 1115–1118) and events are intercepted in the `PeekMessageA` pump before `DispatchMessageA` (:1611–1707). The plan's `ddrawPoll`/`DdrawEvent` fit this shape — but the plan never states the constraint; an implementer who writes a WndProc (the obvious way to catch WM_CLOSE) hits a wall. Should cite the pattern (Important-lite).
- **No mutable union captures / mandatory `switch` else** — P3 uses no tagged unions; `Buttons`/`DdrawEvent` are flat structs ✓. Any switch needs `else` (Global Constraints ✓; language rule `Language_Spec_Z98.md:215`).
- **`-fsafe` idioms** — Task 4 Step 5 correctly requires PASS under both `-ffast` and `-fsafe` "no trap on shift/mix" ✓. The plan does not restate the widen→mask→cast rule (p2-review caveat 4) that the mixer scaling, LFSR shifts, and ring-pointer wrap will need; low volume here but should be pinned the way amended P2 did.
- **Buffer sizes / ring expressibility and stack safety:**
  - APU ring `static ring capacity 32768 i16` = 65,536 B module-scope static ✓ (array-size window `Language_Spec_Z98.md:703`; not stack — Global Constraints line 22 ✓).
  - DS two-region `Lock` is expressible (pointer×2 + DWORD×2 out-params in a struct mirror — same technique as `DdSurfaceDesc2` mirror std_gfx_pal.zig:296–346 and `WAVEHDR` mirror audio_win9x.zig:84 "eight four-byte fields").
  - 8,192 B DS buffer and 2×4,096 B waveOut buffers are driver/extern-owned or static ✓.
  - Per-frame drain (44,100/60 ≈ 735 stereo frames = 1,470 i16 ≈ 2.9 KB): stack-safe either way, but the plan never says where the drain buffer lives (bounded stack local or static — nit).
  - `u64` QPC arithmetic is carrier-clean (`Language_Spec_Z98.md:25`). PROVED.
- Win32 struct mirrors needed beyond proven ones: `WAVEFORMATEX` (trivial), `DIPROPHEADER`/`DIPROPDWORD` (for the 25% dead zone `SetProperty`), `DIDEVCAPS`, `DIDEVICEINSTANCEA`, `DIJOYSTATE` — all plain-struct mirrors, no language obstacle.

**Verdict:** every P3 construct is expressible and precedented; the only sharp edge is the undocumented "no stdcall callbacks" rule forcing the DefWindowProcA pump pattern.

---
## 5. Test evidence quality (recomputed)

**Arithmetic (all recomputed):**
- Scaling outputs: 160×2=**320**, 144×2=**288** (the mandate's 320×288 ✓); 3x = **480×432**; 4x = **640×576** ✓. Client rect `src*scale` matches spec §8.4.
- Offscreen bytes: 640×576×4 = **1,474,560 B** ✓ == spec §5.2 table.
- DS buffer: 2,048 stereo frames × 2 ch × 2 B = **8,192 B** ✓ (plan's parenthetical exact). Duration = 2048/44100 = **46.4 ms**.
- waveOut fallback: two 1,024-stereo-frame buffers = **4,096 B** each, **8,192 B** total, same 46.4 ms aggregate ✓. (Note: z9play's proven config is 2×500 ms — §3.7.)
- APU ring: 32,768 i16 = **65,536 B** = **16,384 stereo frames** ✓ (plan's parenthetical exact) = **371.5 ms** at 44.1 kHz.
- Frame: 456×154 = **70,224 T** ✓; emulated seconds per 600 frames = 600×70224/4194304 = **10.046 s** (p2-review's 10.05 ✓).
- **GB frame rate is 59.7275 Hz**, not 60 (4,194,304/70,224). Task 6 Step 2's "60 fps average over 10 seconds" is loose: a correctly paced run delivers 59.7 fps and takes 10.05 s for 600 frames. Any assertion must accept ≈59.7 (e.g., ≥58 fps or wall ≤ 10.5 s) and define how fps is computed (frames/wall, logged where). Unpinned = unverifiable.
- `period_ticks = highResFreq() × 70224 / 4194304`: at 1,193,182 Hz (Win9x QPC) = 19,977 ticks after truncation (true 19,977.6) = 16.7420 ms vs 16.7427 ms — 0.7 µs/frame drift ≈ 2.7 ms/min; negligible, but deadlines should be `start + n×period` (absolute), not accumulated `+=`.
- **`dmg_sound` budget: `--frames 1200` = 20.05 emulated s.** Asserted, not measured. Upstream `dmg_sound/readme.txt` (pinned commit) gives no runtime bound and warns "many tests need to run for a while"; the multi-ROM runs the whole suite serially. Nothing in the plan derives 1,200 from a reference run. Combined with no turbo / no early-exit / no no-verdict=FAIL rule (§1), this **repeats the p2-review Critical #1 anti-pattern** (`--frames 600` for Blargg CPU gates). The amended P2 answer — `--serial --turbo --frames 200000`, early exit on terminal verdict, cap-without-verdict = FAIL — is the repo's agreed harness and is simply not used here.

**Are the tier gates real?**
- `tier_win32.sh` mechanics are real and precedented: `examples/z98/gfx_demo/tests/tier_gfx.sh` runs `check_win9x_imports.sh 9x` (:38, :135), Wine with isolated `WINEPREFIX`/`WINEARCH=win32`/`WINEDEBUG=-all` + `timeout` + `wineserver -k` cleanup (:40–67), Xvfb shot capture (:239+); `examples/z98/z9play/tests/tier_win9x.sh` is the `-osw` build+gate twin. PROVED.
- Import gate is mechanical (objdump of the PE import table vs whitelist) — cannot be faked without editing the gate script. Strong.
- Wine smoke: 120 frames + framebuffer log (Task 5) — plausible; "framebuffer matches headless for the same ROM/frame" (Task 5 Step 5) is the right cross-check but the comparison method (hash? `cmp`?) is unstated.
- **Silent-SKIP audit:** missing `dmg_sound.gb` → SKIP ✓ stated; missing homebrew → SKIP ✓ stated — but the homebrew ROM is **unnamed** (§1), so this gate can SKIP forever with no closeout pressure → effectively not a gate. Wine/tool absence: gfx_demo's tier SKIPs on missing tools; the plan never states whether P3 closeout blocks on a Wine-less host. `tier_perf.sh` measurements are "measured numbers only; label estimates as estimates" ✓ honest language.
- RSS check "check `rss_kb`" (Task 5 Step 5) has **no bound** — unverifiable; should assert `< 12288` (12 MiB) or explicitly "reported, not gated".
- Verdict-string pinning and manifest hash verification (both p2-review gaps) are not addressed in P3's runners either.

**Verdict:** arithmetic is correct throughout; the `dmg_sound` gate semantics are the single evidence-breaking defect (Critical), and the homebrew 60 fps gate is not yet a real gate (unnamed ROM, undefined metric).

---
## 6. Memory model (12 MiB RSS / 1 MiB stack)

Composition at max ROM (recomputed):
| Item | Bytes |
|---|---:|
| ROM static (8 MiB cap) | 8,388,608 |
| Framebuffer 160×144×4 | 92,160 |
| Headless snapshot (P1) | 92,160 |
| APU ring 32,768 i16 | 65,536 |
| Serial log (P1) | 4,096 |
| Save RAM (MBC up to 128 KiB) | ≤ 131,072 |
| WRAM 8 KiB + VRAM 8 KiB + OAM/HRAM/IO | ~20,000 |
| **Static subtotal** | **≈ 8.72 MiB** |
| DDraw offscreen (spec 1,474,560 max) | 1,474,560 |
| **With system-memory surface** | **≈ 10.1 MiB** + code/stack |

- Against the provisional 12 MiB target this is **tight but plausible**; spec §5.2 already permits revision "with data, not assumed". P3's windowed+audio measurement (spec §5.2: "P3 measures windowed+audio") is correctly placed (Task 5 Step 5, Task 6 Step 3) — but unbounded (§5), and spec §5.2's "report stack, cache, static, and driver surfaces separately" is still unmet (inherited from P1; P3 adds driver surfaces to the list and should report them).
- The 640×576 offscreen while only 160×144 is written wastes **1.38 MiB** of a 12 MiB budget (§3.4) — sizing to `src_w×src_h` is within spec ("640x576 maximum") and materially eases the 32 MB machine story.
- Stack: audio ring/framebuffer/surfaces are static (Global Constraints line 22 ✓); no step introduces a large stack local; the per-frame audio drain (≤ 2.9 KB) is safe wherever it lives. The 1 MiB stack rule is respected **by construction** — still no measurement step (inherited p1-review caveat 7).

**Verdict:** fits the spec table with ~2 MiB headroom before Wine/driver overhead; measurement exists but is ungated and un-decomposed.

---
## 7. Dependencies / ordering

- **Internal order** 0→1→2→3→4→5→6→7 is linear with no inversions. Task 2 correctly consumes `ddrawWindow` from Task 1; Task 5 consumes all of 1–4. Task 4 (APU) is independent of 1–3. ✓
- **P2→P3 contract:** Emu facade (amended, exact), pixel format, `Bus` — all ✓ (§2). **Gap A:** Task 4 wires the APU to "Bus I/O" but P3 Task 4's Files list is `apu.zig`, `emu.zig`, `tests/*` — **`mmu.zig` is absent**. P2's `ioRead`/`ioWrite` route IO and state "Timer/PPU/APU registers are owned by their modules" (p2 plan:222) with **no APU hook defined**; so FF10–FF3F routing can only land by modifying `mmu.zig` (or emu-side dispatch that P2 doesn't provide). As written the task cannot wire its stated interface without an unlisted file edit. **Gap B:** `emuAudioSamples` (spec §8.2) is assigned to no task (§1).
- **P3→P4 contract:** `apuReset/apuTick/apuRead/apuWrite/apuSamples` + unchanged display/input/audio backends. P4's double-speed work (p4:137–141) consumes `apuTick(cycles)` and modifies `apu.zig` — compatible, no inversion. ✓
- **P3→P5:** `platformWin32()` + `EmuConfig.dynarec` + audio sample count parity (p5:207, 236) — the last needs `emuAudioSamples`. Task 0 Step 4's `VirtualAlloc` probe is a clean forward contract for P5. ✓
- **Seed ordering:** Task 7 is correctly last; the claim "P3 seed rotation is the only seed rotation in Phase 4 unless a later plan changes `sf/src`" is **PROVED** — P4/P5 files lists touch `examples/` only (p5 reads `sf/src/std_page.zig`, writes nothing there).

**Verdict:** one file-list inversion (`mmu.zig`), one unassigned facade function; otherwise ordered correctly.

---
## 8. Plan structure quality

Template compliance (Files / Interfaces / TDD failing-step-first / Expected / scoped commit) is strong across all 8 tasks, matching P1/P2 quality. TDD shape is real (each task's Step 1 is a failing probe/test). Commit blocks are scoped and name the whitelist change (Task 2 commit carries `check_win9x_imports.sh` ✓ and says so).

Vague / unverifiable steps (flagged):
1. **Tasks 1–3: probe sources missing from Files.** `run_ddraw_probe.sh` "builds a Win32-only probe" — from which `.zig`? No `tests/*_probe.zig` (or similar) appears in any Files block. Same for `run_dinput_probe.sh`, `run_dsound_probe.sh`.
2. **Task 1 Step 5:** "framebuffer checksum matches the headless source" — the probe draws a solid color; "the headless source" is undefined as an oracle.
3. **Task 2 Step 1:** "a simulated `DIK_LEFT`" — no mechanism exists to inject a DInput key state in the Wine probe (`SendInput` isn't whitelisted; `PostMessage` never reaches `GetDeviceState`/`GetAsyncKeyState`); needs xdotool or an explicit test hook. Unverifiable as written.
4. **Task 3 Step 2:** `SetCooperativeLevel` level unspecified (pin `DSSCL_NORMAL`).
5. **Task 1 Step 4:** "recreates only the offscreen if needed" — condition undefined (and contradicts the fixed 640×576).
6. **Task 5 Step 5:** `rss_kb` checked against no bound; "framebuffer matches headless" comparison method unstated; late-frame deadline resync (Review Focus 5) unspecified.
7. **Task 6 Step 2:** homebrew ROM unnamed; fps metric/tolerance unstated (§5).
8. **Tasks 4 Step 6 / 6 Step 1:** `dmg_sound` run semantics (§1) — the single worst step in the plan.

**Verdict:** structurally excellent; the weak spots are concentrated in the probe definitions and the two playable gates.

---
## 9. Fact table

| # | Claim (plan location) | Verdict | Evidence |
|---|---|---|---|
| 1 | MinGW `ddraw.h`, `dsound.h`, `dinput.h` exist (Task 0 Step 1) | PROVED | `/usr/i686-w64-mingw32/include/` — 2754/1885/2714 lines |
| 2 | `dmg_sound.gb` exists at pinned commit (Task 4 Step 6) | PROVED (path nuance) | `dmg_sound/dmg_sound.gb`, **65,536 B**, MBC1 — GitHub contents API at `c240dd7d…`; plan gives no manifest path |
| 3 | `dmg_sound` multi-ROM semantics (serial `Passed` verdict) | PROVED with unpinned bytes | `dmg_sound/readme.txt` (pinned): runs all tests; reports "all tests passed" or first failed test number; also `$A000` protocol with `$DE $B0 $61` signature; exact serial terminal bytes unpinned (inherits p2-review fact 8) |
| 4 | `--serial --frames 1200` is a sufficient/valid `dmg_sound` harness (Task 4 Step 6) | **DISPROVED as pattern / INCOMPLETE as budget** | 1,200 frames = 20.05 emulated s, asserted not measured; readme gives no bound; amended P2 harness (p2:388) mandates `--turbo --frames 200000` + early-exit + "cap without verdict = FAIL"; P3 omits all three |
| 5 | `GetAsyncKeyState` absent from USER32 whitelist at `check_win9x_imports.sh:35` (Task 2 Step 4) | PROVED | line 35 `USER32_ALL` has `GetKeyState`, not `GetAsyncKeyState` |
| 6 | Adding exactly `GetAsyncKeyState` is the only whitelist delta needed (Task 2 Step 4) | PROVED | full import enumeration (§3.3): SetWindowPos/GetDC/PeekMessageA/… USER32_ALL:35; LoadLibraryA/GetProcAddress/Sleep/QPC/QPF/GetTickCount KERNEL32_9X:26; six `waveOut*` WINMM_ALL:28; no static DDRAW (std_gfx_pal.zig:491–492) — nothing else unlisted |
| 7 | `timeBeginPeriod` not used (implicit) | PROVED | absent from plan; WINMM whitelist `waveOut*`-only (check_win9x_imports.sh:28) — consistent |
| 8 | `sleepMs(1)`-based pacing works on Win9x (Task 5 Step 3, implied) | **DISPROVED** | `@sleepMs`→Win32 `Sleep` (std_time.zig:124–127); Win9x `Sleep` granularity = system tick ≈ 55 ms without `timeBeginPeriod(1)`; Wine ≈ 1 ms hides it |
| 9 | `dinput8.dll` missing → `GetAsyncKeyState` fallback (Task 2 Step 4) | PROVED | plan + spec §5.1/§10 risk 3; `dinput8.dll` is DX8+, absent on stock Win98 (DX5) |
| 10 | DirectSound path works on stock Win98 DX5 (Task 3, implied) | PROVED | `dsound.dll` ships with Win98 (DX5) exporting `DirectSoundCreate`; plan uses DS **v1** (`DirectSoundCreate`, `IDirectSound` 11-slot vtable) — correctly avoids DX8-only `DirectSound8Create` |
| 11 | Windowed display works on stock Win98 (Goal, implied) | **DISPROVED** | `IDirectDraw7`/`IDirectDrawSurface7` are **DX6+** interfaces; stock Win98 = DX5 → QI (Task 1 Step 2) fails → `OpenFailed`; no fallback; README duty (Task 6 Step 4) documents only dinput8 |
| 12 | COM vtable slot orders "exact from MinGW headers" (Task 1; implied for 2–3) | PROVED as rule / INCOMPLETE as coverage | `ddraw.h` named only in Task 1; verified targets: `IDirectSound` 11 slots (`Compact` after `SetCooperativeLevel`, dsound.h:575–590), `IDirectSoundBuffer` 21 slots w/ 7-arg `Lock` (dsound.h:686–713), `IDirectInput8A` 11, `IDirectInputDevice8A` 32 w/ `Poll` at 25 (dinput.h:1943–1987) |
| 13 | Hand-written COM vtables + dynamic `ddraw.dll` load pattern exists (Tech Stack) | PROVED | `sf/src/std_gfx_pal.zig:375–462` vtables; :493 `DirectDrawCreateFn`; :495–497 `LoadLibraryA`/`GetProcAddress`/`FreeLibrary`; exe imports no DDRAW.DLL (:491–492, :994) |
| 14 | Real `Lock`/`Unlock` vtable slots (Task 1 Step 3) | PROVED as new work | std_gfx_pal `Lock`/`Unlock` are placeholder `fn() void` (:455, :462; spec §6 "no Lock/Unlock") — must be typed per `ddraw.h`, not copied |
| 15 | No custom WndProc needed; message pump pattern (implicit) | PROVED | "Z98 cannot define a stdcall callback"; `DefWindowProcA` registered as class proc (std_gfx_pal.zig:550, 1115–1118); events intercepted in `PeekMessageA` pump (:1611–1707) |
| 16 | `sleepMs`/`highRes`/`highResFreq` available (Task 5) | PROVED | `sf/src/std_time.zig:72,124–127`; QPC/QPF coherent-fallback fix documented :30–33 |
| 17 | Scaling outputs 320×288 / 480×432 / 640×576; offscreen 1,474,560 B (Task 1, spec §5.2) | PROVED | recomputed (§5); 640×576×4 = 1,474,560 |
| 18 | DS buffer 2,048 stereo frames = 8,192 B (Task 3) | PROVED | 2048×2×2 = 8,192; 46.4 ms @ 44.1 kHz |
| 19 | APU ring 32,768 i16 = 16,384 stereo frames (Task 4) | PROVED | 65,536 B = 371.5 ms @ 44.1 kHz |
| 20 | `period_ticks = highResFreq()×70224/4194304` (Task 5) | PROVED with truncation note | 1,193,182 Hz → 19,977 ticks = 16.7420 ms vs 16.7427 ms true; use absolute deadlines |
| 21 | "60 fps average over 10 seconds" for 600 frames (Task 6 Step 2) | **DISPROVED as exact** | GB rate = 4,194,304/70,224 = **59.73 Hz**; 600 paced frames = 10.046 s; metric/tolerance undefined |
| 22 | waveOut fallback parity with z9play (Task 3 Step 4) | PARTIAL / **DISPROVED** | z9play: 2×500 ms buffers, blocking `WHDR_DONE` poll (audio_win9x.zig:10–16, 125–132); P3: 2×23 ms buffers, nonblocking short-consume contract — adaptation, not copy; six `waveOut*` externs match audio_win9x_pal.zig:20–36 ✓ |
| 23 | Gamepad mapping path works (Task 2 Step 3) | INCOMPLETE | never calls `IDirectInputDevice8::Poll` (required for polled gamepads; vtable idx 25); no `DIERR_NOTACQUIRED` re-`Acquire` despite Review Focus 2 |
| 24 | `c_dfDIKeyboard`/`c_dfDIJoystick` usable (Task 2 Step 2–3) | INCOMPLETE | data exports of `dinput8.dll` (GetProcAddress returns data address) or hand-written `DIDATAFORMAT`; plan silent |
| 25 | No `std.zig` barrel change; path-imported modules (Global Constraints) | PROVED | `sf/src/std.zig` = 17-entry barrel without `std_gfx` etc.; `gfx_demo/main.zig:16` `@import("std_gfx")` precedent |
| 26 | lib count 59 → 65 (Task 7) | PROVED | `build_from_seed.sh:24` "59 std .zig"; copy line 146 = `std.zig` + 58 `std_*`; +6 = 65 |
| 27 | Public API matches spec §8.4 (Task 1–3 Interfaces) | PROVED modulo const drift | `dsoundQueued(d: *const Dsound)` vs spec `*Dsound` (spec §11 nit); everything else verbatim |
| 28 | P1/P2 amended facade is consumable (Task 5) | PROVED | p1 plan:118–133 exact spec §8.2 sigs incl. `emuSetButtons`; `EmuConfig` 4 fields + `CgbRequired` (p1 plan:119–120) |
| 29 | `emuAudioSamples` produced somewhere (spec §8.2, implied by Task 5 drain) | **DISPROVED** | grep: spec line 242 only occurrence in spec + P1–P5 |
| 30 | Task 4 can wire APU to Bus I/O with its Files list | **DISPROVED** | `mmu.zig` absent from Task 4 Files; P2 `ioRead`/`ioWrite` define no APU hook (p2:222) |
| 31 | P3 is the only Phase 4 seed rotation (Global Constraints) | PROVED | P4/P5 file lists touch `examples/` only (p5 reads `sf/src/std_page.zig`, writes none) |
| 32 | Homebrew ROM "from the manifest" (Task 6 Step 2) | **DISPROVED** | spec §5.3 manifest tracks 5 suites only; no homebrew ROM pinned anywhere |
| 33 | Import gate + Wine tier mechanics real (Tasks 1–6) | PROVED | `gfx_demo/tests/tier_gfx.sh:38,135` import gate; :40–67 Wine prefix/timeout/cleanup; `z9play/tests/tier_win9x.sh` `-osw` twin |
| 34 | Language allows COM vtable structs of `extern "stdcall"` fn pointers (Global Constraints) | PROVED | `Language_Spec_Z98.md:575` (convention carried in fn-pointer type), :370, :486 (§6.2 vtable precedent) |
| 35 | `SetWindowPos` (ddrawSetScale resize) gate-legal | PROVED | `USER32_ALL` line 35 |

---
## 10. Caveat list (Win9x-focused)

1. **`dmg_sound` gate harness repeats the fixed-budget anti-pattern** (Task 4 Step 6): no turbo, fixed 1,200 frames, no early-exit, no "cap without verdict = FAIL" rule. Hard gate false-fails or drifts. Adopt the amended P2 runner verbatim (p2:388) + pin verdict strings.
2. **IDirectDraw7 is DX6+; stock Win98 is DX5.** `--windowed` hard-fails (`OpenFailed`) on stock Win98; the "playable on Win9x" goal silently assumes a DX6+ (practically DX7/8) runtime. Document it (README/Task 6 Step 4) or add an `IDirectDraw2` fallback (scope). Spec anti-goal 2 forbids unqualified Win98 claims.
3. **Win9x `Sleep` granularity ≈ 55 ms without `timeBeginPeriod(1)`** — the sleep-only pacer bursts ~3–4 frames then stalls on real hardware; Wine hides this completely. Decide: WINMM whitelist delta, bounded deadline spin (spec §8.8 "when idle" permits), or documented degraded pacing.
4. **Homebrew 60 fps gate is not a gate yet** — ROM unnamed ("from the manifest" but no homebrew row exists), fps metric/tolerance undefined (real rate 59.73 Hz), and it can permanently SKIP. Pin ROM + sha + measurement.
5. **`mmu.zig` missing from Task 4 Files** (FF10–FF3F → `apuRead`/`apuWrite` wiring) and **`emuAudioSamples` unassigned** (spec §8.2; P5 parity consumes it).
6. **DInput gamepad: no device `Poll()`** (stale state on real pads) and **no focus-loss re-`Acquire`** (input dies after alt-tab); "simulated `DIK_LEFT`" probe has no defined mechanism.
7. **DS/DI vtable transcription risk** — Tasks 2/3 don't mandate "exact slot order from MinGW `dinput.h`/`dsound.h`"; pin the lengths (IDirectSound 11, IDirectSoundBuffer 21, IDirectInput8A 11, IDirectInputDevice8A 32) and note `Compact` sits after `SetCooperativeLevel`.
8. **waveOut fallback deviates from z9play's proven pattern** (2×23 ms nonblocking vs 2×500 ms blocking) — thin glitch margin; spell out short-consume/drop semantics for the fallback path.
9. **640×576 offscreen wastes 1.38 MiB** of the 12 MiB budget (160×144 written); "recreates the offscreen if needed" is contradictory. Size to `src_w×src_h` (spec "maximum" allows).
10. **Probe sources missing from Files** (Tasks 1–3); Task 1 Step 5 oracle ("headless source") undefined; `rss_kb` check unbounded; `Blt`-stretch persistent-failure UX undefined (spec maps it to `OpenFailed`, which is open-time).
11. **`SetCooperativeLevel` level unpinned** (use `DSSCL_NORMAL`); `DDERR_SURFACELOST` restore target (primary vs offscreen) unspecified.
12. **Inherited gaps not re-addressed:** verdict-string pinning, manifest hash verification in runners, stack-use reporting (spec §5.2 "report … separately" still unmet).
13. **`c_dfDIKeyboard` is a data export** — `GetProcAddress` or hand-written `DIDATAFORMAT`; don't assume a function slot.

---
## VERDICT

**NEEDS FIXES**

Architecture, module boundaries, spec-shaped APIs, whitelist discipline, arithmetic, and TDD structure are all solid — the plan is the best-typed of the three so far on the std-module side. But the plan's centerpiece hard gate (`dmg_sound`) repeats the exact fixed-budget mistake the P2 review declared Critical and the P2 amendment fixed, the homebrew 60 fps gate is currently unverifiable (unnamed ROM, undefined metric), and three real-hardware Win9x defects (DDraw7-on-DX5, 55 ms Sleep pacing, DInput Poll/reacquire) would ship green-under-Wine and broken-on-metal.

### Caveats / risks by severity

**Critical:**
1. `dmg_sound` harness (Task 4 Step 6, Task 6 Step 1): `--serial --frames 1200` with no turbo/early-exit/"no verdict = FAIL" rule repeats p2-review Critical #1. Fix: use the amended P2 verdict harness verbatim (`--serial --turbo --frames 200000`, early exit on terminal verdict, cap-without-verdict = FAIL) and pin exact per-ROM verdict strings from a reference run.

**Important:**
2. IDirectDraw7/Surface7 are DX6+ interfaces; stock Win98 (DX5) fails the QI → `--windowed` dead on stock hardware. Document the DX6+ runtime requirement (and keep spec anti-goal 2 honesty) or scope an `IDirectDraw2` fallback.
3. Win9x pacing: `Sleep(1)` ≈ 55 ms granularity without `timeBeginPeriod`; "never busy-spin" blocks the standard bounded-spin fix. Operator decision (whitelist delta / bounded spin / document burst pacing).
4. Homebrew 60 fps gate: pin an exact ROM + sha (manifest has no homebrew row), define fps computation and tolerance (59.73 Hz, not 60), and make closeout block on it — otherwise it SKIPs forever.
5. Task 4 must add `mmu.zig` to Files (FF10–FF3F routing; P2 defines no APU hook) and some task must produce spec §8.2 `emuAudioSamples` (P5 consumes it).
6. DInput: call device `Poll()` for gamepads; handle `DIERR_NOTACQUIRED` → re-`Acquire` on focus return; define or drop the "simulated `DIK_LEFT`" probe.
7. Pin "exact slot order from MinGW `dinput.h`/`dsound.h`" in Tasks 2–3 (lengths: IDirectSound 11, IDirectSoundBuffer 21 with 7-arg `Lock`, IDirectInput8A 11, IDirectInputDevice8A 32 with `Poll` at 25); pin `DSSCL_NORMAL`.

**Minor:**
8. waveOut fallback: state nonblocking short-consume semantics explicitly (z9play pattern is blocking, 2×500 ms); 2×23 ms buffers have thin margin.
9. Size the offscreen to `src_w×src_h` (saves 1.38 MiB of a 12 MiB budget); fix "recreates the offscreen if needed"; define `Blt`-stretch failure UX and `Restore` target.
10. Add probe sources to Files blocks; define the Task 1 Step 5 oracle; bound or un-gate the `rss_kb` check; specify deadline resync for late frames.
11. `dsoundQueued` const drift vs spec §8.4 — trivial, but spec §11 technically needs approval.
12. Inherited: verdict-string pinning + manifest hash verification in runners + stack reporting (spec §5.2 split).

### Top operator decisions

1. **`dmg_sound` harness:** adopt the amended P2 turbo/until-verdict runner verbatim (recommended), or re-derive per-ROM budgets from reference runs?
2. **DX story:** document "requires DX6+ runtime for display, DX8 for gamepad" and accept (recommended, era-authentic — games shipped DX runtimes), or add IDirectDraw2 fallback?
3. **Win9x pacing:** whitelist `timeBeginPeriod`/`timeEndPeriod`, allow a bounded ≤2 ms deadline spin (spec-compatible), or accept and document burst pacing on real hardware?
4. **Homebrew gate ROM:** which exact ROM + sha becomes the pinned 60 fps subject (and does closeout block on it)?
5. **Offscreen sizing:** 160×144 (92 KB, within spec's "maximum") vs the plan's fixed 640×576?

