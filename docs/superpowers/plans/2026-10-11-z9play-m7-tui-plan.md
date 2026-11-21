# z9play M7 — TUI + directory iteration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `std.fs` directory iteration (the one remaining std addition) and a TUI frontend: a directory browser + now-playing pane + in-memory playlist, built on the `Console` vtable (Linux ANSI; Win9x from M6).

**Architecture:** Add `openDir`/`readDir`/`closeDir` to `sf/src/std_file.zig` (Linux `opendir`/`readdir`/`closedir`; Win9x `FindFirstFileA`/`FindNextFileA`/`FindClose`). The app-level `Console` vtable (`platform/console.zig`) and the complete Linux ANSI backend are **already delivered by M5b** (all 9 ops incl. `cursorShow`; not created here); the TUI (`ui.zig`) owns the layout and event loop, reusing `Player` (M4) and the M5b `Console`.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_file` (extended), `Player`, `platform/console`.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m6-win9x-plan.md`. NEXT: `2026-10-11-z9play-m8-flac-plan.md` (optional).

## Global Constraints

- Modify **only** `sf/src/std_file.zig` (+ `std_file_pal.zig` if needed) in `sf/src` (+ its fixture + `scripts/stdlib/expected_dirs.txt`); **no compiler change**; compiler fixed point unchanged.
- `scripts/stdlib/verify_stdlib.sh` MUST stay green.
- Example-only otherwise under `examples/z98/z9play/**`. Z98 rules (NOTE 2026-10-16 — **SUPERSEDED by Amendment 1** below: the M7 base seed is **v101** (fixed point `b299b4b435e624d0ddbd2edde681cbc3`, archive md5 `378f5ea01db25ec69f455fbce52bc947`); D1/D2 are FIXED, D3/D4/D5 are OPEN — see Amendment 1; this class of compiler defects can still surface in new shapes — if one is hit, STOP-present, apply a minimal example-only workaround, and record it in `examples/torrent_example_defects.md` for a later compiler pass); `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/`.

## File Structure

- `sf/src/std_file.zig` (+ `std_file_pal.zig`) — `openDir`/`readDir`/`closeDir` + a `DirEntry` shape.
- `repro/mi_matrix/stdlib_dir_iter_xmod/` — stdlib fixture; `scripts/stdlib/expected_dirs.txt` pin.
- `examples/z98/z9play/platform/console.zig` — `Console` vtable + `Key` (**delivered by M5b; not modified here**).
- `examples/z98/z9play/platform/console_linux.zig` — complete ANSI backend (**delivered by M5b; not modified here**).
- `examples/z98/z9play/ui.zig` — TUI layout + event loop + in-memory playlist.
- `examples/z98/z9play/tests/tier_tui.sh`.

---

### Task 0: Preflight

- [ ] Confirm the std directory-iteration API to expose (name + `DirEntry` fields) and that it works without changing the compiler. Confirm M6's console contract from its Task 6 review.

### Task 1: `std.fs` directory iteration

**Files:** `sf/src/std_file.zig`, `sf/src/std_file_pal.zig`, fixture, `expected_dirs.txt`, `scripts/win32_cross/check_win9x_imports.sh` (whitelist `FindNextFileA` only).
**Interfaces:** `pub const DirEntry = struct { name: []const u8, is_dir: bool };` `pub fn openDir(arena, path: []const u8) !Dir`; `pub fn readDir(arena, d: *Dir) !?DirEntry` (or a one-shot `readAll` returning `[]DirEntry`); `pub fn closeDir(d: *Dir) void`. Linux + Win9x backends.
- [ ] Fixture `stdlib_dir_iter_xmod`: create a scratch dir with files+subdirs, assert the listing (names + is_dir) sorted. Implement. `verify_stdlib` green; fixed point unchanged. Add `FindNextFileA` to the `KERNEL32_9X` list in `scripts/win32_cross/check_win9x_imports.sh`. Commit `feat(std_file): directory iteration (openDir/readDir/closeDir)`.

### Task 2: `Console` vtable + Linux ANSI backend — DELIVERED BY M5b

**Files:** `platform/console.zig`, `platform/console_linux.zig`.
**Status:** this task's deliverable — the complete `Console` vtable + full Linux ANSI backend (`clear`/`setCursor`/`writeStr`/`readKey` incl. arrow escapes/`enterRaw`/`leaveRaw`/`width`/`height`/`cursorShow`) — is **delivered complete by M5b** (`2026-10-16-z9play-m5b-console-contract-plan.md`). No work here.
- [ ] Confirm the M5b contract from its Task 6 review; the TUI (Task 3) consumes it. No commit.

### Task 3: TUI (`ui.zig`)

**Interfaces:** directory pane (filter `.ogg`(+`.flac`)+dirs, `..`, cursor nav `↑↓`/`j k`, Enter play/navigate), now-playing pane, `a`/`d` playlist add/remove, `n`/`p` next/prev, space pause, `+`/`-` volume, `q` quit; layout per blueprint §5.1 at 80×25.
- [ ] Implement on top of `Player` + `Console`. Commit `example(z9play): TUI frontend`.

### Task 4: `tier_tui.sh`

- [ ] Build `-fsafe`; drive the TUI under a pty (`script`): assert the screen renders (dir pane + now-playing), navigation updates the selection, Enter plays (into the WAV sink) to completion, playlist add/remove works, `q` exits restoring the terminal. Non-vacuous. Run PASS. Commit `example(z9play): M7 TUI tier`.
- [ ] **Amendment 1 Win9x gate:** emit/build the TUI for `-osw` (default 9x no-CRT); assert PE32, no msvcrt, and `check_win9x_imports.sh <exe> 9x`. Keep the pty behavior assertions on Linux; Wine smoke is allowed but is not a substitute for the operator-pending Win98/Me hardware check.

