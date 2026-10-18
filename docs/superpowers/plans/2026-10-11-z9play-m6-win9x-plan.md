# z9play M6 — Win9x audio + console — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the CLI player build and run on **Windows 9x**: a `waveOut` audio backend and a Win9x console backend (raw keys + cursor position), selected at compile time via `@isWindows()`, proven via mingw build + Wine smoke and a documented manual Win98 procedure.

**Architecture:** Add `platform/audio_win9x.zig` and `platform/console_win9x.zig`. The audio backend implements the M4 `AudioOut` vtable; the console backend implements the **complete** `Console` contract created and completed by **M5b** (`platform/console.zig` + the complete Linux backend, all 9 ops). `main`/`cli` select via `@isWindows()` (with an explicit `else`). Build with the repo's `scripts/win32_cross/` mingw path; smoke under Wine (`-osw`).

**Tech Stack:** Z98 (`zig1` → C89 → mingw i686), `@cInclude("windows.h")`/`mmsystem.h`, `extern "c"` (or `"stdcall"`) `waveOut*`/`SetConsoleMode`/`ReadConsoleInput`/`SetConsoleCursorPosition`; Wine for smoke.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m5-cli-plan.md`. NEXT: `2026-10-11-z9play-m7-tui-plan.md`.

## Global Constraints

Same as prior milestones: example-only `examples/z98/z9play/**`; **no compiler change**; no seed rotation; Z98 rules (`@isWindows()` must have an explicit `else` so both arms emit valid C; NOTE 2026-10-16 — the M6 base seed is **v98** (fixed point `f18b69ece1917bf970a036b276e5e403`), superseding the v97 this milestone was authored against; compiler defects **D1–D8 are all FIXED** in seed v98 (see `examples/torrent_example_defects.md`), so the prior D7-class workaround warning is retired; this class of cumulative compiler defects can still surface in new shapes — if one is hit, STOP-present, apply a minimal example-only workaround, and record it in `examples/torrent_example_defects.md` for a later compiler pass); `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/`. Reuse `scripts/win32_cross/cross_build_run.sh` (as z9torr M5 did) for the mingw+wine path.

## File Structure

- `examples/z98/z9play/platform/audio_win9x.zig` — `waveOut*` backend.
- `examples/z98/z9play/platform/console_win9x.zig` — Win9x console backend.
- `examples/z98/z9play/tests/tier_win9x.sh` — mingw build + Wine smoke.
- `examples/z98/z9play/demo/win9x_README.txt` — manual Win98 procedure.

---

### Task 0: Preflight

- [ ] Confirm mingw i686 + wine present; confirm the `cross_build_run.sh` path and its `-osw` build recipe; confirm M5's console/CLI contract from its Task 6 review.

### Task 1: `waveOut` audio backend

**Interfaces:** `audio_win9x.open/write/close/drain` over `waveOutOpen`/`waveOutPrepareHeader`/`waveOutWrite`/`waveOutUnprepareHeader`/`waveOutClose` (+ `WAVEHDR`), 16-bit stereo PCM, 500 ms buffers (starvation mitigation).
- [ ] Build `-osw` (mingw) clean; wire through `@isWindows()`. Commit `example(z9play): Win9x waveOut audio backend`.

### Task 2: Win9x console backend

**Interfaces:** `console_win9x` implementing the **complete M5b `Console` contract** (all 9 ops: `enterRaw`/`leaveRaw`/`readKey`/`clear`/`setCursor`/`writeStr`/`width`/`height`/`cursorShow`). `enterRaw` (AMENDMENT 1, 2026-10-18 — operator ruling, Option 3): `SetConsoleMode` clear `ENABLE_LINE_INPUT`/`ENABLE_ECHO_INPUT` **and** `ENABLE_PROCESSED_INPUT` (so Ctrl-C is reported in the input buffer as a `KEY_EVENT` with `uChar == 0x03`). `leaveRaw` (restore): **explicit before every `std.os.exit` path** (Z98 `std.os.exit` runs no `defer`) **plus** an `atexit` crash backstop — `defer` alone is insufficient; `SetConsoleCtrlHandler` is NOT used (Z98 cannot define stdcall functions — defect D5; see Amendment 1). `readKey`: `ReadConsoleInput`/`KEY_EVENT`, mapping `VK_*` (arrows/`VK_RETURN`/`VK_ESCAPE`) to the shared `Key` variants and Ctrl-C (`uChar == 0x03`) to `.sigint`. `clear`/`setCursor`/`writeStr`/`cursorShow`: `FillConsoleOutputCharacter`/`SetConsoleCursorPosition`/`WriteConsole`. `width`/`height`: `GetConsoleScreenBufferInfo`.
- [ ] Build `-osw` clean. Commit `example(z9play): Win9x console backend`.

### Task 3: Backend selection

**Files:** `main.zig`/`cli.zig`.
- [ ] Route audio + console through `@isWindows()` (`if/else`, both arms valid C) using the M5b `Console` contract. Precedence: with `Z9PLAY_WAV_OUT` set select the WAV sink on **all** platforms (hermetic/Wine-parity override); else `@isWindows()` → waveOut/Win9x console, with an explicit `else` → OSS/Linux console. Preserve M5's exit codes on Win9x (0/1/2/3/4/5). Build both `-osl` and `-osw` clean. Commit `example(z9play): select Win9x backends via @isWindows()`. (`edit`/`fastedit`.)

### Task 4: `tier_win9x.sh` (mingw build + Wine smoke)

- [ ] `tier_win9x.sh`: (a) build z9play for `-osw` via the cross harness → assert `PE32` + no undefined symbols; (b) run under Wine with the WAV/`waveOut` path driving a fixture and assert the emitted PCM matches the Linux golden (parity within M3 tolerance); (c) assert raw-mode restore on exit. SKIP-with-reason if wine/mingw absent. Run PASS. Commit `example(z9play): M6 Win9x tier`.

**Gate:** `tier_win9x.sh` green (`PE32`, Wine parity, console restore); `-osw --dump-c89` md5 recorded.

### Task 5: Manual Win9x procedure + docs

- [ ] `demo/win9x_README.txt`: how to copy the `.exe` + an `.ogg` to a real Win98 box, run, expected console behavior, and the raw-mode restore caveat. Update `NOTES.md`/`README.md`. Commit `docs(z9play): manual Win98 procedure`.

### Task 6: Next-milestone amendment review (M7)

- [ ] Read `2026-10-11-z9play-m7-tui-plan.md`. Judge whether M6's `console_win9x` + M5's Linux console actually expose the full `Console` vtable M7 needs (cursor addressing, size, screen clear, non-echoed keys) on both platforms, and whether M7's `std.fs` directory-iteration addition is still the right shape. If an amendment is required, **STOP-present** it; else record "no amendment needed".

**Gate:** approved M7 amendment or justified "no amendment needed".

### Amendment 1 — T2 Ctrl-C mechanism (operator ruling, 2026-10-18)

Z98 cannot define a stdcall function: `extern "stdcall" fn` with a body is accepted (rc=0) and the definition is silently dropped (link error surfaces at the C toolchain, not as a diagnostic); `callconv(...)` is rejected by the parser; `export fn` is cdecl. The originally-planned `SetConsoleCtrlHandler` callback is therefore not implementable in Z98 — a cdecl function cast to the stdcall `PHANDLER_ROUTINE` is a real i386 stack-cleanup ABI defect (review Critical, objdump `ret` vs `ret $4`).

**Ruling (Option 3):** `enterRaw` clears `ENABLE_PROCESSED_INPUT`; Ctrl-C is delivered as a `KEY_EVENT` with `uChar == 0x03` and `readKey` maps it to `.sigint` (the backend already carries a defensive 0x03 arm); `SetConsoleCtrlHandler` and its cdecl cast are removed; `atexit` remains the restore backstop. Known limitations (documented in Task 5 docs): Ctrl-Break still terminates via the default handler; console-close/shutdown restore is moot (the console is gone).

The compiler issue is recorded as defect **D5** in `examples/torrent_example_defects.md`: defect = extern-fn-with-body silent drop; feature gap = stdcall function definitions do not exist; minimal fix = clean reject with an error code; full fix = stdcall definition support.
