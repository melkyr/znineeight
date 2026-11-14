# M9 Task 7 report — final review and handoff

**Status:** PASS / handoff ready. No open Critical or Important findings. No push.

**Branch:** `zig1_improvements`
**Report HEAD at initial write:** `ee695a5b` (`docs(sdd): M9 T6 ledger`)
**Source-freeze commit:** `7a873812` (`fix(z9play): make_large_ogg sample-accurate granules`)

This is a report-only task. T7 did **not** perform a new authoritative
full-gate run; the operator explicitly asked to stop repeated reruns. The last
authoritative results are the T6 fix round and the T6 scoped re-review.
Incidental T7-era build/playback artifacts (for example
`/tmp/t7_tier_stream.log`, `/tmp/z9play_tier_stream/tiers/flac.log`, rebuilt
`lin_bin` binaries, and playback WAVs) are **not** gate evidence. **No source
changed after `7a873812`**:

```text
$ git diff --stat 7a873812..HEAD
 .../progress.md                                    |  3 +-
 .../task-6-report.md                               | 80 ++++++++++++++++++++++
 2 files changed, 82 insertions(+), 1 deletion(-)

$ git diff --name-only 7a873812..HEAD
.superpowers/sdd/2026-10-19-z9play-streaming-playback-plan/progress.md
.superpowers/sdd/2026-10-19-z9play-streaming-playback-plan/task-6-report.md
```

All post-freeze commits are documentation-only. The last source change was in
`7a873812`; the T6 fix-round gates and the scoped re-review ran after it, so
the cited results apply to the current tree.

## Environment / seed / operator files

- Build container: Linux x86_64, 32-bit `gcc` toolchain, Python 3.11,
  `script(1)`, Wine, and the FLAC toolchain for the existing tiers. It has no
  OSS `/dev/dsp` and no `aplay`.
- Seed archive: `release/seed/zig1-seed.tgz`
- Seed archive md5: `702f34d87b7e6bf401dd206d2517dbee` (v102)
- Seed fixed point: `/tmp/m7_t5_seed2/zig1_5_clean`
- Seed fixed-point md5: `b299b4b435e624d0ddbd2edde681cbc3` (v102, unchanged)
- Operator-provided OGG: `lin_bin/01. 霜月はるか — ユメノハテニ.ogg`,
  8,205,755 bytes (untracked; path/size as reported by the operator)
- Operator-provided FLAC: `lin_bin/01. Yofukashino Uta.flac`, 33,757,087 bytes
  (untracked; exact path/size as reported by the operator; not independently
  verified as gate evidence)
- `lin_bin/` is an untracked operator working directory, rebuilt/recreated for
  operator playback during M9. It is not a tracked artifact and is not part of
  any gate. `run.err` and `progress.md` were not modified by this task.

## M9 commit chain

| Task | Commits |
|---|---|
| T0 preflight | `e696392c`, truth-ups `16655f0e` |
| T1 `stream.zig` | `ecf2bcdd`, `e312c886` |
| T2 `ogg_stream.zig` | `dc11bc88`, `968fcc12` |
| T3 FLAC stream | `ad3d7313`, `a9dc1ecc` |
| T4 Vorbis + main modes | `4d88f4d2`, `1211759c`, fix `688b5c9d`, `45a112a9` |
| T5 TUI stream | `71aabc63`, `0ae9f9f6` |
| T6 large-file gate / docs | `72ca8efa`, `b7c548b9`, `b2446dc1`, fix `7a873812`, `1d12989c`, ledger `ee695a5b` |

## Read-only verification (commands and observed outputs)

### 1. Production frontends have no whole-file oracle path

Scanned the production frontends `main.zig`, `ui.zig`, `decoder.zig`,
`player.zig`, and `vorbis_info.zig`:

```text
$ grep -rn "readAll\|reassemble\|lastGranule\|flac\.open(" \
    examples/z98/z9play/main.zig examples/z98/z9play/ui.zig \
    examples/z98/z9play/decoder.zig examples/z98/z9play/player.zig \
    examples/z98/z9play/vorbis_info.zig
examples/z98/z9play/player.zig:25:// trims to `ogg.lastGranule`).
examples/z98/z9play/vorbis_info.zig:5:// reassembler in ogg.zig:
```

