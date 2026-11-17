# z9gb — known gaps, tested surface, and reproduction notes

Technical companion to `README.md`. Everything here is stated only to the extent
it has been measured or verified; unverified items are marked as such. Status:
2026-11-17, after the commercial-ROM compatibility pass (Tasks 1–8B), the
partial dynarec-boundary study (Task 8), and the real-Win9x dynarec fault
reproduction (see §3.1).

## 1. Scope

- DMG and CGB (including CGB "DMG compatibility" mode). Not GBA, not SGB.
- Pure-Z98 emulator in `examples/z98/z9gb/`; Linux headless backend and Win32
  windowed backend (DirectDraw/DirectInput8/DirectSound with WinMM/waveOut
  fallback).
- The SM83 dynarec exists only on Win32 (`VirtualAlloc` `PAGE_EXECUTE_READWRITE`);
  Linux uses the interpreter and reports `dynarec=disabled reason=unsupported-host`.

## 2. Verified surface

### 2.1 Test ROM gates (all passing)

| Suite | Result | Notes |
|---|---|---|
| Blargg `cpu_instrs`, `instr_timing`, `mem_timing` | PASS | `retrio/gb-test-roms` pinned commit |
| Mooneye 15 ROMs (MBC1, timer, PPU, OAM DMA) | 15/15 PASS | `Gekkio/mooneye-test-suite` pinned commit |
| `dmg-acid2` | PASS, 92,160-byte golden `c831675c9cff3289d505364286cfb5322a6807fa074386851744f28cdeb84083` | golden derived from the official reference PNG, not self-captured |
| Blargg `dmg_sound` | PASS | verdict via the SRAM memory protocol (`$A000`/`$A004`) |
| Blargg `cgb_sound` | PASS | same protocol; includes CGB APU semantics |
| Blargg `interrupt_time` | PASS (CGB) | CGB-only test; DMG does not run it |
| `cgb-acid2` | PASS, 92,160-byte golden `0fba336ce7d7cb4ef76049a4548ff0e7a5147be79fb34bfd266ce7bb71fcf9fd` | official v1.1 reference |
| In-repo tiers | `tier_smoke`, `tier_dmg`, `tier_cgb`, `tier_audio`, `tier_win32`, `tier_dynarec` pass | see the README section "gates" for commands |

A missing external ROM produces a truthful `SKIP` (exit 77); a skipped hard gate
blocks closeout and is never reported as PASS.

### 2.2 Operator-run commercial/logical ROM matrix (Wine, headless)

Frames complete, 92,160-byte framebuffer each mode; coverage is the dynarec's
`tinstr/(tinstr+minstr)` permille:

| ROM (local, not shipped) | sha256 | Flags | Coverage | Reaches |
|---|---|---|---|---|
| Pokemon Crystal | `fdcc3c8c43813cf8731fc037d2a6d191bac75439c34b24ba1c27526e6acdc8a2` | `--cgb` | 317‰ | title screen |
| Pokemon Pinball | `7672001d4710272009df6a41e3cbada65decd56e0eb2f185cb3d59c08d33ea0e` | `--cgb` (and DMG mode) | 973–988‰ | title/menu |
| Kirby's Dream Land | `0f6dba94fae248d419083001c42c02a78be6bd3dff679c895517559e72c98d58` | DMG | 962‰ (matrix 600f), 961‰ (operator run) | title + playable |
| Kirby Tilt 'n' Tumble | `6cf412aeb1ec60da1a401019d95dee1e76f0297154a7f06b55fb1657a71ed44f` | `--cgb` | 743‰ | MBC7 calibration prompt only |

Under Wine, Crystal, Pinball and KDL are playable with the interpreter and with
the dynarec; the dynarec is faster on Pinball and slower on Crystal/KDL (see
§3). On real Win9x the dynarec faults immediately instead (§3.1).

### 2.3 Input path (verified by the operator on real runs)

