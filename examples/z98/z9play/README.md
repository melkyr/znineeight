# z9play

z9play — a **native Z98** OGG Vorbis music player (CLI + TUI) for Linux and
Windows 9x. Decoded entirely in Z98 (no vendored decoder, no C decoder
library); playback goes through a small application-level platform audio layer.

Spec: `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`.
M0 plan: `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md`.

## Status

**M0 (OGG container + Vorbis headers + `z9play --info`) — complete.**
Tasks 0–5 are done: deterministic fixtures + goldens, the no-root
`vorbis-tools` acquisition helper, the OGG container parser (`ogg.zig`), the
Vorbis id/comment parsers (`vorbis_info.zig`), and the `--info` CLI
(`cli.zig`/`main.zig`). The M0 gate `tests/tier_info.sh` is green (20/20).

**M1 (Vorbis setup header + codebooks + `z9play --dump-setup`) — complete
(Tasks 0–5, closed out).** `vorbis_setup.zig` parses the setup header (codebooks,
floors, residues, mappings, modes); `codebook.zig` builds the canonical Huffman decode
tables and VQ vectors. `z9play --dump-setup <file.ogg>` prints a fixed summary
of the setup object counts. The M1 gate `tests/tier_setup.sh` is green (21/21).

**M2 (native pure-Z98 `std_math` f64 `sqrt`/`sin`/`cos`) — complete (Tasks 0–6,
closed out).** This milestone edits the **standard library** (`sf/src/std_math.zig`),
not the example: fdlibm-port `sin`/`cos` (Cody–Waite reduction, ≤1 ULP over
`|x| ≤ ~1.65e6`, NaN beyond) and a correctly-rounded integer-seed `sqrt`; no libm,
no compiler builtins. The M2 gate `tests/tier_math.sh` is green (8/8) and
`verify_stdlib` is 285/0 (`STDLIB GATE OK`). Its Task 6 M3 amendment review found
**no amendment needed**.

**M3 (audio decode to interleaved s16 PCM) — complete (Tasks 0–6, closed out).** Window +
inverse MDCT + overlap-add (`dsp.zig`), floor1 (`floor.zig`), residue type 0/1/2
(`residue.zig`), and the packet→PCM driver (`decode.zig`), exposed as
`z9play --pcm <in.ogg> <out.wav>` (canonical 44-byte-header PCM WAV). The M3 gate
`tests/tier_decode.sh` is green (24/24): all five fixtures decode within tolerance
(`max |Δ| = 1 LSB`, RMS 0.034–0.039 LSB) and 3× deterministically vs the `oggdec`
goldens. Example-only; no compiler/seed change (the open defect D7 is worked
around in `vorbis_setup.zig`, recorded in `examples/torrent_example_defects.md`).
Its Task 6 M4 amendment review found **no amendment needed** (`decodePacket` is
already streaming-capable with caller-owned `DecoderState`; M4 drives it per
packet).

**M4 (audio output + ring buffer + Player core) — complete (Tasks 0–6, closed
out).** An application-level `AudioOut` vtable (`platform/audio.zig`) with two
backends — a hermetic WAV/null sink (`platform/audio_wavfile.zig`) and a Linux
OSS `/dev/dsp` backend (`platform/audio_oss.zig` + its C-extern PAL
`platform/audio_oss_pal.zig`) — plus the shared `Player` core and double-buffer
`RingBuffer` (`player.zig`; 176,400 B = 88,200 interleaved i16; blocking v1
loop; per-packet scratch reset). The M4 gate is `z9play --wav <in.ogg> <out.wav>`
driving the whole path into the hermetic sink; `tests/tier_audio.sh` is green
(27/27: completion + position monotonicity, canonical WAV header + payload size,
tolerance vs the M3 goldens, 3× determinism, and the OSS `OpenFailed` contract).
Example-only; no compiler/seed change (compiler defect D8 is worked around by
holding the vtables **by pointer** and assembling them at the caller — see
`examples/torrent_example_defects.md`). Its Task 6 M5 CLI-plan amendment review
found **no amendment needed** (M4's public `Player` `state`/`volume` fields and
`playerPositionMs` cover the status line, keys, volume and clean stop; the
`AudioOut` vtable and the D8 caller-owned/pointer-vtable shape carry over — M5
adds its own volume scaling, `--start` skip and `--loop` reset).

