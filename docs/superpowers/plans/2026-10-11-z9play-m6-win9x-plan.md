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

### Amendment 2 — Win9x default profile, no-CRT runtime, other-arch research (operator rulings, 2026-10-18)

This amendment **supersedes, for Tasks T5.1–T5.6 only**, the Global Constraints clauses "no compiler change" and "no seed rotation". Tasks 0–6 above remain complete; T5.5 re-truthes Task 5's docs.

**Why:** the T5 review proved the manual Win98 procedure false — the built exe imports KERNEL32 `GetFileSizeEx`, `SetFilePointerEx`, `GetFileAttributesExA` (minimum client Windows XP) from `sf/src/std_file.zig:226/:239/:321`; Win98 resolves the import table at load and fails before `main`. z9torr shares the defect. All other exe imports are Win9x-safe; Wine cannot prove Win98 loadability, so the mechanical per-DLL import whitelist is the loadability gate.

**Rulings (binding):**

- (a) Win9x = 95/98/Me; baseline = **Win98/Me reference**; Win95 best-effort.
- (b) **Default `-osw` = 9x, NEVER nt.** `nt` is explicit opt-in only.
- (c) **no-CRT (kernel32-only) is the default for `-osw`**; the XP/NT layer stays available, opt-in.
- (d) Dynamic `GetProcAddress` resolution REJECTED; a new `@isWin9x()` builtin REJECTED.
- (e) Mechanism = compile-time profile via C build define: default (no define) = Win9x path; `-osw nt` emits `-DZIG_WIN_NT`; profile-dependent APIs are hand-written C helpers in `zig_pal.c` (`#ifdef ZIG_WIN_NT` modern XP calls / default Win95 equivalents), exposed to Z98 via `extern "c"` (existing `pal_file_*` pattern).
- (f) T5.6 is pure research/report: no "make it work", no emulation shortcuts (e.g. "RISC-V could emulate 32-bit x86"). Aim as close and performant as we can; report the real work even if infamous; list new compiler features and inline-asm requirements and how it can work overall. Report path `sf/docs/tech_docs/Other_arch_supp.md` (+ INDEX row).
- (g) Split confirmed: six tasks. Seed rotation happens at T5.3 iff `sf/src` changes (it will).

#### Task T5.1: Inventory + capability table (report only)

- [ ] Produce `task-5.1-report.md`: per-DLL import inventory for z9play and z9torr (objdump + `nm -u` attribution); every `@isWindows()` std branch and its Win9x safety; CRT-startup vs emitted-code import split; per-API Win9x equivalent/fallback (`GetFileSizeEx`→`GetFileSize`; `SetFilePointerEx`→`SetFilePointer`; `GetFileAttributesExA`→`FindFirstFileA` vs `CreateFileA`+`GetFileTime` — decide with evidence); `emit_support.zig` ↔ `sf/src/include/*` mirror map (`check_emit_support.sh`); CLI-help delta (all 12 parsed-but-undocumented flags); whitelist drafts (9x/nt) per DLL with min-OS annotation; proposed `-osw [9x|nt]` CLI semantics. No source edits.

**Gate:** review only (report accuracy).

#### Task T5.2: Compiler plumbing

- [ ] CLI `-osw [9x|nt]` (bare `-osw` = 9x), `target_win_profile`; emit the profile into `build_target.sh`/`.bat`/`.owc` (default = no define = Win9x; nt adds `-DZIG_WIN_NT`); `--help` truth-up (all parsed flags + profile). Commit `feat(main): -osw [9x|nt] target win profile` + `docs(sdd): T5.2 report`.

**Gate:** usual compiler gates — corpus frozen-1124 md5 `518eca1a9b5d3e1cc5a48abce214abd8` (0 movers), goldens 5/5, mi_matrix 25+oob, examples 26/26+26/26, stdlib 285/0, seed hop2==hop3, pins 0/8 recorded old→new, markers, `check_emit_support.sh`. No seed rotation yet.

#### Task T5.3: Compiler semantics + no-CRT runtime