- DInput8 keyboard raw state is DIK-indexed; capture returned
  Right=0xCD, Left=0xCB, Up=0xC8, Down=0xD0, A=0x2C, B=0x2D, Select=0x0E,
  Start=0x1C, Quit=0x01.
- Default map: arrows = D-pad, `Z` = A, `X` = B, `Enter` = Start,
  `Backspace` = Select, `Esc` = Quit.
- `--mapkeys` writes `z9gb.ini` in the working directory (raw code per logical
  input plus the backend tag); `--printkeys` and `--input-debug` inspect the
  active table. A backend-tag mismatch falls back to defaults with a warning.
- FF00 select polarity is Pan Docs-correct (bit 5 = 0 selects buttons, bit 4 = 0
  selects the D-pad). This was inverted before the compatibility pass and fixed
  by `fix(z9gb): correct key translation`.

## 3. Dynarec: measured reality (not a general-purpose speedup)

The dynarec is mechanically correct on the tested Wine/host surface (all gates
and ROM runs pass); on real Win9x it faults immediately (§3.1). Its cost model
is dominated by per-block overhead, not by translation quality.

Measured on Wine, headless, 600 frames, turbo, medians (Task 4 and Task 8
workspace):

| ROM | Coverage | Interpreter | Dynarec | Verdict |
|---|---:|---:|---:|---|
| `2048.gb` | 12‰ | ~8.26M T-cycles/s | ~8.28M | interpreter-dominated, no gain |
| Crystal | 317‰ | ~9.57M | ~7.96M | dynarec slower |
| Pinball | 973→988‰ | ~10.7M | ~13.1M | dynarec faster |
| KDL (operator) | 961‰ | smooth | lags in enemy-heavy scenes | real slowdown observed |

Operator KDL counters (600 frames, `--dynarec`):
`blocks=1448334 executed=11444908 fallback=1389355 minstr=1389355 rejected=709086 coverage=961‰`,
i.e. about **3.0 guest instructions per dispatch**.

Why the overhead wins at high coverage:

- Every dispatch pays glue, register save/restore, and a frame-loop
  `ppuSyncIn` → `ppuTick(dot_delta)` → `ppuSyncOut` (up to 11 register writes plus
  two reads).
- Every IO/OAM/VRAM helper access additionally pays `syncCtxPpu`: `busTick` +
  `syncPpuIn` (11 `ppuWrite`) + `ppuTick` + `syncPpuOut` (2 `ppuRead`).
  Sprite/VRAM-heavy code (Crystal, KDL enemy scenes) pays this per access.
- Blocks end at branches/calls/returns, EI/DI/RETI, IO writes, ROM writes, all
  indirect stores, CB `(HL)` writes, HALT/STOP, `LD B,B`, and statically-known
  PPU reads. Frequent indirect stores and calls keep blocks at 1–3 instructions.
- 709k rejected translations on KDL are retried rather than negatively cached;
  a block that starts on a PPU-read boundary is rejected and interpreted.

What was tried (Task 8, report-only): removing only the "reject a block starting
at a statically-known PPU read" rule changed almost nothing — 2048 12‰ → 12‰,
Crystal 317‰ → 317‰, Pinball 973‰ → 988‰ (wall 3.21 s → 3.06 s, ~5%) — because
reads still end blocks mid-stream.

Explicitly **not scheduled** (future-work hypotheses, out of scope here):
removing the PPU-read block enders; syncing PPU only for real PPU state; pushing
only dirty PPU registers; distinguishing IO/ROM indirect stores from WRAM/VRAM
stores to lengthen blocks; a negative cache for rejected PC/bank pairs. Each is
an emulator-performance project of its own, not a Z98-spec testing concern.

### 3.1 Win9x dynarec fault (open; reproduced under Wine)