**Gate:** `tier_tui.sh` green; terminal restored; `--dump-c89` md5 recorded; Win9x `-osw` build is PE32, imports no msvcrt, and passes `check_win9x_imports.sh <exe> 9x` (hardware verification operator-pending).

### Task 5: Docs + commit

- [ ] Update `NOTES.md`/`README.md` + `docs/sf/QUICK_REF.md` (new std dir API). Commit `docs(z9play): M7 TUI + std dir iteration`.
- [ ] **Closeout (Amendment 1):** rotate seed **v101 → v102** (archive + `release/seed/CHANGELOG.md` + QUICK_REF seed/pins) because the archive `lib/` payload changed; the compiler self-emission fixed point is expected to remain `b299b4b435e624d0ddbd2edde681cbc3`.

### Task 6: Next-milestone amendment review (M8)

- [ ] Read `2026-10-11-z9play-m8-flac-plan.md`. Judge whether M7's decoder-abstraction boundary (does the player core select a decoder by a vtable/`union(enum)`, so FLAC can slot in?) matches M8's assumptions. If not, **STOP-present** the M8 amendment (or recommend dropping the optional M8); else record "no amendment needed".

**Gate:** approved M8 amendment/drop, or justified "no amendment needed".

---

### Amendment 1 — M6 handoff truth-up: seed v101, no-CRT Win9x, dir-iteration gate (operator ruling, 2026-10-18)

This amendment supersedes the "NOTE 2026-10-16" seed/defect clause in the
Global Constraints and adds the missing Win9x directory-iteration
authorization/gate. It does not change the TUI feature set or the Console
contract.

- **Base seed is v101**, not v98: `release/seed/zig1-seed.tgz` (archive md5
  `378f5ea01db25ec69f455fbce52bc947`), rebuilt binary/fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`. Rebuild with
  `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz <out>` for
  every M7 build/gate.
- **Defect status:** D1 and D2 are FIXED at root cause and are included in
  seed v101; the M5b `Key.none` and M6 example workarounds remain. Do not say
  "D1–D8 are all FIXED": `examples/torrent_example_defects.md` currently lists
  D3 (conditional `@import` lazy-load) OPEN/deferred, D4 (static-analyzer
  cluster) OPEN, and D5 (`extern fn` with a body) OPEN. If a new defect shape
  is hit, STOP-present, apply the minimal example-only workaround, and record
  it in `examples/torrent_example_defects.md`.
- **Win9x profile is 9x no-CRT by default:** `-osw` emits
  `-DZIG_NO_CRT -nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32` (plus
  `-lwinmm`/`-lwsock32` only when used). The Task 1 Win9x directory backend
  must use only KERNEL32 `FindFirstFileA`/`FindNextFileA`/`FindClose`; it must
  not introduce msvcrt or CRT dependencies. Native MSVC/OpenWatcom `.bat`
  scripts remain design-verified only; real Win98/Me hardware verification is
  operator-pending, and M7 docs must say "design-verified; hardware
  verification pending".
- **Task 1 touch-set addition:** add
  `scripts/win32_cross/check_win9x_imports.sh` to the M7 touch set and add
  `FindNextFileA` to its `KERNEL32_9X` list. The closed-world 9x import gate
  currently allows `FindFirstFileA`/`FindClose` but not `FindNextFileA`;
  without this, any z9play `-osw` build that calls `readDir` fails the gate.
  This is the only script change authorized by this amendment.
- **Seed rotation:** because Task 1 changes `sf/src/std_file.zig` /
  `std_file_pal.zig`, the archive `lib/` payload changes. At M7 closeout
  rotate seed **v101 → v102** per `docs/sf/QUICK_REF.md` (archive +
  `release/seed/CHANGELOG.md` + QUICK_REF seed/pins), even though the compiler
  self-emission fixed point is independent and expected to remain
  `b299b4b435e624d0ddbd2edde681cbc3`. The M7 gate must record the rotation.
- **M6 console handoff:** `platform/console_win9x.zig` is complete (all 9
  `Console` ops) and is selected by `@isWindows()` in `main.zig`; M7 Task 2 is
  confirmation only, and Task 3 may consume either backend. Reuse the M5/M6
  raw-mode discipline: call `leaveRaw` before every `std.os.exit` path; the
  Win9x backend's `atexit` restore is only a crash backstop.
- **Win9x TUI gate:** add to Task 4: emit/build the TUI for `-osw` (default 9x
  no-CRT), assert PE32, no msvcrt, and the `check_win9x_imports.sh <exe> 9x`
  gate. Keep the pty behavior assertions on Linux; Wine smoke is allowed but
  is not a substitute for the operator-pending Win98/Me hardware check.
- **TUI size semantics:** Win9x `width`/`height` return the screen-buffer size
  (`dwSize`), not the visible window (`srWindow`). M7 must pin the layout to
  the 80×25 visible window (or clamp to it) and must not assume the reported
  size is the visible rectangle.
- **Directory API clarifications (no shape change):** `DirEntry.name` is
  caller-arena-owned; `Dir` holds the OS handle plus the Win9x
  first-entry/pending state; `readDir` copies each name into the caller arena;
  `closeDir` closes the handle. Do not assume `readDir` filters `.`/`..`; the
  TUI synthesizes `..`. On Linux, `is_dir` must fall back to `stat` when
  `d_type == DT_UNKNOWN`. Use `std_file` naming in code/docs; there is no
  `std.fs` namespace in `sf/src/std.zig`.