## Files

M0 (all present; `[x]` = landed in M0):

- `[x]` `tests/get_vorbis_tools.sh` — no-root `vorbis-tools` acquisition
  (`oggenc`/`ogginfo`), private apt state/cache + `dpkg-deb -x`.
- `[x]` `tests/mkfixtures.sh` — deterministic fixture + golden generator.
- `testdata/*.ogg` — committed fixtures; `testdata/expected/*.meta` — goldens.
- `[x]` `ogg.zig` — OGG page parser + packet reassembly (Task 1) + duration
  (Task 4).
- `[x]` `vorbis_info.zig` — Vorbis id + comment header parsers (Tasks 2–3).
- `[x]` `cli.zig`, `main.zig` — `--info`/`--dump-setup`/`--help`/`--version` CLI
  (M0 Task 5; M1 Task 4).

M1 (Tasks 1–4 landed):

- `[x]` `vorbis_setup.zig` — setup-header parser (`Setup`, `Codebook`, `Floor`,
  `Residue`, `Mapping`, `Mode`; `parseSetup`).
- `[x]` `codebook.zig` — canonical Huffman decode tables + VQ vector unpack.
- `[x]` `tests/setup_test.zig` — M1 unit harness.
- `testdata/expected/*.setup` — `--dump-setup` goldens.
- `[x]` `tests/tier_setup.sh` — the M1 gate (Task 4).
- `[x]` `tests/tier_info.sh` — the M0 gate (Task 5).
- `[x]` `NOTES.md`, `README.md`.

M3 (Tasks 1–5 landed):

- `[x]` `dsp.zig` — window slope, unnormalized inverse MDCT, overlap-add.
- `[x]` `floor.zig` — floor1 decode (floor0 rejected).
- `[x]` `residue.zig` — residue type 0/1/2 decode.
- `[x]` `decode.zig` — audio packet → interleaved s16 PCM (`decodePacket` +
  caller-owned `DecoderState`).
- `[x]` `main.zig`/`cli.zig` — `--pcm <in.ogg> <out.wav>`.
- `[x]` `tests/decode_test.zig` — M3 Task 4 golden gate.
- `[x]` `tests/tier_decode.sh` — the M3 gate (Task 5).
- `testdata/expected/*.pcm` — `oggdec` golden raw s16 LE PCM.

M4 (Tasks 1–4 landed):

- `[x]` `platform/audio.zig` — `AudioError` + the blueprint §2.2 `AudioOut`
  vtable.
- `[x]` `platform/audio_wavfile.zig` — hermetic WAV/null sink (output path via
  `setOutputPath` + a `Z9PLAY_WAV_OUT` fallback).
- `[x]` `platform/audio_oss.zig` — Linux OSS `/dev/dsp` backend (best-effort;
  `OpenFailed` when the device is absent).
