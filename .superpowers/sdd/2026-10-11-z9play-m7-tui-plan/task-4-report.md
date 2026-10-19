# M7 Task 4 report — `tier_tui.sh`

**Status:** DONE — tier green twice; Win9x `-osw` gate green; no UI defect found.

**Base:** branch `zig1_improvements`, prior head `61b046d8`.
**Seed:** v101 `/tmp/m7_t1_seed/zig1_5_clean`, md5
`b299b4b435e624d0ddbd2edde681cbc3` (unchanged; verified by the tier).
**Code commit:** `7bc243d9` `example(z9play): M7 TUI tier` (only
`examples/z98/z9play/tests/tier_tui.sh`, mode 100755, 503 lines).

---

## Tier design

`examples/z98/z9play/tests/tier_tui.sh` is self-contained POSIX sh. It removes
`OUT` (default `/tmp/z9play_tier_tui`), resolves the v101 seed compiler (env
`ZIG`, then `/tmp/m7_t1_seed/zig1_5_clean`, then `/tmp/z9play_seed/...`; if none
exists it rebuilds from `release/seed/zig1-seed.tgz` via
`scripts/seed/build_from_seed.sh`), and checks the seed md5.

1. **Linux build.** `ui.zig` is compiled with the binding recipe
   `"$ZIG" -fsafe -o "$OUT" examples/z98/z9play/ui.zig` and linked through the
   emitted `build_target.sh linux`.
2. **Fresh scratch.** `$OUT/scratch` contains `sub/`, `a.ogg`, `b.ogg` (both
   copies of the 0.3 s `short.ogg` fixture: 26460 PCM bytes) and `notes.txt`
   (must be filtered). `Z9PLAY_WAV_OUT` points at `$OUT/tui.wav`.
3. **pty driver.** A Python `pty` helper is written into `$OUT/driver.py` (no
   repo artifact). It opens a pty, pins the window to 100x30, captures the
   original termios, forks/execs the TUI with cwd = scratch, and drives it only
   after the first full frame is observed. It emits `CHECK name=1|0` lines; the
   shell counts them into PASS/FAIL. The driver exits nonzero if any check fails.
4. **Checks (32).**
   - Frame: the first screen parses as exactly 25 rows x 80 columns with the
     pinned top/body/separator/bottom borders, the scratch path in the
     directory pane, `> ..`, `  sub/`, `a.ogg`, `b.ogg`, no `notes.txt`, and
     `No track` in the now-playing pane (and no `Now:`).
   - Raw mode: termios during the run differs from the pre-run capture and has
     `ECHO`/`ICANON` cleared (so the later restore check is non-vacuous).
   - Navigation: `j` changes `> ..` to `> sub/`, then to `> a.ogg`; the target
     marker is asserted absent before its key.
   - Playback: WAV is absent before Enter; Enter on `a.ogg` yields `Now: a.ogg`,
     `State: Playing`, then `State: Ended` with a 240 s timeout (no real-time
     assumption). At `Ended` the WAV is exactly 26504 bytes; after `q` the RIFF/
     `data` size fields are patched (26496 / 26460).
   - Playlist: before `a` the screen has `Playlist: 0` and no `Playlist: 1`;
     `a` shows `Playlist: 1` + `added to playlist` and no stale `0`; `d` shows
     `removed from playlist` and `Playlist: 0`.
   - Quit: `q` exits rc 0, the exact pre-run termios is restored, the cursor is
     shown (`ESC[?25h`) and the screen is cleared (`ESC[2J`).
5. **Win9x gate.** Emits `ui.zig` for default `-osw`, builds through the emitted
   `build_target.sh mingw`, asserts `file` reports PE32 Intel 80386, asserts no
   `MSVCRT` DLL import, and runs
   `scripts/win32_cross/check_win9x_imports.sh <exe> 9x`. Wine is not used.
6. **C89 dump.** `"$ZIG" --dump-c89 examples/z98/z9play/ui.zig` (single-file
   stdout recipe; verified it emits one 1.4 MB C file on stdout) is run twice and
   the md5 is recorded only when both runs agree.

Non-vacuity is explicit: exact 80-column frames/borders, absent-before-key
selection markers, WAV absent before Enter and exact after `Ended`, raw mode
observed active before restore, and playlist counts that must change 0→1→0.

---

## Gates

### Run 1

Command:

```bash
bash examples/z98/z9play/tests/tier_tui.sh
```

