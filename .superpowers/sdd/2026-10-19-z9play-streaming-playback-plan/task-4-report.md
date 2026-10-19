# M9 Task 4 report — stream-backed Vorbis + all CLI modes

**Status:** DONE — gate PASS, no STOP condition.

**Base:** branch `zig1_improvements`, pre-task HEAD `72da9ff8`
(`docs(plan): M9 T4 sequencing — minimal UI Vorbis switch`).

**Seed:** `/tmp/m7_t5_seed2/zig1_5_clean`
(md5 `b299b4b435e624d0ddbd2edde681cbc3`).

**Code commit:** `4d88f4d2` `example(z9play): stream CLI modes`
(4 files, 480 insertions, 195 deletions).

**Scope:** only the four Task 4 files changed:

- `examples/z98/z9play/player.zig`
- `examples/z98/z9play/main.zig`
- `examples/z98/z9play/ui.zig` (authorized minimal Vorbis call-site switch)
- `examples/z98/z9play/tests/player_test.zig`

No compiler/stdlib/seed/plan/spec changes. `run.err`, `lin_bin/`, and
`progress.md` untouched.

---

## 1. Interface (spec §4.3 / §4.5)

`player.VorbisCtx` is now the stream-backed shape:

```zig
pub const VorbisCtx = struct {
    scratch: *std.arena.Arena,
    setup: vs.Setup,
    state: dec.DecoderState,
    stream: *ogg_stream.OggStream,
    tmp: []i16,
    max_frames: u32,
    sample_rate: u32,
    channels: u8,
    total_frames: u64,
};

pub fn vorbisCreate(
    persistent: *std.arena.Arena,
    scratch: *std.arena.Arena,
    stream: *ogg_stream.OggStream,
    setup: vs.Setup,
    state: dec.DecoderState,
    sample_rate: u32,
    channels: u8,
    total_frames: u64,
) DecoderError!*VorbisCtx;
```

`vorbisNext` calls `oggStreamNextPacket(c.stream)`, resets the scratch arena
per packet, decodes with the unchanged `dec.decodePacket`, and returns 0 at
clean EOF. `PacketTooLarge`, CRC, truncated-stream and other `OggStream`
failures map to `DecoderError.DecodeFailed`; `OutOfMemory` is preserved.
`decoder.decoderOpenVorbis(out, vc)` is unchanged in shape.

---

## 2. Implementation decisions

- **Container detection.** `main.zig` opens a `BufferedFile`, reads four bytes,
  calls `detectKind`, closes the probe stream, and dispatches. Each mode then
  opens the codec's streaming reader; there is no `readAll` in `main.zig`.
- **Shared header helper.** `readOggHeaders` consumes exactly the three
  Vorbis header packets once per stream, parses only the requested header
  (ID/comment/setup), and closes the stream before every failure exit.
- **`--info`.** Streams the three headers, parses ID + comment, closes the
  decode stream, then uses `oggStreamLastGranule(arena, path, serial)` for
  duration. Audio is never decoded.
- **`--dump-setup`.** Streams the three headers, parses only the setup packet,
  prints the existing golden line, and exits without reading audio.
- **`--pcm`.** Opens the output with `filemod.open(..., .Write)`, writes the
  canonical 44-byte WAV header with zero size fields, decodes packet by packet,
  writes little-endian s16 incrementally, then seeks to offsets 4 and 40 and
  writes exactly four bytes at each. Payload size is capped at
  `0xFFFFFFFF - 36`; larger output exits 3 explicitly. The output file and
  decode stream are closed on every decode/write failure path.
- **Granule trimming.** `--pcm` still writes only the first `last` frames when
  the tail scan yields a positive granule, while continuing to decode the
  remaining packets so late corruption is still reported. A zero granule keeps
  the old "write all decoded frames" behavior.
- **`--wav` / interactive.** OGG creates a stream-backed `VorbisCtx`; FLAC keeps
  the Task 3 `flac.openStream` path. The `Player` and audio layer are
  unchanged.
- **`--loop` lifetime.** Interactive OGG passes use a dedicated, reset-able
  `stream_arena_buf`; the stream/context/player live for exactly one pass and
  are closed before the next pass resets that arena. Metadata comment copies
  remain in the persistent `arena`.
- **Minimal UI switch.** `ui.zig` opens `ogg_stream.OggStream` for OGG,
  consumes the three headers, tail-scans the granule, creates the stream-backed
  `VorbisCtx`, stores the stream in `g_ogg`, and closes it in `stopPlayback`
  and on the new failure paths. `readAll`, the file arena, and the FLAC path
  remain for Task 5.

---

## 3. Commands and results

### 3.1 Seed

```text
$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
```

### 3.2 Builds

```text
$ /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o /tmp/m9t4_main \
      examples/z98/z9play/main.zig
$ sh /tmp/m9t4_main/build_target.sh linux /tmp/m9t4_main/prog

$ /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o /tmp/m9t4_ui \
      examples/z98/z9play/ui.zig

$ /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o /tmp/m9t4_ptest \
      examples/z98/z9play/tests/player_test.zig
$ sh /tmp/m9t4_ptest/build_target.sh linux /tmp/m9t4_ptest/prog
```