On 2026-11-17 the operator ran the OpenWatcom **nocrt** Win32 build (v150 lib,
the crashing baseline) with `--dynarec` on real Win9x (Pentium 4, Win98). Every
ROM faults immediately, before any console output, with an invalid page fault in
`module <unknown>` at `EIP=011c0004`; `errordynarec.txt` records `EAX=0`,
`EDX=011c010c`, `EBP=00d3bfe8`, and faulting bytes `8b 10 8b 48 04`. The
interpreter (`--no-dynarec`) still runs. The operator reports this as the first
real-Win9x execution of the dynarec; before this run the dynarec was
Wine-proven only.

Reproduced under Wine 8.0 with the operator's binary
`lin_bin/z9gb/z9gb.exe` (1,035,776 B, sha256
`073c8add6e0839bf93b1439085f13566ea5a4a30770577dcc09f56675694d435`,
OpenWatcom nocrt, v150 lib) and the repo's `testdata/synth/minimal.gb` (sha256
`6e110337c4e336d0a4740d987fb3a3020c7a06b441536b575850f66889b04dc6`), fresh
`WINEPREFIX` under `$HOME`:

```
cd /workspace/znineeight/lin_bin/z9gb
WINEPREFIX="$HOME/.wine-z9gb-dyn-3bJ" WINEDEBUG=-all timeout 240 wine ./z9gb.exe \
    --headless --frames 60 --turbo --rom testdata/synth/minimal.gb --dynarec --dynarec-stats </dev/null
```

Result: rc 5, `Unhandled exception: page fault on read access to 0x00000000 in
32-bit code (0x023d0004)`, `EIP:023d0004 EAX:00000000 EBX:00000000
ECX:00000009 EDX:023d00e0 ESI:0107fc34 EDI:00000040 EBP:00d3bfe8`, stack top
`023d0105`; the faulting instruction is `movl 0x0(%eax),%edx` (`8b 10`). The
Win98 dump is **not** identical modulo the cache base (`011c0000` vs
`023d0000`); compare by relative offset. Matching: EIP at `base + 4`, `EAX=0`,
`EBX=0`, `ECX=9`, `EDI=0x40`, `EBP=00d3bfe8`, and faulting bytes `8b 10 8b 48
04`. Differing: Win98 `EDX=011c010c` (`base + 0x10c`) vs Wine `EDX=023d00e0`
(`base + 0xe0`), a 0x2c relative-offset gap, plus `ESI` and stack contents.
`--no-dynarec` with the same command exits rc 0 and prints
`dynarec=disabled reason=not-requested`. The fault is confirmed on the headless
path under Wine and on the operator's Win9x run (whose display mode is not
stated); the windowed path is untested here (DirectDraw will not open under this
Wine/Xvfb).

Observations to test (hypotheses, not a diagnosis): the glue buffer starts at
`glue_off` with the body at `GLUE_BODY_OFF = 9`
(`dynarec/dynarec.zig:27`); the dispatcher calls `d.mem + e.glue_off`
(`dynarec/dynarec.zig:554`), while chained entries jump to
`glue_off + GLUE_BODY_OFF` (`dynarec/dynarec.zig:305`); `GLUE_MAX = 224` and
`EDX = glue_off + 0xe0` in the Wine dump. The fault at `base + 4`, before the
glue body at `glue_off + 9`, suggests execution entered the glue preamble rather
than the body; that is an inference from the offsets, not an instrumented fact.
Whether the two entry conventions pick different bytes, or the generated/cache
state is invalid on Win9x, is unproven.

Next diagnostic steps, with no fix in this task:

- First, A/B the OpenWatcom CRT and nocrt builds of the same source with the
  same ROM, to separate runtime/library effects from code-cache effects.
- Probe the `VirtualAlloc` result (base, size, protection) and the
  `FlushInstructionCache` call on Win9x; log `d.mem`, `glue_off`, and the
  bytes at `glue_off` and `glue_off + 9` at first dispatch.
- Capture `--dynarec-stats` or a pre-dispatch log to confirm whether
  translation, linking, or the first glue call fails; compare the Win98 and
  Wine dumps at the same offsets.
