# M8 Task 2 report — native FLAC stream + frame decode

**Status:** COMPLETE.

**Commit (a):** `07d9239357aa2d6fefea60947578dc7bd98ec906` —
`example(z9play): native FLAC decoder`

**Seed:** v102 `/tmp/z9play_seed/zig1_5_clean`
(`b299b4b435e624d0ddbd2edde681cbc3`); archive
`release/seed/zig1-seed.tgz` md5 `702f34d87b7e6bf401dd206d2517dbee`
(unchanged).

## FLAC implementation (`examples/z98/z9play/flac.zig`)

- `open(arena, bytes) !FlacDecoder` verifies the `fLaC` marker, walks every
  metadata block, requires `STREAMINFO`, and records min/max block size, sample
  rate, channels, bits/sample and total samples. `pos` is left at the first
  audio frame; no metadata block is ever returned as audio.
- `decode(d, arena, out) !usize` decodes one frame:
  - frame header sync `0x3FFE`, reserved bits, blocking strategy, block-size /
    sample-rate / channel-assignment / sample-size codes, optional 8/16-bit
    block-size and sample-rate fields, UTF-8-style coded number, and **CRC-8
    verified** over the header;
  - subframes: constant, verbatim, fixed order 0–4, and LPC order 1–32
    (precision, signed shift, coefficients, warm-up samples);
  - partitioned Rice residuals (method 0/1, 4/5-bit parameters, escape/raw
    form, signed folding) and predictor reconstruction;
  - wasted-bit restoration after prediction;
  - channel decorrelation independent / left-side / right-side / mid-side;
  - interleaved signed-16 output with saturation, returning the frame count
    and 0 at end of stream.
- CRC-16 is skipped (the plan permits skip/verify). The decoder allocates one
  `max_block * channels` i64 scratch block in `open`, reset per frame in place,
  so a long stream does not grow the arena.
- `FlacDecoder` exposes `max_frames`, `sample_rate`, `channels`,
  `total_frames`, plus the decode cursor/scratch.

## Selector / main / ui wiring

- `decoder.zig`: `detectKind` checks `OggS` / `fLaC` signatures; the FLAC arm is
  now `FlacDecoder { fd: *flac.FlacDecoder }`, with `decoderOpenFlac(out, fd)`
  filling the caller-owned `player.Decoder` out-param (no return-by-value
  vtable; D8 shape preserved). `flacNext` adapts `flac.decode` to
  `player.DecoderError` (`OutOfMemory` preserved, other errors →
  `DecodeFailed`).
- `main.zig`: detection happens before OGG reassembly. `--wav` and interactive
  play select FLAC vs Vorbis through `decoder.zig`; rate/channels/total frames
  (and duration) come from STREAMINFO. OGG paths are byte-for-byte the previous
  parsing/decoder construction. `--info` / `--dump-setup` / `--pcm` remain
  Vorbis-only per the T2 scope (a FLAC input is rejected with the existing
  "not an OGG Vorbis stream" exit 3).
