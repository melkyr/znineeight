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
- Example-only otherwise under `examples/z98/z9play/**`. Z98 rules (NOTE 2026-10-16 — the M7 base seed is **v98** (fixed point `f18b69ece1917bf970a036b276e5e403`), superseding the v97 this milestone was authored against; compiler defects **D1–D8 are all FIXED** in seed v98 (see `examples/torrent_example_defects.md`), so the prior D7-class workaround warning is retired; this class of cumulative compiler defects can still surface in new shapes — if one is hit, STOP-present, apply a minimal example-only workaround, and record it in `examples/torrent_example_defects.md` for a later compiler pass); `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/`.

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

**Files:** `sf/src/std_file.zig`, `sf/src/std_file_pal.zig`, fixture, `expected_dirs.txt`.
**Interfaces:** `pub const DirEntry = struct { name: []const u8, is_dir: bool };` `pub fn openDir(arena, path: []const u8) !Dir`; `pub fn readDir(arena, d: *Dir) !?DirEntry` (or a one-shot `readAll` returning `[]DirEntry`); `pub fn closeDir(d: *Dir) void`. Linux + Win9x backends.
- [ ] Fixture `stdlib_dir_iter_xmod`: create a scratch dir with files+subdirs, assert the listing (names + is_dir) sorted. Implement. `verify_stdlib` green; fixed point unchanged. Commit `feat(std_file): directory iteration (openDir/readDir/closeDir)`.

### Task 2: `Console` vtable + Linux ANSI backend — DELIVERED BY M5b

**Files:** `platform/console.zig`, `platform/console_linux.zig`.
**Status:** this task's deliverable — the complete `Console` vtable + full Linux ANSI backend (`clear`/`setCursor`/`writeStr`/`readKey` incl. arrow escapes/`enterRaw`/`leaveRaw`/`width`/`height`/`cursorShow`) — is **delivered complete by M5b** (`2026-10-16-z9play-m5b-console-contract-plan.md`). No work here.
- [ ] Confirm the M5b contract from its Task 6 review; the TUI (Task 3) consumes it. No commit.

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