All compilations and target links return rc 0.

### 3.3 Player unit test (stream-backed producer)

```text
$ /tmp/m9t4_ptest/prog
player_test: PASS frames=88200 wav_bytes=352844 max_delta=1 \
    m3_pcm=byte_identical deterministic=2x
```

`player_test` now feeds the Player from `oggStreamNextPacket`; its payload is
byte-identical to the in-test M3 reference and remains within the existing
2-LSB libvorbis tolerance.

### 3.4 Required tiers

```text
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_info_t4 \
      sh examples/z98/z9play/tests/tier_info.sh
== tier_info summary: 20 passed, 0 failed ==
TIER_INFO PASS                         (rc=0)

$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_setup_t4 \
      sh examples/z98/z9play/tests/tier_setup.sh
== tier_setup summary: 21 passed, 0 failed ==
TIER_SETUP PASS                        (rc=0)

$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_cli_t4 \
      sh examples/z98/z9play/tests/tier_cli.sh
== tier_cli summary: 23 passed, 0 failed ==
TIER_CLI PASS                          (rc=0)

$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_tui_t4 \
      sh examples/z98/z9play/tests/tier_tui.sh
== tier_tui summary: 40 passed, 0 failed ==
TIER_TUI PASS                          (rc=0)

$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_audio_t4 \
      sh examples/z98/z9play/tests/tier_audio.sh
== tier_audio summary: 27 passed, 0 failed ==
TIER_AUDIO PASS                        (rc=0)
```

Additional regression runs:

```text
$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_decode_t4 \
      sh examples/z98/z9play/tests/tier_decode.sh
== tier_decode summary: 24 passed, 0 failed ==
TIER_DECODE PASS                       (rc=0)

$ ZIG=/tmp/m7_t5_seed2/zig1_5_clean OUT=/tmp/z9play_tier_flac_t4 \
      sh examples/z98/z9play/tests/tier_flac.sh
== tier_flac summary: 59 passed, 0 failed ==
TIER_FLAC PASS                         (rc=0)
```

### 3.5 `--pcm` byte comparison

The committed `testdata/expected/*.pcm` files are the libvorbis oracle and are
not byte-identical to this decoder by design (the existing gate allows
`max_delta <= 2`, observed 1 LSB). Byte-exactness was therefore checked
against the pre-task implementation's `--pcm` output:

```text
$ git archive HEAD examples/z98/z9play | tar -x -C /tmp/m9t4_old
$ /tmp/m7_t5_seed2/zig1_5_clean -fsafe -o /tmp/m9t4_old \
      examples/z98/z9play/main.zig
$ sh /tmp/m9t4_old/build_target.sh linux /tmp/m9t4_old/prog
$ /tmp/m9t4_old/prog --pcm \
      /tmp/m9t4_old/examples/z98/z9play/testdata/sine_stereo_44100.ogg \
      /tmp/m9t4_old/out.wav

$ /tmp/m9t4_main/prog --pcm \
      examples/z98/z9play/testdata/sine_stereo_44100.ogg \
      /tmp/m9t4_main/out.wav

$ cmp /tmp/m9t4_old/out.wav /tmp/m9t4_main/out.wav
PCM_BYTE_IDENTICAL_TO_PRE_TASK
$ md5sum /tmp/m9t4_old/out.wav /tmp/m9t4_main/out.wav
e7f24870ec03b924be1b8e55a1962fb3  /tmp/m9t4_old/out.wav
e7f24870ec03b924be1b8e55a1962fb3  /tmp/m9t4_main/out.wav
```

The header size fields are patched correctly: the comparison inputs are both
352,844-byte WAVs (44-byte header + 352,800-byte payload).

### 3.6 No production whole-file calls in the CLI

```text
$ grep -n "readAll\|reassemble\|ogg\.lastGranule\|flac\.open(" \
      examples/z98/z9play/main.zig
NO_MEDIA_WHOLE_FILE_CALLS
```

`ui.zig` still contains `readAll` exactly as authorized for Task 5.

---

## 4. Concerns

1. **UI cleanup remains Task 5.** `ui.zig` still calls `readAll` for container
   detection and still has the 4 MiB file arena; only the OGG decoder path was
   switched. `g_ogg` lives in `g_dec_arena` and is closed before that arena is
   reset (Task 5 should move it to the dedicated stream arena).
2. **Committed PCM goldens are libvorbis fixtures, not this decoder's exact
   bytes.** The Task 4 byte-exact check therefore uses the pre-task `--pcm`
   output; the existing tolerance gate remains the committed-fixture check.
3. **Two OGG opens per interactive pass.** The metadata pass reads ID/comment
   and closes; each playback pass reopens the file and re-consumes the three
   headers. This is intentional so `--loop` can reset the stream arena while
   tag slices stay in the persistent arena.
4. **Win9x hardware verification** remains operator-pending; the `-osw`
   emit/link and PE/import checks pass inside `tier_flac`/`tier_tui`.