- `[x]` `platform/audio_oss_pal.zig` — the OSS `open`/`ioctl`/`write`/`close` C
  externs (split out: an `extern "c" fn open` cannot share a module with the
  backend's `pub fn open`).
- `[x]` `player.zig` — `Player`, `PlayerState`, `RingBuffer`, the `Decoder`
  vtable, and the M3 Vorbis backend (`vorbisCreate`/`vorbisNext`).
- `[x]` `main.zig`/`cli.zig` — `--wav <in.ogg> <out.wav>` (the Player gate path).
- `[x]` `tests/audio_test.zig`, `tests/player_test.zig`, `tests/oss_test.zig` —
  M4 unit harnesses.
- `[x]` `tests/tier_audio.sh` — the M4 gate (Task 4).

## Build and Run

M0/M1 use the seed built from `release/seed/zig1-seed.tgz` (current seed v97):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed
mkdir -p /tmp/z9play_out
timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_out \
    examples/z98/z9play/main.zig
sh /tmp/z9play_out/build_target.sh linux /tmp/z9play_out/prog
/tmp/z9play_out/prog --info examples/z98/z9play/testdata/tagged_unicode.ogg
/tmp/z9play_out/prog --dump-setup examples/z98/z9play/testdata/tagged_unicode.ogg
/tmp/z9play_out/prog --pcm examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/out.wav
/tmp/z9play_out/prog --wav examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/player.wav
```

`--info <file.ogg>` prints a fixed `key=value` block matching the golden
`testdata/expected/*.meta`:

```
channels=2
sample_rate=44100
duration_s=1.000
TITLE=Café déjà vu
ARTIST=Naïve 日本
ALBUM=Ünïcodé
```

`TITLE`/`ARTIST`/`ALBUM` are printed only when the stream carries them (raw
UTF-8 bytes). Exit codes: `0` ok, `1` arguments, `2` open, `3` decoder
(malformed/non-Vorbis); `--help`/`--version` exit `0`.

`--dump-setup <file.ogg>` parses the setup header and prints exactly one fixed,
LF-terminated summary line matching the golden `testdata/expected/*.setup`:

```
codebooks=38 floors=2 residues=2 mappings=2 modes=2
```

The counts are the parsed header-object list lengths. Exit codes mirror
`--info` (`0`/`1`/`2`/`3`).

`--pcm <in.ogg> <out.wav>` (`M3`) decodes the whole stream and writes a canonical
44-byte-header PCM WAV (16-bit, the fixture's channels/sample-rate) whose `data`
payload is the decoded interleaved s16 LE frames, trimmed to the stream granule
so it lines up with the `oggdec` golden `testdata/expected/*.pcm`. Exit codes:
`0` ok, `1` arguments (incl. a missing output path), `2` open, `3` decoder
(malformed container/header/packet, or floor-0/unsupported).

`--wav <in.ogg> <out.wav>` (`M4`) drives the whole player path — decode → the
double-buffer PCM ring (`player.zig`) → the `AudioOut` vtable — into the
hermetic WAV sink (`platform/audio_wavfile.zig`); no audio device is touched. It
writes the same canonical 44-byte-header PCM WAV as `--pcm` (same granule trim)
and prints one line `wav: ended frames=<n> pos_ms=<n> monotonic=<0|1>` (the
Player reached `ended` cleanly and `playerPositionMs` never went backwards). It
is the M4 gate subcommand; the Linux OSS `/dev/dsp` backend is best-effort and
device-dependent. Exit codes mirror `--info`/`--pcm` (`0`/`1`/`2`/`3`).

```bash
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_info.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_setup.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_decode.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_audio.sh
```

## Fixtures

Generated once and committed (`testdata/`), not regenerated by the suite:

| fixture | channels | rate | duration | tags |
|:--|:--|:--|:--|:--|
| `sine_mono_44100.ogg` | 1 | 44100 | 1.0 s | — |
| `sine_stereo_44100.ogg` | 2 | 44100 | 2.0 s | — |
| `sine_stereo_48000.ogg` | 2 | 48000 | 1.0 s | — |
| `tagged_unicode.ogg` | 2 | 44100 | 1.0 s | TITLE/ARTIST/ALBUM (UTF-8) |
| `short.ogg` | 1 | 44100 | 0.3 s | — |

Regenerate (deliberate, manual): `sh tests/mkfixtures.sh`. See `NOTES.md` for
the golden `.meta` format and the determinism contract.

## Notes

`NOTES.md` holds the build recipe, the `--dump-c89` md5
(`d695bf99dadb7f6dbbc0f2a94bb42f43`, seed v97; M4 adds `main.zig`'s audio/player
import closure and bumps `--version` to `(M4)`, so it changed from the M3 value
`a5f208b5c8034e9c9f2be9c6800913f4`; prior M2
`88ad559ce5e4a3dae6f11a0c52b35792`, M1 `344c26ed89dd0830443fa5e16b870ec0`,
M0 `--info`-only `ba86cbe8b2229667f4c8084a0b0e75da`), the golden formats, and the
milestone log.