- [ ] `std_file` 3 XP+ APIs → C helpers `pal_file_size` / `pal_file_seek64` / `pal_file_mtime` (`#ifdef ZIG_WIN_NT` = modern XP calls; default = Win95 equivalents per T5.1); `std_file_pal.zig` `extern "c"`.
- [ ] `std_os.getenv` → `GetEnvironmentVariableA`; `std_time.time` → `GetSystemTimeAsFileTime`.
- [ ] no-CRT default for `-osw`: emitted mingw link `-nostdlib -e,_mainCRTStartup -lgcc -lkernel32` (+winmm/wsock32 as needed).
- [ ] Runtime/shim: `c_exit`→`ExitProcess` under `ZIG_NO_CRT`; `pal_abort`; `strlen`/`memcpy`/`strncmp`; `zig_runtime` strlen.
- [ ] Edit **BOTH** the `sf/src/emit_support.zig` literals **and** the `sf/src/include/*` + `sf/src/c_exit.c` mirrors; `check_emit_support.sh` green.
- [ ] Commits `fix(win9x): Win9x-safe std runtime + no-CRT default for -osw` + `docs(sdd): T5.3 report`.

**Gate:** usual compiler gates + profile-aware import whitelist gate + std_file cross-probe (create/write/size/seek/read/mtime) Wine↔Linux + **seed rotation** (`archive_seed.sh`, QUICK_REF pins/seed, CHANGELOG; hop2==hop3 recorded).

#### Task T5.4: z9torr Win9x

- [ ] Build z9torr with default `-osw` (9x, no-CRT): whitelist green (KERNEL32 + WS2_32, no msvcrt); Wine smoke (file/disk; network build-only or loopback); README note. Commit `example(z9torr): Win9x default profile build` + `docs(sdd): T5.4 report`.

**Gate:** Wine z9torr + std gates; no compiler hops.

#### Task T5.5: z9play Win9x + docs

- [ ] `tier_win9x` under default `-osw`: PE32, no msvcrt, Wine WAV parity, console restore; whitelist; truth-up `demo/win9x_README.txt`, `NOTES.md`, `README.md` (Win9x default, NT opt-in, no-DLL-bundling note). Commits `example(z9play): Win9x default profile tier` + `docs(z9play): Win9x default profile` + `docs(sdd): T5.5 report`.

**Gate:** Wine z9play/tier 14/14 + std gates; no compiler hops.

#### Task T5.6: Other-arch exploration (report only)