Only comments matched. There are **no production calls** to `readAll`,
`ogg.reassemble`, `ogg.lastGranule`, or `flac.open(arena, bytes)`.

The byte-slice functions remain definitions only, as the permitted test-only
oracles:

- `ogg.zig:157` `pub fn reassemble(...)`
- `ogg.zig:252` `pub fn lastGranule(...)`
- `flac.zig:38` `FlacDecoder`, `flac.zig:489` `pub fn open(...)`

Call sites are confined to `examples/z98/z9play/tests/**`, for example
`tests/decode_test.zig:101,109`, `tests/floor_test.zig:118,122`,
`tests/info_test.zig:69,73`, `tests/ogg_stream_test.zig:166,170,174`,
`tests/ogg_test.zig`, `tests/player_test.zig`, `tests/setup_test.zig`,
`tests/audio_test.zig:101`, and `tests/flac_test.zig:86,95`.

Production uses the streaming path:

```text
main.zig:  stream.bufferedFileOpen, ogg_stream.oggStreamOpen,
           ogg_stream.oggStreamLastGranule, flac.openStream
ui.zig:    stream.bufferedFileOpen, ogg_stream.oggStreamOpen,
           flac.openStream, and closeStream on every stop/change/quit path
decoder.zig: FlacDecoder wraps *flac.StreamFlacDecoder
```

### 2. No `sf/**` change

```text
$ git diff --stat 3c9659dd..HEAD -- 'sf/**'
(empty)

$ git log --oneline 3c9659dd..HEAD -- 'sf/**' | wc -l
0
```

No compiler, standard-library, or seed source changed across M9.

### 3. Seed v102 unchanged

```text
$ md5sum release/seed/zig1-seed.tgz
702f34d87b7e6bf401dd206d2517dbee  release/seed/zig1-seed.tgz

$ md5sum /tmp/m7_t5_seed2/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/m7_t5_seed2/zig1_5_clean
```

Both match the v102 values in the spec and ledger. No seed rebuild or rotation
was performed.

### 4. Console binary md5

```text
$ md5sum lin_bin/z9play-console
af1cef634dd7b885363bff2ec3582aff  lin_bin/z9play-console
```

The current untracked console is the M9 operator-playback rebuild. Its md5
matches the T6 rebuild and is byte-identical to the `ui.zig` binary built by
the T6 fix-round `tier_stream.sh` (`/tmp/z9play_tier_stream/ui/prog`). It is not
a tracked artifact and is not gate evidence.

### 5. Working tree

```text
$ git status --porcelain=v1
?? lin_bin/
?? run.err
```

At audit time these were the only untracked paths. `lin_bin/` is a non-gate
operator working directory and may be rebuilt or emptied by playback sessions;
it is never staged or treated as a tracked artifact. `run.err` is likewise left
out of the report commit.

## Gate evidence (last authoritative; T6 fix round)

From the T6 fix round after `7a873812`:

| Gate | Result |
|---|---|
| `tier_stream.sh` | **20 passed, 0 failed** (`TIER_STREAM PASS`) |
| `tier_info` | 20/0 |
| `tier_setup` | 21/0 |
| `tier_cli` | 23/0 |
| `tier_tui` | 40/0 |
| `tier_audio` | 27/0 |
| `tier_flac` | 59/0 |
| Large OGG | 67,109,323 bytes; 19,800 pages; deterministic 2x |
| Independent oracle | frames 883,148,168; duration 20,026.035 s |
| Large `--info` under `ulimit -v 65536` | exit 0; channels/rate/duration exact |
| Same-size full allocation under the same limit | `alloc-failed` |
| `--pcm` exact pin | 352,844 bytes; md5 `e7f24870ec03b924be1b8e55a1962fb3` |
| Operator OGG `--info` under 64 MiB | exit 0; 334.000 s |
| Operator OGG TUI pty | `Now:` + `State: Playing`; 1,082,668 WAV bytes; no `cannot open track` |

The T6 scoped re-review recorded **APPROVE after the sample-accurate granule
fix**, with no open Critical/Important findings (ledger). It covered the T6 fix
round (`7a873812`, `1d12989c`) after the source freeze. T7's read-only audit
found no new Critical or Important issue.

## Operator confirmation: real files played

The operator confirmed on 2026-10-19 that both real files in `lin_bin/` played
successfully through the M9 streaming build:

- real OGG: `01. 霜月はるか — ユメノハテニ.ogg` (8,205,755 bytes; size also
  recorded in the T6 report)
- real FLAC: `01. Yofukashino Uta.flac` (33,757,087 bytes; exact filename and
  size as provided by the operator, not independently verified as gate
  evidence)

The T6 pty evidence above corroborates OGG playback with actual decoded output.
The real-FLAC result is the operator's confirmation; it is not an automated gate
run and the media files are not committed.

## Audio caveat / platform status

- **Linux audio caveat:** the build container has no OSS `/dev/dsp` and no
  `aplay`; automated Linux verification used only the hermetic WAV sink
  (`Z9PLAY_WAV_OUT`). The operator host has ALSA and `aplay`, and the operator
  used them for real-file playback. The native OSS backend was not
  device-tested in either environment; do not read the Linux result as an
  OSS-device test.
- **Win9x:** `-osw` emit/link, PE32 shape, and the KERNEL32+WINMM /
  no-msvcrt import whitelist are design/automated-gate verified. Real
  Win98/Me hardware playback remains **operator-pending**.

## Review against the M9 spec

The current tree matches the approved direction:

- `BufferedFile` is a bounded 64 KiB reader over `std_file`; refill loops to
  fill the caller buffer or reach true EOF.
- OGG pages are read one at a time into a 65,536-byte buffer; packets assemble
  into a fixed 1 MiB buffer with a clean `PacketTooLarge` reject; the tail
  granule scan is bounded to 256 KiB plus at most one page-straddle retry.
- `flac.StreamFlacDecoder` reads metadata/frames through the file; the
  byte-slice `FlacDecoder` is never used by production frontends.
- `main.zig` and `ui.zig` stream `--info`, `--dump-setup`, `--pcm`, `--wav`,
  interactive CLI, and TUI. `--pcm` writes the 44-byte header first and patches
  RIFF/data sizes at the end.
- Stream handles are closed on success and failure paths in both frontends; the
  TUI closes before resetting the stream arena.
- No compiler, `sf/**`, standard-library, or seed change.
- Out-of-scope items remain out of scope: network streaming, chained /
  multiplexed OGG, granular seeking, resumed playback, and playlist
  persistence.

No hidden whole-file path was found in the production audit. The bounded
negative test in `tier_stream.sh` (full-file allocation fails under the same
limit) remains the non-vacuous proof.

## Deferred minors

The per-task reviews recorded these Minor counts in the ledger: **T0 4,
T1 4, T2 3, T3 4, T5 4**. T4 and T6 have no open C/I after their fix rounds.
The review notes were not stored as separate files, so the counts are cited
from the ledger; the corresponding known items in the task reports are:

1. `BufferedFile` caches file size at open; a file that grows or shrinks later
   is not re-stat'ed (`bufferedFileSize`).
2. `bufferedFileSeek` casts `u64` to `i64`; offsets above `i64` max are outside
   the intended range.
3. OGG stream I/O failures map to `Truncated` because the spec's error set has
   no open/read/seek/size variants.
4. The tail scan requires the final complete page to end at EOF; a final-page
   truncation returns `Truncated` rather than the previous granule.
5. FLAC CRC-16 is read but not verified (unchanged from M8 and explicitly
   allowed).
6. The FLAC streaming path duplicates decode helpers because Z98 has no
   generics; the exact-oracle tests must keep both paths in sync.
7. FLAC stream and fixed sample scratch share the 16 MiB decode arena rather
   than splitting the API.
8. A pathological near-1 MiB comment packet plus copied tags could exhaust the
   2 MiB stream arena; such a track reports an OOM/header error instead of
   playing. Committed fixtures are far smaller.
9. TUI `d` on an active track stops playback and closes the stream; after
   Ended it preserves the existing now-playing display. This is the
   minimum-change behavior for the close-on-`d` requirement.
10. The optional `Z9PLAY_LARGE_OGG` branch printed `skip` in the recorded
    automated T6 run because the variable was unset; it was exercised manually
    with the same `--info`/limit command. It never copies the operator file.
11. The pure-Python large-OGG generator takes roughly 10 s per 64 MiB run; the
    gate runs it twice for determinism.
