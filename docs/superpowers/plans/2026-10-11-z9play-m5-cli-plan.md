# z9play M5 — CLI frontend — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Linux CLI player: `z9play <file.ogg> [--volume N|--start SEC|--loop|--quiet|--version|--help]` with a startup metadata line, a per-second `\r` status line, non-echoed key handling (space / `+` / `-` / `q` / Ctrl-C), and the exact exit codes.

**Architecture:** `cli.zig` parses args and drives `Player` (M4). A minimal local formatter renders `mm:ss`, the volume bar, and the status line (no `std.fmt.bufPrint`). Raw keyboard input on Linux uses `termios` via `extern "c"` (restored in `defer`), with a `SIGINT` handler mapped to quit.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `Player` (M4), `std_file`/`std_time`/`std_io.print`, `extern "c"` `termios`/`signal`.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m4-audio-out-plan.md`. NEXT: `2026-10-11-z9play-m6-win9x-plan.md`.

## Global Constraints

Same as prior milestones: example-only `examples/z98/z9play/**`; no compiler change; Z98 rules (NOTE 2026-10-11: compiler defects D1–D6 are FIXED in seed v97 — no workarounds needed); build `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m5-cli-plan/`.

## File Structure

- `examples/z98/z9play/fmt.zig` — minimal integer/`mm:ss`/status-line formatter (player-local; no std change).
- `examples/z98/z9play/platform/console_linux.zig` — `termios` raw mode + `readKey` (non-blocking) + ANSI-free (CLI uses only `\r`).
- `examples/z98/z9play/cli.zig` / `main.zig` — arg parse + playback loop.
- `examples/z98/z9play/tests/tier_cli.sh`.

---

### Task 0: Preflight

- [ ] Confirm env: `script` (pty) available for key tests; `termios` usable; the playback tests use the WAV sink (no `/dev/dsp`). Confirm M4's `Player` API from its Task 6 review.

### Task 1: Formatter (`fmt.zig`)

**Interfaces:** `pub fn mmss(buf: []u8, ms: u64) []const u8` (e.g. `03:15`); `pub fn statusLine(buf, pos_ms, dur_ms, vol) []const u8` → `00:42 / 03:15  vol 80%  [########------------]` (fixed width, `\r`-ready).
- [ ] Unit test: exact byte output for fixed inputs (incl. `--` guard when duration is 0). Implement. PASS. Commit `example(z9play): CLI status formatter`.

### Task 2: Raw key input (Linux)

**Interfaces:** `pub fn termEnterRaw(state: *TermState) void`; `pub fn termLeaveRaw(state) void`; `pub fn readKey() ?Key` (non-blocking, no echo); `Key = union(enum){ char: u8, sigint }`.
- [ ] Unit test (via pty, `script`): entering raw mode disables echo; a written key is read back; `termLeaveRaw` restores. Implement. PASS. Commit `example(z9play): Linux raw console input`.

### Task 3: Playback loop + exit codes

**Interfaces:** `main(argc, argv)`: parse `--volume/--start/--loop/--quiet/--version/--help`; open decoder + audio (sink for tests / OSS on host); startup metadata line; per-second status (unless `--quiet`); keys: space pause/resume, `+`/`-` volume ±5, `q`/Ctrl-C quit; on exit `Stopped at mm:ss.`; exit codes 0 ok / 1 arg / 2 open / 3 decoder / 4 audio / 5 internal.
- [ ] Implement. Manual smoke on host (OSS absent → exit 4 path; sink path completes). Commit `example(z9play): CLI playback loop + keys`.

### Task 4: `tier_cli.sh`

- [ ] Build `-fsafe`; drive the CLI under a pty (`script`) into the WAV sink: assert the startup line, a per-second status line appears, `q`/Ctrl-C stops cleanly (exit 0), a bad flag → exit 1, a missing file → exit 2, a non-OGG → exit 3, `--quiet` suppresses the status line. Non-vacuous. Run PASS. Commit `example(z9play): M5 CLI tier`.

**Gate:** `tier_cli.sh` green; exit codes exact; `--dump-c89` md5 recorded.

### Task 5: Docs + commit

- [ ] Update `NOTES.md`/`README.md` (CLI usage, build recipe, md5). Commit `docs(z9play): M5 CLI`.

### Task 6: Next-milestone amendment review (M6)

- [ ] Read `2026-10-11-z9play-m6-win9x-plan.md`. Judge whether M5's console/CLI split (Linux `termios` backend, `readKey`, formatter) maps cleanly onto M6's Win9x console/`waveOut` requirements, or whether the console vtable shape must change first (e.g., the CLI now needs a minimal `Console` contract that M6/M7 share). If an amendment is required, **STOP-present** it; else record "no amendment needed".

**Gate:** approved M6 amendment or justified "no amendment needed".