- `ui.zig`: `playTrack` selects by signature, stores the FLAC context in the
  module-global `g_flac` (so the Player's ctx pointer outlives `playTrack`), and
  feeds STREAMINFO rate/channels to the backend/Player. FLAC tags are not
  required for T2 and remain unset.
- No `player.zig`, compiler, std or seed change.

## Fixture / tool

`tests/get_flac_tools.sh` mirrors `get_vorbis_tools.sh`: private apt state/cache,
`apt-get --download-only --no-install-recommends flac`, `dpkg-deb -x`, then
reports the runnable binary + `LD_LIBRARY_PATH`.

```
$ TMP=/tmp/z9play_flac_tools sh examples/z98/z9play/tests/get_flac_tools.sh
flac: /tmp/z9play_flac_tools/sys/usr/bin/flac
LD_LIBRARY_PATH: /tmp/z9play_flac_tools/sys/etc:/tmp/z9play_flac_tools/sys/lib/x86_64-linux-gnu:/tmp/z9play_flac_tools/sys/lib64:/tmp/z9play_flac_tools/sys/usr/lib/x86_64-linux-gnu:/tmp/z9play_flac_tools/sys/usr/lib/x86_64-linux-gnu/gconv:
flac_version: flac 1.4.2
```

Fixture generated from the existing raw golden (not committed; the T2 touch
set excludes fixtures, so it lives under `/tmp` for these gates):

```
$ .../flac -f --force-raw-format --endian=little --sign=signed \
    --channels=2 --bps=16 --sample-rate=44100 \
    -o /tmp/z9play_t2_fixture/sine_stereo_44100.flac \
    examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
sine_stereo_44100.pcm: wrote 74017 bytes, ratio=0.210
$ wc -c /tmp/z9play_t2_fixture/sine_stereo_44100.flac
74017 /tmp/z9play_t2_fixture/sine_stereo_44100.flac
```

## Gates (command + observed output)

### `-fsafe` compile/build (seed v102)

```
$ timeout 180 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_t2_ftest \
      examples/z98/z9play/tests/flac_test.zig
emit_rc=0
$ sh /tmp/z9play_t2_ftest/build_target.sh linux /tmp/z9play_t2_ftest/prog
Built: /tmp/z9play_t2_ftest/prog
build_rc=0

$ timeout 180 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_t2_main \
      examples/z98/z9play/main.zig
main_emit_rc=0
$ sh /tmp/z9play_t2_main/build_target.sh linux /tmp/z9play_t2_main/prog
Built: /tmp/z9play_t2_main/prog
main_build_rc=0

$ timeout 180 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_t2_ui \
      examples/z98/z9play/ui.zig
ui_emit_rc=0
$ sh /tmp/z9play_t2_ui/build_target.sh linux /tmp/z9play_t2_ui/prog
Built: /tmp/z9play_t2_ui/prog
ui_build_rc=0
```

### Unit decode + 3× determinism

```
$ /tmp/z9play_t2_ftest/prog /tmp/z9play_t2_fixture/sine_stereo_44100.flac \
      examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
flac_test: PASS frames=88200 golden=88200 max_delta=0 sha1=0e31277ffee2bd62a707fc9732e9eb7281da58df
flac_test_rc=0
```

FLAC is lossless, so the match is exact (max |delta| = 0); the harness also
performs the three reset-arena decode passes and requires identical SHA-1.

### Player path (`--wav`) and interactive path

```
$ /tmp/z9play_t2_main/prog --wav /tmp/z9play_t2_fixture/sine_stereo_44100.flac \
      /tmp/z9play_t2_main/flac.wav
wav: ended frames=88200 pos_ms=2000 monotonic=1
wav_rc=0
$ wc -c /tmp/z9play_t2_main/flac.wav
352844 /tmp/z9play_t2_main/flac.wav
$ tail -c +45 /tmp/z9play_t2_main/flac.wav > /tmp/z9play_t2_main/flac.pcm
$ cmp /tmp/z9play_t2_main/flac.pcm \
      examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
cmp_rc=0

$ Z9PLAY_WAV_OUT=/tmp/z9play_t2_main/play100.wav \
    /tmp/z9play_t2_main/prog /tmp/z9play_t2_fixture/sine_stereo_44100.flac \
    --quiet --volume 100
z9play: /tmp/z9play_t2_fixture/sine_stereo_44100.flac  00:02  2ch 44100Hz

Stopped at 00:02.
play100_rc=0
$ tail -c +45 /tmp/z9play_t2_main/play100.wav > /tmp/z9play_t2_main/play100.pcm
$ cmp /tmp/z9play_t2_main/play100.pcm \
      examples/z98/z9play/testdata/expected/sine_stereo_44100.pcm
play100_cmp_rc=0
```

### Existing tiers (OGG behavior)

```
$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_cli.sh
== tier_cli summary: 23 passed, 0 failed ==
TIER_CLI PASS
tier_cli_rc=0

$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_tui.sh
== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS
tier_tui_rc=0

$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_audio.sh
== tier_audio summary: 27 passed, 0 failed ==
TIER_AUDIO PASS
tier_audio_rc=0

$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_info.sh
== tier_info summary: 20 passed, 0 failed ==
TIER_INFO PASS
tier_info_rc=0

$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_setup.sh
== tier_setup summary: 21 passed, 0 failed ==
TIER_SETUP PASS
tier_setup_rc=0
```

### Win9x compile/build + import gate

```
$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_win9x.sh
ok   - emitted mingw recipe is 9x no-CRT (DZIG_NO_CRT, nostdlib, kernel32+winmm)
ok   - file: .../z9play.exe: PE32 executable (console) Intel 80386 ... 7 sections
ok   - imports are exactly KERNEL32 + WINMM (no msvcrt)
ok   - check_win9x_imports.sh 9x whitelist PASS
== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
TIER_WIN9X PASS
tier_win9x_rc=0
```

`tier_tui.sh` also emitted/built the `ui.zig` root for `-osw`:

```
ok   - ui.zig -osw emit produced build_target.sh (default 9x no-CRT)
imports: KERNEL32.DLL WINMM.DLL
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
note: real Win98/Me hardware verification is operator-pending (not claimed)
```

### `--dump-c89` old → new (record only)

Measured from a pristine `git archive HEAD` copy at the same relative entry
paths with seed v102 (the old values reproduce the T1 report):

| root | old md5 (HEAD before T2) | new md5 |
|---|---|---|
| `main.zig` | `1a0e54402c2625dfbbb338ea65084486` | `e56af7916edd199e796f3ef11d5e49c4` |
| `ui.zig` | `38e4e1ca2346ae0f3578d737306155a6` | `22676fd997471df1c4c3a3f04397121d` |

Both new values were stable across the tiers' 2× checks. The move is expected
from the FLAC arm/selector wiring (module content change), not an OGG behavior
change.

### Diff scope

```
$ git show --stat --oneline HEAD
07d92393 example(z9play): native FLAC decoder
 examples/z98/z9play/decoder.zig             |  59 ++-
 examples/z98/z9play/flac.zig                | 565 ++++++++++++++++++++++++++++
 examples/z98/z9play/main.zig                | 250 ++++++-----
 examples/z98/z9play/tests/flac_test.zig     | 189 ++++++++++
 examples/z98/z9play/tests/get_flac_tools.sh |  71 ++++
 examples/z98/z9play/ui.zig                  | 103 +++--
 6 files changed, 1097 insertions(+), 140 deletions(-)
```

Only authorized files changed. `player.zig`, compiler/std, seed, `NOTES.md`,
`README.md` untouched. `run.err` left untracked/untouched; `progress.md` left
dirty/untouched.

## Concerns

- Frame CRC-16 is read but not verified (explicitly allowed by the plan); the
  header CRC-8 is verified.
- T2 routes only `--wav` and interactive playback to FLAC. `--info`,
  `--dump-setup` and `--pcm` remain Vorbis-only per the context scope; FLAC
  title/comment tags are optional for T2 and not parsed.
- The generated `.flac` fixture is not committed (T2 touch set excludes it).
  T3's `tier_flac.sh` should regenerate it with `get_flac_tools.sh` using the
  exact command in this report.
- Win9x is emission/build/import-gated only; no hardware claim.