- Keep windowed and DirectDraw out of the comparison until a host can open
  them.

### 3.2 Interpreter cost on P4/Win98

On the same P4/Win98 run the plain interpreter (no `--dynarec`) runs but is
slow and saturates the CPU (~98%), matching the code-bound cost model above;
the same binary is fast on a modern host. The operator also observes z9play at
~49% CPU, likewise code-bound. This is an operator observation, not a benchmark
against §3's Wine medians: it says the interpreter path is viable on Win9x but
host-speed-limited, not that the interpreter is defective.

## 4. Functional gaps and debt

| Area | Gap | Effect / workaround |
|---|---|---|
| Tilt | MBC7 accelerometer is not implemented; X/Y latch reads neutral `0x8000` | Tilt games reach the calibration prompt and cannot progress. Tilt input + gamepad axes are deferred debt. |
| Rumble | MBC5 rumble writes are decoded and RAM-banked with `& 0x07`, but no motor feedback; MBC7 rumble is not implemented | A game with rumble options runs and saves correctly; rumble cues are ignored. No `--rumble` cue exists. |
| Save load | CLI `--save` writes `.sav`/`.rtc` but never auto-loads them; `emuLoadBattery` is library/test-only | Start a run expecting a fresh battery unless the embedding API loads the save. |
| MBC1 | Mode-1 RAM-bank offset is not aliased to the active RAM size (8 KiB RAM + bank select) | Out-of-range bank reads return `0xFF`; planned Mooneye MBC1 RAM rows use 32 KiB RAM. |
| MBC2 | Types `0x05`/`0x06` are rejected (`UnsupportedMbc`) | Not supported; no built-in 512×4-bit RAM. |
| CGB DMG-compat | `FF4F`/`FF70` writes still land in `io[]`; high-bit read masks are partial | No effect on DMG-mode rendering; not tested against a compat-mode title that probes those registers. |
| HDMA | VRAM destination overflow wraps instead of stopping; HBlank copies are scheduled by accumulated bus dots (one block/line); the per-block CPU stall is charged after the copy and consumed on the next step; an active HBlank restart and HDMA across the STOP stall are untested | Correct for well-formed HDMA; malformed lengths or exotic restart sequences are unspecified. |
| PPU | Mode-3 OBJ penalty is the Pan Docs per-tile model with a clamped X=0 case; the first line after LCD re-enable does not model a mode-2/OAM lock before dot 84; X=0 same-tile suppression is an approximation | All PPU gates and `dmg-acid2`/`cgb-acid2` pass; raster-effect ROMs outside the suite are unverified. |
| APU | CGB wave first-fetch uses a calibrated `wavePeriod + 6` constant; mixer details beyond `dmg_sound`/`cgb_sound` are unverified | Both sound suites pass; per-title audio nuance is not claimed. |
| Serial | Link-mode log is capped at 4096 bytes; the transfer model is a fixed latency, not link-cable timing | Debug/verdict harnesses only; no link cable. |
| Paths | Save/ROM path handling truncates around the Win9x `MAX_PATH` (260) boundary; `.sav`/`.rtc` write uses a temp/backup rename window | A crash between renames can leave `.bak`/`.tmp` files; load-side validation prevents corrupt state. |
| RTC | Without `--rtc-fixed`, the MBC3 clock follows host wall time; `.rtc` v1 stores a u64 LE anchor at bytes 16–23, reserved bytes 24–31 zero | Deterministic tests must pass `--rtc-fixed`. |
| Backends | Win32 headless paths are verified under Wine/cross-build and, since 2026-11-17, run on Win98/P4 (interpreter OK; `--dynarec` faults immediately, see §3.1); windowed and gamepad paths are still Wine-only, and gamepad axes/dead-zone/focus-loss are untested on hardware | `--windowed` needs DirectX 6+ (`IDirectDraw7`); gamepad needs DX8 (`dinput8.dll`), keyboard falls back to `GetAsyncKeyState`. Real-hardware sign-off is explicitly operator-owned. |