- [ ] Write `sf/docs/tech_docs/Other_arch_supp.md` (+ INDEX row). No tests, no code. Cover: C89-as-IR adequacy per target (AArch32, RISC-V32, 64-bit ARM/RISC-V/x86-64; 16-bit DOS as a feasibility question); the real blockers (Z98's 32-bit semantic model `usize = unsigned int`, 4-byte pointers, `SYS_LLSEEK=140`, `-m32`; per-arch/OS PAL; struct layouts/ABI; 64-bit syscalls); **new compiler features required** (target-width-parameterized type model, pointer↔int casts, 64-bit literal/arith support, ABI selection, etc.); **inline-asm requirements** (which targets genuinely need it and how it would work); targeting another arch (emit C) vs self-hosting the compiler there (own PAL port); effort/phasing/risks and a file-level change list. Explicitly no emulation framing; aim as close and performant as the architecture allows.

**Gate:** review only (report quality); INDEX row present.

**Global gate reminders:** battery definition unchanged from prior milestones; run gates sequentially (spill-file race); `--dump-c89` requires a pre-created `--output-dir`; reports under `.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/`; no push.

### Amendment 3 — T5.3 no-CRT shim set (Option A) + T5.3a safety inventory (operator ruling, 2026-10-18)

Operator ruling: before implementing T5.3, run a **second inventory task (T5.3a)** on what to implement and how to do it safely; then implement **path A** — the full emitted no-CRT shim set, extending T5.3's original list.

**Why:** T5.1 §3.3/§4.8 measured that `-nostdlib` links leave these unresolved in emitted code: `std_io` → `__acrt_iob_func`, `fwrite`, `getchar`, `putchar`; `std_os` → `exit`, `getenv`; `std_time` → `__time32`; `zig_runtime` → `strlen`; `c_exit` → `exit`; z9torr adds `memcpy`; `console_win9x` → `atexit`. The original T5.3 list covers only some; without the rest T5.4/T5.5 cannot link on the 9x default.

**Ruling (A):** T5.3 is authorized and required to implement the full no-CRT runtime shim set in the emitted runtime/support (`sf/src/emit_support.zig` literals + `sf/src/include/*` mirrors, behind `ZIG_NO_CRT`): `exit`→`ExitProcess`; `atexit` registry invoked on the exit path; `__acrt_iob_func`/`_iob`/std-stream emulation + `fwrite`/`getchar`/`putchar`; `memcpy`/`strlen`/`strncmp`; `time`/`__time32` helper; plus the plan-named `c_exit`/`pal_abort`/`getenv`→`GetEnvironmentVariableA`/`GetSystemTimeAsFileTime`/std_file helpers. CRT path behavior unchanged. `-DZIG_NO_CRT` is added by T5.3's emitted 9x build recipe (T5.2 only emits the profile define). `std_os.env` uses a static PAL buffer (single-threaded; preserves the current slice-lifetime contract).

#### Task T5.3a: No-CRT runtime inventory + safe implementation design (REPORT ONLY, runs before T5.3)

- [ ] Produce `task-5.3a-report.md`: exact shim placement and ownership between `zig_pal.c` / `zig_runtime.c` / any new emitted shim file; duplicate-definition/symbol-clash analysis for CRT vs `ZIG_NO_CRT`; header/prototype placement under `-Wall`; `atexit` registry semantics (capacity, ordering, `ExitProcess` bypass) and how `c_exit`/`exit` invoke it; `__acrt_iob_func`/`_iob` std-stream emulation + `fwrite`/`getchar`/`putchar` parity; `memcpy`/`strlen`/`strncmp`; `time`/`__time32` FILETIME→Unix conversion (1601 epoch, 64-bit math); `GetEnvironmentVariableA` static buffer size/ownership; `std_file` helper signatures + Win95 fallback semantics (size/seek64 high-DWORD/mtime source decision with evidence); emitted build recipe changes (sh/bat/owc) incl. `-DZIG_NO_CRT`, `-nostdlib -e,_mainCRTStartup -lgcc -lkernel32` (+winmm/wsock32); `emit_support.zig` ↔ include mirror map updates; whitelist-gate artifact design; risk list + concrete test probes (Wine/Linux). File:line inventory of every T5.3 edit. No source edits.

**Gate:** review only (design/safety review). T5.3 then implements exactly the approved design + Amendment 3 ruling; deviations STOP-present.

**Next:** T5.3a → T5.3.

### Amendment 4 — Redistribution-first Win9x (path B) + native-toolchain no-CRT + T5.3b (operator ruling, 2026-10-18)

**Goal (operator):** every generated `.exe` must be a single drag-and-drop file on a clean Win98/Me machine (Win95 best-effort). No instructions to install an `msvcrt.dll` redistributable. `winmm.dll` / `wsock32.dll` are OS DLLs (Win95+) and are allowed; `msvcrt` on the 9x path is not.

**Ruling (B):** no-CRT / kernel32-only is the **9x default for all toolchains**:
- mingw: `-nostdlib -e,_mainCRTStartup -lgcc -lkernel32` + the Amendment 3 shim set.
- MSVC 6: no-CRT (`/Zl` compile, `/NODEFAULTLIB`, `/entry`, runtime helpers) — exact flags/design from T5.3b.
- OpenWatcom: no-CRT (`option nodefaultlibs`, entry, runtime helpers) — exact design from T5.3b.
- Static-CRT variants remain emitted as alternates (single EXE, no DLL) for users who want them.

**Script layout (operator-approved):**
- `build_target.sh` unchanged for mingw (9x default no-CRT; `nt` arg = CRT + `ZIG_WIN_NT`).
- For `-osw`, emit: `build_target_nocrt.bat`, `build_target_crt.bat` (MSVC); `build_owc_nocrt.bat`, `build_owc_crt.bat` (OpenWatcom). Each script header states its redistribution guarantee; `_nocrt` is the 9x default.
- Existing `build_target.bat` / `build_owc.bat` names: T5.3b recommends keep-as-alias or remove; no dangling docs.

**T5.3a rulings folded in:** env static-buffer narrowing accepted and documented; `GetCommandLineA` argv parser authorized; `_iob` omission ratified (no emitted reference under the pinned toolchain) and must be documented visibly; PAL helpers apply to all Windows profiles (CRT-linked builds behavior-equivalent; wording truth-up).

#### Task T5.3b: native-toolchain no-CRT investigation/design (REPORT ONLY, after T5.3a, before T5.3)

- [ ] Produce `task-5.3b-report.md`:
  1. **MSVC 6.0 no-CRT** — exact compile flags (`/Za /Zl /DZIG_NO_CRT …`), exact `link` invocation (`/NODEFAULTLIB`, `/entry` symbol decoration, `/subsystem:console`, libs), `mainCRTStartup` + argv, and the runtime-helper set actually required by emitted C (`__chkstk` vs `/Gs`, 64-bit mul/div/rem/shift, `_fltused`, float helpers), with the decide-and-justify choice of implementing helpers in C vs taking vendor static-lib objects; verify the static-CRT alternate script.
  2. **OpenWatcom no-CRT** — `wcc386` flags, `wlink` `system` choice, `option nodefaultlibs`, entry/stack, 64-bit helper set (`__I8M`/`__U8D`/…), static-runtime alternate.
  3. **Shared** — toolchain-neutral `zig_nocrt.c` vs per-toolchain startup; header/prototype cleanliness; import-table expectations per variant (only OS DLLs); exact contents of the four `.bat` scripts + `.sh` header update.
  4. **Verification strategy** — host has only mingw+wine, no `cl`/`wcc386`; attempt to obtain/use OpenWatcom 2 (Linux-host) for real compile/link probes; MSVC 6 cannot run here → state exactly what is design-verified vs unverified and the evidence (vendor docs, import tables, probes) for each claim.
  5. File:line inventory of every T5.3 edit; risk list.
- No source edits.

**Gate:** review only (redistribution/design safety).

#### T5.3 revisions

- Implement the T5.3a design + T5.3b native scripts; emit the four `.bat` files for `-osw`; resolve old-name aliases per T5.3b.
- Add visible doc `sf/docs/tech_docs/13_windows_support.md` (+ INDEX): profile × toolchain × CRT matrix, `_iob` omission rationale, env lifetime, redistribution policy, verification status.
- Gates unchanged + native-script review; seed rotation.

**T5.4/T5.5:** gate text uses actual `WSOCK32.DLL` (not `WS2_32`).

**Next:** T5.3b → T5.3.

### Amendment 5 — No native runtime probing; cleanup precondition; hardware verification deferred (operator ruling, 2026-10-18)

- **Drop the native-toolchain probing requirement from T5.3b.** Do NOT download/install OpenWatcom, do NOT run native toolchains under Wine, do NOT attempt MSVC/OWC runtime probes. The approach is too fragile and makes a mess.
- T5.3b is **documentation + emitted-C static analysis only**: exact compile/link commands, entry/argv design, runtime-helper strategy (`__chkstk` vs `/Gs`, 64-bit helpers, `_fltused`), static-CRT alternates, exact script contents, import-table expectations, and an explicit **unverified-locally** statement per claim (vendor docs + file:line + emitted-C evidence only).
- **Manual Win98/hardware verification is operator-owned and happens after the z9play milestone completes.** Native scripts and the Windows-support doc must state "design-verified; hardware verification pending" until the operator records results. No report may claim native runtime verification before that.
- **Precondition before continuing:** clean `/tmp` of project-created artifacts (including the aborted `/tmp/t53b/ow2-c-linux-x64` download) and wine-created state (`~/.wine`); preserve the opencode/node temp internals. Then rebuild the compiler fresh from the seed into `/tmp/m6` (`bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/m6`) and record its md5.
- T5.3 remains: mingw 9x no-CRT + full shim set + argv parser + the T5.3b-designed native scripts + `sf/docs/tech_docs/13_windows_support.md`; usual compiler gates; seed rotation. T5.4/T5.5 Wine gates unchanged; real-hardware checks deferred as above.

**Next:** cleanup + fresh compiler build → T5.3b (design-only) → review → T5.3.
