# M7 Task 3 report — TUI (`ui.zig`)

**Status:** DONE — `ui.zig` implemented as a separate root, all required gates pass.

**Base:** branch `zig1_improvements`, prior head `5bd40ba7`.
**Seed:** v101 rebuilt `zig1_5_clean` at `/tmp/m7_t1_seed` (fixed point
`b299b4b435e624d0ddbd2edde681cbc3`).
**Code commit:** `74d8c785` `example(z9play): TUI frontend` (only
`examples/z98/z9play/ui.zig`).

---

## Implement

### Layout (80x25, pinned)

- `ui.zig` is a separate root with `pub fn main(argc: i32, argv: [*][*]u8) void`
  (same signature as `main.zig`). No `--tui` flag and no `main.zig`/`cli.zig`
  edit.
- Layout is hard-pinned to 80x25, independent of `Console.width`/`height`, so
  the Win9x `dwSize` vs `srWindow` distinction cannot move the panes: top
  border row 0, content rows 1–20, separator 21, two help rows 22–23, bottom
  border 24. Left directory pane cols 1–43, separator col 44, right
  now-playing pane cols 45–78, border col 79. All content writes are clipped so
  long paths/titles cannot overwrite a border or the opposite pane.
- Starts browsing `getcwd` (`std.os.cwd`), copied into a 4096-byte path buffer
  before the per-directory arena is reset.

### Directory pane

- Streaming `std_file.openDir/readDir/closeDir` (T1 API) with a per-load
  arena reset; names stay caller-arena-owned.
- Filters to directories plus `.ogg`/`.flac` files (case-insensitive suffix);
  skips OS `.`/`..`; synthesizes `..` at the top when not at root.
- Sorts directories first, then files, alphabetical within each (insertion
  sort, no new std dependency).
- Cursor navigation: `up`/`down` arrows and `j`/`k`; Enter on a file plays it,
  Enter on a directory enters it, Enter on `..` goes up. Scrolls to keep the
  selected row visible.

### Now-playing pane and playlist

- Shows `No track` before playback. With a current track: `Now: <filename>`,
  elapsed / duration, `vol N%`, a 20-cell progress bar, title/artist/album
  metadata when present, player state (`Playing`/`Paused`/`Ended`/`Error`),
  playlist count, and a status line for errors/actions.
- In-memory playlist (`PLAYLIST_MAX = 256`, paths allocated from the UI arena):
  `a` adds the selected file (duplicates skipped), `d` removes the current
  track from the playlist, `n`/`p` move to the next/previous playlist item and
  play it. Entering a file directly also makes it the current playlist item
  when it is already in the list.
- Key set exactly per plan: `up/down` or `j/k`, Enter, `a`, `d`, `n`, `p`,
  Space pause/resume, `+`/`-` volume (5-step, clamped 0–100), `q` quit,
  Ctrl-C (`.sigint`) quit. No `s`, mouse, color, or on-disk playlist.

### Playback wiring

- Reuses `Player` + `VorbisCtx`/`Decoder` + `AudioOut` exactly as M4/M5:
  `readAll` -> `ogg.reassemble` -> id/comment/setup -> `initDecoderState` ->
  `vorbisCreate` -> `Decoder` literal -> `playerInit`.
- Sink selection mirrors M5: `Z9PLAY_WAV_OUT` -> `audio_wavfile.zig`, else
  `@isWindows()` -> `audio_win9x.zig`, explicit `else` -> `audio_oss.zig`.
  The final else is a comptime-dead branch under `-osw`, so OSS is not emitted
  into the Win9x build.
- Volume wrapper scales interleaved s16 by `sample*vol/100` before the real
  sink, and `Player.volume` is also updated on `+`/`-`.
- Event loop is non-blocking (`readKey` returns `.none`), pumps the player
  against `std.time.ticksMs()` pacing, sleeps 10 ms when caught up (no 100%
  spin), and re-renders on key/state change or every 250 ms.
- Track open/parse/decode failure sets a status message and leaves the TUI
  running. Track end shows `Ended`; it does not auto-advance.
- Cleanup: every normal exit drains/closes the audio sink, calls
  `leaveRaw_fn`, shows the cursor (`cursorShow_fn(true)`), clears the screen,
  then `std.os.exit(0)`. There are no other `std.os.exit` paths after raw mode.

---

## Gates