## 5. Test-harness caveats

- External hard gates require the pinned suites under `Z9GB_ROM_DIR`; absence is
  `SKIP` (77), never PASS. The `cgb-acid2` reference PNG is not committed; the
  committed framebuffer golden is the comparison source.
- Sound/interrupt verdicts come from a fixed SRAM protocol (`$A000`/`$A004`),
  not serial output.
- Performance numbers are Wine evidence unless labelled host headless; only the
  host headless gate (`>= 59.0 fps`) is authoritative. Wine is never Win98.
- User ROMs are local and untracked; the matrix in §2.2 is evidence, not a CI
  gate.
- Dynarec stats must be non-vacuous (`blocks > 0`, `executed > 0`);
  `dynarec=disabled reason=...` is a SKIP/FAIL.
- `tier_dmg --gates` fails when any hard gate is skipped (a skip can never be a
  closeout PASS).

## 6. Reproduction proposal: `--capture` / `--replay` (not implemented)

Goal: a user records a session once; an agent or another user replays it
deterministically and compares interpreter vs dynarec without owning the same
timing luck.

Proposed trace format (text, versioned, no ROM bytes):

```
z9gb-trace v1
rom_sha256=<64 hex> rom_size=<n>
flags=cgb:<0|1> dynarec:<0|1> rtc_fixed:<unix|none>
frames=<n>
save_sha256=<64 hex|none>
# frame, input-byte changes (bit order: 0 right,1 left,2 up,3 down,
# 4 a,5 b,6 select,7 start), and optional per-frame framebuffer md5
input <frame> <hex byte>
fb    <frame> <md5 of 92,160-byte framebuffer>
serial <frame> <hex bytes>
```

Proposed CLI:

- `--capture <path>`: while running, record the header, every input transition
  at the frame it was applied, the serial log, and optionally one framebuffer
  md5 per frame; never records ROM bytes.
- `--replay <path>`: validate ROM sha256/size and header, initialize with the
  recorded `rtc_fixed`, apply inputs at frame boundaries, run headless, and
  compare each recorded framebuffer md5 and the serial log. Exit nonzero on the
  first mismatch. `--dynarec` / `--no-dynarec` on the replay command override
  the recorded mode so the same trace can A/B the two engines.
- Determinism requirements: same emulator build, `--rtc-fixed`, no wall-clock or
  audio-device dependency, fixed frame count.

Non-goals: ROM redistribution, savestate/rewind, anti-cheat, network/link
capture.

## 7. Reproduce today

```sh
ZIG=/path/to/zig1_5_clean
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --all
bash examples/z98/z9gb/tests/tier_dmg.sh "$ZIG" --gates
bash examples/z98/z9gb/tests/tier_cgb.sh "$ZIG" --all
bash examples/z98/z9gb/tests/tier_audio.sh --gate "$ZIG"
bash examples/z98/z9gb/tests/tier_win32.sh "$ZIG"            # full Win32 probe tier
bash examples/z98/z9gb/tests/tier_win32.sh --smoke "$ZIG"    # windowed Wine smoke
bash examples/z98/z9gb/tests/tier_dynarec.sh "$ZIG"
bash examples/z98/z9gb/tests/tier_perf.sh "$ZIG" --compat --user-roms /path/to/roms
```

Headless single run with counters:

```sh
wine z9gb.exe --headless --cgb --frames 600 --dynarec --dynarec-stats \
  --rom "path.gbc" --fb-out /tmp/fb.bin
```

## 8. Explicitly out of scope

- GBA/SGB, link cable, IR, printer, cheat devices, savestates, rewind.
- Translating code in RAM/VRAM (dynarec is ROM-only; RAM PCs fall back).
- Rumble output and real tilt hardware (debt above).
- Win98/Pentium II hardware certification.
- General-purpose emulator performance optimization (see §3).
