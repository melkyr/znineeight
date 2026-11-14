# M9 Task 5 report — streaming TUI playback

**Status:** DONE — gate PASS, no STOP condition.

**Base:** branch `zig1_improvements`, pre-task HEAD `14b353d0`
(`docs(sdd): M9 T4 ledger`).

**Seed:** `/tmp/m7_t5_seed2/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`, seed v102 fixed point).

**Code commit:** `71aabc63` `example(z9play): stream TUI playback`
(1 file, 60 insertions, 29 deletions).

**Scope:** only `examples/z98/z9play/ui.zig` changed. No
`main.zig`/`player.zig`/stream module changes, no compiler/stdlib/seed/plan
changes. `run.err`, `lin_bin/`, and `progress.md` were not touched.

---

## 1. Implementation

### 1.1 Arena replacement

`g_file_buf`/`g_file_arena` (4 MiB) is gone. It is replaced by
`g_stream_buf`/`g_stream_arena` (2 MiB), which covers:

- `BufferedFile` read buffer: 64 KiB
- OGG page buffer: 64 KiB
- OGG packet assembly buffer: 1 MiB
- comment/vendor/tag copies
- slack

`g_dec_arena`, `g_scratch_arena`, and `g_player_arena` are unchanged and
still initialized/reset exactly as before. The stream arena is reset only
after `stopPlayback()` has closed the live stream.

### 1.2 Container detection without `readAll`

`playTrack` opens a `stream.BufferedFile` in the stream arena, reads up to four
bytes, calls `decoder.detectKind`, closes the probe, then dispatches to the
codec stream. A failed probe reports `cannot open track` (or `out of memory`);
the probe handle is closed on the read-failure path.

### 1.3 Per-track stream state and lifetime

State is now:

```zig
var g_flac: flac.StreamFlacDecoder = undefined;
var g_ogg_stream: ogg_stream.OggStream = undefined;
var g_stream_open: bool = false;
var g_stream_is_flac: bool = false;
```

`closeStream()` is idempotent (`g_stream_open` guard) and dispatches to
`flac.closeStream` or `oggStreamClose`. `stopPlayback()` calls `closeStream()`
first, then drains/closes the audio backend if a track is active. Track changes
and `q` therefore close before any arena reset.

Failure paths in `playTrack` close through `stopPlayback()` as before. The open
paths mark `g_stream_open` only after a successful open.

### 1.4 Codec paths

- **OGG:** `oggStreamOpen` in the stream arena; ID/comment/setup headers are
  consumed from the stream; `oggStreamLastGranule` supplies duration;
  `VorbisCtx` borrows `g_ogg_stream`. Comment/tag copies use the stream arena.
- **FLAC:** `flac.openStream` in the decode arena (unchanged from T3). This
  arena also owns the decoder's fixed `channels * max_block` sample scratch, as
  required by spec §3; the stream handle is stored in `g_flac` and closed by
  `closeStream`. Keeping FLAC scratch in the 16 MiB decode arena avoids forcing
  worst-case FLAC block scratch into the 2 MiB stream arena.
- **Status:** OOM is reported as `out of memory`; non-OOM open failures keep
  `cannot open track`, `not an OGG Vorbis stream`, or
  `corrupt or unsupported FLAC stream`. Layout/keys/status text are otherwise
  unchanged.

### 1.5 `d` key

`d` still removes the current entry from the playlist. It closes the stream:
while playing/paused it calls `stopPlayback()` (close + stop), and after
Ended/Stopped it calls `closeStream()` only, preserving the existing now-playing
/playlist display so the TUI behavior remains unchanged. The `Now:` and
`Playlist:` rendering is untouched.

---

## 2. Commands and results

### 2.1 Seed

```text
$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
```

### 2.2 `tier_tui` (binding gate)

```text
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_tui_t5 \
      sh examples/z98/z9play/tests/tier_tui.sh
...
== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
rc=0
```

The existing pty checks already play `short.ogg`, observe `Now: a.ogg`,
`State: Playing`, and `State: Ended`, and validate the exact 26,504-byte WAV
payload. New stable `--dump-c89` pin for `ui.zig`:
`76d0fc83121892118089b10c6b66bb41` (twice), with `-fsafe` Linux build and the
Win9x `-osw` PE/import gate both passing.

### 2.3 Repeated play/stop + FLAC/OGG pty check

A disposable pty driver played a generated `sine_stereo_44100.flac` fixture,
replayed it five times, then changed tracks to `short.ogg`, and finally checked
`d`. It counted `/proc/<pid>/fd` after each Ended state.

```text
$ timeout 900 python3 /tmp/t5_playcheck/driver.py \
      /tmp/z9play_tier_tui_t5/z9play-tui \
      /tmp/t5_playcheck/scratch /tmp/t5_playcheck/tui.log \
      /tmp/t5_playcheck/out.wav
CHECK flac-now=1
CHECK flac-playing=1
CHECK flac-ended=1
FD flac=5
CHECK replay-0-ended=1
...
CHECK replay-4-ended=1
FD replays=5,5,5,5,5,5
CHECK replay-fds-stable=1
CHECK ogg-now=1
CHECK ogg-playing=1
CHECK ogg-ended=1
FD ogg=5
CHECK ogg-fd-stable=1
CHECK ogg-remove-counts-zero=1
FD before-d=5 after-d=4
CHECK d-closes-stream-fd=1
CHECK q-rc0=1
DRIVER_DONE=1
DRIVER_CHECKS total=27 passed=27 failed=0
rc=0
```

The stable descriptor count across six FLAC opens and the FLAC→OGG track change
shows no file-handle leak; `d` closes the ended track's stream descriptor while
leaving the UI state intact. `q` exits 0.

### 2.4 No production whole-file calls in the TUI

```text
$ grep -n "readAll\|reassemble\|ogg\.lastGranule\|flac\.open(" \
      examples/z98/z9play/ui.zig
NO_WHOLE_FILE_CALLS
```

---

## 3. Concerns

1. **FLAC scratch arena.** `flac.openStream` takes one arena for both the
   `BufferedFile` and fixed sample scratch. T5 keeps the existing decode-arena
   call (16 MiB) rather than splitting that API; the stream handle still lives
   in `g_flac` and closes through `g_stream_open`.
2. **`d` on an active track.** Removing the current playlist entry while
   playing/paused stops playback (stream closed); after Ended it closes the
   stream but preserves the existing now-playing/playlist display. This is the
   minimum change that satisfies “close on d” without changing the TUI layout.
3. **Worst-case comment size.** The 2 MiB stream arena matches `main.zig`’s
   streaming budget. A pathological near-1 MiB comment packet plus copied tags
   could exhaust it; such a track reports `bad Vorbis comment header`/OOM
   instead of playing. Committed fixtures are far smaller.
4. **Win9x hardware verification** remains operator-pending; the `-osw`
   emit/link and PE/import checks pass inside `tier_tui`.