### 1. Compile `-fsafe` and build emitted C (Linux)

```bash
rm -rf /tmp/m7_t3_final && mkdir -p /tmp/m7_t3_final
timeout 120 /tmp/m7_t1_seed/zig1_5_clean -fsafe -o /tmp/m7_t3_final \
    examples/z98/z9play/ui.zig
sh /tmp/m7_t3_final/build_target.sh linux /tmp/m7_t3_final/z9play-tui
```

Observed:

```text
compile_rc=0
Built: /tmp/m7_t3_final/z9play-tui
build_rc=0
```

### 2. pty smoke — first render, `q`, exit, terminal restored

Driver: Python `pty.fork`, wait for first render, send `q`, wait for exit,
compare `tcgetattr` before/after.

```bash
python3 /tmp/m7_t3/smoke.py /tmp/m7_t3_final/z9play-tui \
    /tmp/m7_t3/scratch 'q' 'z9play' 6
```

Observed:

```text
SAW=1 RC=0 TERMIOS_RESTORED=1 OUT_BYTES=8690
```

First rendered screen (ANSI stripped) included the fixed 80x25 frame, the
scratch path, sorted listing (`..`, `sub/`, `a.ogg`, `b.ogg`), `No track`,
and both help rows.

Additional pty checks (same binary):

```text
dir navigation (Enter on sub, Enter on ..): path showed /tmp/m7_t3/scratch/sub then back
playlist/volume: added to playlist=1, Playlist: 1=1, Now: b.ogg=1,
                 removed from playlist=1, Playlist: 0=1, vol 75%=1, vol 80%=1
WAV sink playback: RC=0 WAV_SIZE=88364 TERMIOS_RESTORED=1
```

### 3. Touch set

```bash
git add examples/z98/z9play/ui.zig
git diff --cached --stat
git diff --cached --name-only
```

Observed:

```text
 examples/z98/z9play/ui.zig | 1140 ++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 1140 insertions(+)
examples/z98/z9play/ui.zig
```

`run.err` remains untracked and untouched; no other source/platform/std/compiler
files were changed.

### 4. Win9x compile-only check (T4 owns the Win9x gate)

```bash
timeout 120 /tmp/m7_t1_seed/zig1_5_clean -osw -o /tmp/m7_t3_final_win \
    examples/z98/z9play/ui.zig
sh /tmp/m7_t3_final_win/build_target.sh mingw /tmp/m7_t3_final_win/prog.exe
bash scripts/win32_cross/check_win9x_imports.sh /tmp/m7_t3_final_win/prog.exe 9x
```

Observed:

```text
win_compile_rc=0
Built: /tmp/m7_t3_final_win/prog.exe
win_build_rc=0
DLL KERNEL32.DLL
DLL WINMM.DLL
IMPORT GATE PASS (9x): /tmp/m7_t3_final_win/prog.exe
import_gate_rc=0
```

PE32/i386, imports only KERNEL32 + WINMM (no msvcrt). Real Win98/Me hardware
verification remains operator-pending and is not claimed here.

---

## Concerns

1. **WAV sink lifetime across tracks.** `audio_wavfile.zig` has one global
   path/context. `n`/`p` (or entering another file) closes the previous sink
   and reopens the same `Z9PLAY_WAV_OUT` path, which truncates the prior file.
   This is inherited sink behavior, not a TUI regression; a single-track
   Enter-play run produces a complete WAV (observed 88364 bytes).
2. **Debug-build decode speed.** The emitted `-O0 -fsafe` C decodes slower than
   real time on this host; a short wall-clock wait may show only partial
   progress/WAV data even though the player is advancing correctly. T4's tier
   should allow enough time (or pump to `Ended`) rather than assume real-time
   completion.
3. **No playlist pane/cursor.** The blueprint only draws the directory and
   now-playing panes; `d` therefore removes the *current* track from the
   playlist (first matching path), which is the plan's "selected playlist item"
   interpretation in the absence of a separate playlist selection.
4. **Non-tty stdin.** As with M5, raw mode is a no-op when stdin is not a tty;
   the TUI still runs non-blocking but has no way to receive `q`. The required
   smoke uses a pty.
5. **Win9x is compile/import-only here.** Behavior on Win98/Me (especially
   80x25 conhost rendering) is design-verified, hardware verification pending,
   per T4 and Amendment 1.