12. `tier_flac.sh` re-runs `tier_tui.sh`; a deep scratch path can truncate the
    TUI's fixed 43-column path pane. This is a harness path-length sensitivity,
    so `tier_stream.sh` uses a short scratch root. The direct `tier_tui` run is
    40/0 at the normal short path.

## Remaining limits / risks

- **Linux device audio:** the build container has no `/dev/dsp` and no
  `aplay`; automated verification used the WAV sink only. Operator-host
  ALSA/`aplay` playback is operator-confirmed, not an automated OSS-device
  test.
- **Win9x:** hardware playback on real Win98/Me remains operator-pending.
- **D3/D4/D5:** still OPEN from the earlier milestones; not changed by M9.
- **Streaming subset:** single logical OGG stream, no chaining/multiplexing,
  no sample-accurate seek, no resumed playback, no playlist persistence.
- **Packet bound:** a legal packet over 1 MiB is rejected cleanly by design.
- **Tail granule:** requires a complete final page; no whole-file fallback is
  allowed.
- **WAV output on 32-bit:** output sizes are 32-bit; a >4 GiB `--pcm`/WAV
  request must be rejected rather than wrapped.
- **Test harness:** the generator and nested-tier path assumptions above remain
  environment-sensitive but do not affect the player.

## Task 7 checklist

- [x] Last authoritative M9 gate evidence cited from the T6 fix round and
  scoped re-review; no new T7 full-gate run.
- [x] No production `readAll` / `ogg.reassemble` / `ogg.lastGranule` /
  `flac.open(arena, bytes)`; test-only oracles remain.
- [x] No `sf/**` change.
- [x] Seed v102 archive and fixed-point md5 unchanged.
- [x] `lin_bin/z9play-console` md5 matches the T6 build (provenance check
  only; untracked operator artifact, not gate evidence).
- [x] Operator confirmation of real OGG and real FLAC playback recorded.
- [x] Build-container no-`/dev/dsp`/no-`aplay` caveat and operator-host
  ALSA/`aplay` playback context recorded; Win9x hardware pending.
- [x] Deferred minors and remaining limits recorded.
- [x] No source edits; report-only change. `run.err` and `progress.md` were not
  modified. `lin_bin/` remains the untracked M9 operator-playback build, not a
  gate artifact.
- [x] No push.

**Handoff verdict:** M9 is complete for the approved code/test/docs scope. The
only remaining external validation is real Win9x hardware and Linux OSS-device
audio on a host that has `/dev/dsp`.

## Fix round 1

**T7 review I1 — provenance correction.** Status is unchanged: PASS / handoff
ready. T7 did not perform a new authoritative full-gate run and no source was
changed; this section only corrects the report's provenance claims.

1. **Gate provenance.** T7 did **not** perform a new authoritative full-gate
   run. The last authoritative results remain the T6 fix round and the T6
   scoped re-review. Incidental T7-era artifacts — `/tmp/t7_tier_stream.log`,
   `/tmp/z9play_tier_stream/tiers/flac.log`, the rebuilt `lin_bin` binary, and
   playback WAVs — are build/playback evidence only, **not** gate evidence.
   No source changed after `7a873812`; `1d12989c`, `ee695a5b`, the initial
   report commit `8cbe25ae`, and this truth-up commit are documentation-only.
2. **`lin_bin` provenance.** `lin_bin/` was rebuilt/recreated for operator
   playback during M9 and remains untracked. It is not a tracked artifact, not
   part of the gate, and not included in this or the initial report commit. The
   console md5 `af1cef634dd7b885363bff2ec3582aff` is a provenance check
   against the T6 build, not independent gate evidence. T7 did not treat
   `lin_bin/` as pristine, and this report does not claim it was untouched.
3. **Audio host split.** The build container has no OSS `/dev/dsp` and no
   `aplay`; automated Linux verification used the hermetic WAV sink only. The
   operator host has ALSA and `aplay`, used by the operator for real-file
   playback. The native OSS backend was not device-tested in either
   environment.
4. **Operator confirmation.** The operator confirmed successful playback of
   real OGG and real FLAC files. The exact FLAC filename and size
   (`01. Yofukashino Uta.flac`, 33,757,087 bytes) are recorded as
   operator-provided and were not independently verified as gate evidence.

**Effect:** no change to the handoff verdict, no change to source, no new gate
run, and no push.