Observed (trimmed to the summary-relevant lines; full 40 checks all `ok`):

```text
== seed ==
compiler: /tmp/m7_t1_seed/zig1_5_clean
md5:      b299b4b435e624d0ddbd2edde681cbc3
ok   - seed v101 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3
ok   - ui.zig -fsafe compile + emitted build_target.sh linux
...
ok   - first-frame-25-rows
ok   - first-frame-80-cols
ok   - pane-borders-pinned
ok   - now-playing-shows-no-track
ok   - enterraw-active-during-run
ok   - nav-down-moves-to-subdir
ok   - nav-down-moves-to-ogg
ok   - enter-opens-ogg
ok   - play-state-playing
ok   - play-reaches-ended
ok   - wav-payload-complete-at-ended
ok   - playlist-add-counts-one
ok   - playlist-remove-counts-zero
ok   - q-exits-rc0
ok   - termios-restored-exactly
ok   - wav-size-fields-patched
driver: total=32 passed=32 failed=0
pty log: /tmp/z9play_tier_tui/tui.log (21686 bytes)
...
ok   - file: ...z9play-tui.exe: PE32 executable (console) Intel 80386 ...
imports: KERNEL32.DLL WINMM.DLL
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
--dump-c89 md5: e7bc57a2a38a72cb83f51a1ce7497239
ok   - --dump-c89 md5 recorded stable 2x: e7bc57a2a38a72cb83f51a1ce7497239

== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
```

Exit status: 0.

### Run 2 (stability)

Same command. Observed identical results:

```text
driver: total=32 passed=32 failed=0
pty log: /tmp/z9play_tier_tui/tui.log (21686 bytes)
ok   - check_win9x_imports.sh 9x whitelist PASS
--dump-c89 md5: e7bc57a2a38a72cb83f51a1ce7497239
ok   - --dump-c89 md5 recorded stable 2x: e7bc57a2a38a72cb83f51a1ce7497239

== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
```

Exit status: 0. Both runs rebuilt from scratch (`OUT` removed each time), so the
pty/WAV/exe results are not reused state.

---

## Win9x gate (Amendment 1)

```text
== Win9x gate: -osw TUI emit/build + PE/import check (Amendment 1) ==
ok   - ui.zig -osw emit produced build_target.sh (default 9x no-CRT)
ok   - emitted build_target.sh mingw produced exe (596571 bytes)
ok   - file: /tmp/z9play_tier_tui/z9play-tui.exe: PE32 executable (console) Intel 80386 (stripped to external PDB), for MS Windows, 7 sections
imports: KERNEL32.DLL WINMM.DLL
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
       DLL KERNEL32.DLL
       DLL WINMM.DLL
       IMPORT GATE PASS (9x): /tmp/z9play_tier_tui/z9play-tui.exe
note: real Win98/Me hardware verification is operator-pending (not claimed)
```

The build log contains only a harmless pre-existing `pal_strlen` warning from
the emitted C; the link succeeds. Real Win98/Me hardware behavior remains
operator-pending and is not claimed.

---

## Touch set / commit

```text
 examples/z98/z9play/tests/tier_tui.sh | 503 ++++++++++++++++++++++++++++++++++
 1 file changed, 503 insertions(+)
examples/z98/z9play/tests/tier_tui.sh
```

Commit `7bc243d9` contains only the new tier script (mode 100755). No
`ui.zig`/`main.zig`/`cli.zig`/platform/std/compiler edits. `run.err` remains
untracked and untouched; `run.out`/dirty `progress.md` were left alone.

---

## Concerns

1. **Inherited WAV sink lifetime (not a TUI defect).** `audio_wavfile.zig` has
   a single global sink; switching tracks reopens/truncates `Z9PLAY_WAV_OUT`.
   The tier plays exactly one track before asserting the payload, so this
   remains the T3 concern rather than a T4 failure.
2. **Debug decode speed.** The tier waits for the explicit `State: Ended` frame
   (240 s bound) and only then asserts the 26504-byte WAV; it does not assume
   real-time decode. `short.ogg` (0.3 s) keeps the gate fast while still
   exercising the real `Player` path.
3. **Win9x is compile/import-only here.** PE32/no-msvcrt/closed-world imports
   are proven, but 80x25 conhost rendering and raw-mode restore on real
   Win98/Me are design-verified only, pending operator hardware verification.
4. **No UI defect encountered.** No required assertion had to be weakened; all
   32 behavior checks are non-vacuous and pass twice.
