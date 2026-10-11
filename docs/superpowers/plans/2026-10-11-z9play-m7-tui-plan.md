# z9play M7 — TUI + directory iteration — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `std.fs` directory iteration (the one remaining std addition) and a TUI frontend: a directory browser + now-playing pane + in-memory playlist, built on the `Console` vtable (Linux ANSI; Win9x from M6).

**Architecture:** Add `openDir`/`readDir`/`closeDir` to `sf/src/std_file.zig` (Linux `opendir`/`readdir`/`closedir`; Win9x `FindFirstFileA`/`FindNextFileA`/`FindClose`). Define the app-level `Console` vtable (`platform/console.zig`) and a Linux ANSI backend; the TUI (`ui.zig`) owns the layout and event loop, reusing `Player` (M4).

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_file` (extended), `Player`, `platform/console`.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m6-win9x-plan.md`. NEXT: `2026-10-11-z9play-m8-flac-plan.md` (optional).

## Global Constraints

- Modify **only** `sf/src/std_file.zig` (+ `std_file_pal.zig` if needed) in `sf/src` (+ its fixture + `scripts/stdlib/expected_dirs.txt`); **no compiler change**; compiler fixed point unchanged.
- `scripts/stdlib/verify_stdlib.sh` MUST stay green.
- Example-only otherwise under `examples/z98/z9play/**`. Z98 rules (NOTE 2026-10-11: compiler defects D1–D6 are FIXED in seed v97 — no workarounds needed); `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/`.

## File Structure

- `sf/src/std_file.zig` (+ `std_file_pal.zig`) — `openDir`/`readDir`/`closeDir` + a `DirEntry` shape.
- `repro/mi_matrix/stdlib_dir_iter_xmod/` — stdlib fixture; `scripts/stdlib/expected_dirs.txt` pin.
- `examples/z98/z9play/platform/console.zig` — `Console` vtable + `Key`.
- `examples/z98/z9play/platform/console_linux.zig` — ANSI backend (clear/cursor/size/keys incl. arrow escapes).
- `examples/z98/z9play/ui.zig` — TUI layout + event loop + in-memory playlist.
- `examples/z98/z9play/tests/tier_tui.sh`.

---

### Task 0: Preflight

- [ ] Confirm the std directory-iteration API to expose (name + `DirEntry` fields) and that it works without changing the compiler. Confirm M6's console contract from its Task 6 review.

### Task 1: `std.fs` directory iteration

**Files:** `sf/src/std_file.zig`, `sf/src/std_file_pal.zig`, fixture, `expected_dirs.txt`.
**Interfaces:** `pub const DirEntry = struct { name: []const u8, is_dir: bool };` `pub fn openDir(arena, path: []const u8) !Dir`; `pub fn readDir(arena, d: *Dir) !?DirEntry` (or a one-shot `readAll` returning `[]DirEntry`); `pub fn closeDir(d: *Dir) void`. Linux + Win9x backends.
- [ ] Fixture `stdlib_dir_iter_xmod`: create a scratch dir with files+subdirs, assert the listing (names + is_dir) sorted. Implement. `verify_stdlib` green; fixed point unchanged. Commit `feat(std_file): directory iteration (openDir/readDir/closeDir)`.

### Task 2: `Console` vtable + Linux ANSI backend

**Files:** `platform/console.zig`, `platform/console_linux.zig`.
**Interfaces:** `Console` struct (blueprint §2.2) + `Key` (chars + arrows + enter/esc); Linux backend: `clear` (`\033[2J\033[H`), `setCursor` (`\033[<y>;<x>H`), `writeStr`, `readKey` (raw, arrow escape state machine), `enterRaw`/`leaveRaw` (termios, restore in `defer`), `width`/`height` (`ioctl TIOCGWINSZ`).
- [ ] Unit test (pty): clear/setCursor emit expected escapes; arrow keys decode; size read. Implement. PASS. Commit `example(z9play): Console vtable + Linux ANSI backend`.

### Task 3: TUI (`ui.zig`)

**Interfaces:** directory pane (filter `.ogg`(+`.flac`)+dirs, `..`, cursor nav `↑↓`/`j k`, Enter play/navigate), now-playing pane, `a`/`d` playlist add/remove, `n`/`p` next/prev, space pause, `+`/`-` volume, `q` quit; layout per blueprint §5.1 at 80×25.
- [ ] Implement on top of `Player` + `Console`. Commit `example(z9play): TUI frontend`.

### Task 4: `tier_tui.sh`

- [ ] Build `-fsafe`; drive the TUI under a pty (`script`): assert the screen renders (dir pane + now-playing), navigation updates the selection, Enter plays (into the WAV sink) to completion, playlist add/remove works, `q` exits restoring the terminal. Non-vacuous. Run PASS. Commit `example(z9play): M7 TUI tier`.

**Gate:** `tier_tui.sh` green; terminal restored; `--dump-c89` md5 recorded.

### Task 5: Docs + commit

- [ ] Update `NOTES.md`/`README.md` + `docs/sf/QUICK_REF.md` (new std dir API). Commit `docs(z9play): M7 TUI + std dir iteration`.

### Task 6: Next-milestone amendment review (M8)

- [ ] Read `2026-10-11-z9play-m8-flac-plan.md`. Judge whether M7's decoder-abstraction boundary (does the player core select a decoder by a vtable/`union(enum)`, so FLAC can slot in?) matches M8's assumptions. If not, **STOP-present** the M8 amendment (or recommend dropping the optional M8); else record "no amendment needed".

**Gate:** approved M8 amendment/drop, or justified "no amendment needed".
