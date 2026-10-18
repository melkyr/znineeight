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

**M5 (interactive CLI playback) — complete (Tasks 0–5).** `z9play <file.ogg>
[--volume N|--start SEC|--loop|--quiet]` plays interactively: a startup metadata
line, a per-second `\r` status line (`fmt.zig`), and non-echoed keys (space
pause/resume, `+`/`-` volume ±5, `q`/Ctrl-C quit) via `platform/console_linux.zig`
(`termios`). Playback drives the M4 `Player` into the hermetic WAV sink when
`Z9PLAY_WAV_OUT` is set (else Linux OSS `/dev/dsp`). Exit codes: `0` ok / `1` arg
/ `2` open / `3` decoder / `4` audio / `5` internal. The M5 gate
`tests/tier_cli.sh` is green (23/23). Example-only; no compiler/seed change (seed
v98; no workaround was needed at M5 time — the defect numbering was reset on
2026-10-16 and the new D1 is open; see M5b below).

**M5b (console contract + complete Linux backend) — complete (Tasks 1–4).** The
app-level console abstraction is now `platform/console.zig` — the `Console`
contract (`Key = union(enum){ none, char, sigint, up, down, left, right, enter,
esc }`; the nine ops `clear`/`setCursor`/`writeStr`/`readKey`/`enterRaw`/
`leaveRaw`/`width`/`height`/`cursorShow` + `state`; `readKey_fn: fn (*void) Key`,
returning the in-band `Key.none`). The complete Linux backend
`platform/console_linux.zig` implements every op as a free function over a
caller-owned `ConsoleLinState` (termios raw mode, a persistent ESC/arrow state
machine, ANSI clear/setCursor/cursorShow, `ioctl(TIOCGWINSZ)` size), and
`main.zig` assembles the `Console` literal and drives the CLI through it
(`tests/tier_cli.sh` stays green, 23/23). The extended `tests/tier_console.sh`
asserts every op — including contiguous+split arrow decode, the exact ANSI
bytes, and `width`/`height` against a real 100×30 pty window (11/11).
Example-only; no compiler/seed change (seed v98). `readKey_fn` returns `Key`,
not `?Key`, because of compiler defect **D1** (optional-of-aggregate
function-pointer return) — see `examples/torrent_example_defects.md`; the spec §5
`Console` vtable now carries the `cursorShow_fn` extension (committed in
`075e1bf1`).

**M6 (Windows 9x audio + console) — complete (Tasks 0–5).** A Win9x `waveOut`
backend (`platform/audio_win9x.zig` + its PAL) implements the M4 `AudioOut`
vtable (16-bit PCM, 44100/48000 Hz, 1/2 channels, two 500 ms buffers, blocking
write, drain/close; unsupported config/device → `ConfigUnsupported`/
`OpenFailed`), and a complete Win9x `Console` backend
(`platform/console_win9x.zig` + PAL) implements all nine ops (raw mode,
non-blocking `ReadConsoleInput` keys, Win32 output/size/cursor calls, `atexit`
restore backstop). `main.zig` selects the backends at compile time with
`@isWindows()` and an explicit Linux `else`; `Z9PLAY_WAV_OUT` still selects the
hermetic WAV sink on every platform. Ctrl-C uses **Amendment 1, Option 3**:
`enterRaw` clears `ENABLE_PROCESSED_INPUT`, so Ctrl-C arrives as a `KEY_EVENT`
with `uChar == 0x03` → `.sigint` (a clean quit with exit 0); no stdcall
`SetConsoleCtrlHandler` callback is used. The M6 gate `tests/tier_win9x.sh` is
green **14/14**: PE32 + real undefined-symbol/import checks, Wine full-playback
WAV parity vs the Linux golden (`max_delta=1`, `rms_milli=36`) and 2×
determinism, and a pty console probe
(`entered=1,raw_changed=1,restored=1`). The manual real-device path is
`demo/win9x_README.txt`. The M6 `-osw --dump-c89` md5 is
`87856b43091e2bf5d992fc795d9764f2` (stable 2×).

The compiler for M6 is rebuilt from the **current `sf/src`** (post-D1/D2 parity
fixes; md5 `2c48fa702393032c2b711a8d982bd388`, fixed point
`b0e5f3b4e580f69eacdac7bd0e07dda1`, three-hop closure OK) — the pre-fix seed-v98
binary must not be used. Defect status under the current numbering (reset
2026-10-16; the old M0–M5 D1–D8 are all FIXED and in history): **D1** and
**D2** are **FIXED** at root cause by the 2026-10-17 parity milestone; **D3**
(conditional `@import` lazy-load gap) and **D4** (analyzer cluster) are **OPEN**;
**D5** (`extern fn` with a body silently treated as a declaration; no stdcall
definitions) is **OPEN**, and M6 works around it with the Option 3 Ctrl-C
mechanism above. See `examples/torrent_example_defects.md`.

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

M5 (Tasks 1–4 landed):

- `[x]` `fmt.zig` — player-local integer formatter (`mmss` / `statusLine`; no
  `std.fmt.bufPrint`, no std change).
- `[x]` `platform/console_linux.zig` — Linux `termios` raw mode + non-blocking
  `readKey` (M5's 3-op shape; **M5b replaced it with the `Console` contract**,
  below).
- `[x]` `platform/console_linux_pal.zig` — the `termios`/`signal` C externs (PAL
  split, as `audio_oss_pal.zig`).
- `[x]` `cli.zig`/`main.zig` — interactive playback (`<file.ogg>` +
  `--volume`/`--start`/`--loop`/`--quiet`; keys, startup/status lines, exit
  codes `0`/`4`/`5`).
- `[x]` `tests/fmt_test.zig`, `tests/console_test.zig`, `tests/tier_console.sh` —
  M5 unit harnesses + the raw-console gate.
- `[x]` `tests/tier_cli.sh` — the M5 gate (Task 4).

M5b (Tasks 1–4 landed):

- `[x]` `platform/console.zig` — the `Console` contract (`Key` + nine ops +
  `state`; `readKey_fn: fn (*void) Key`).
- `[x]` `platform/console_linux.zig` — complete Linux backend (raw `termios`, a
  persistent ESC/arrow state machine, ANSI output, `ioctl(TIOCGWINSZ)` size)
  over a caller-owned `ConsoleLinState`.
- `[x]` `platform/console_linux_pal.zig` — `termios`/`signal`/`ioctl` C externs
  (PAL split; `Winsize` mirror).
- `[x]` `main.zig`/`cli.zig` — the CLI drives the assembled `Console` contract.
- `[x]` `tests/console_test.zig`, `tests/tier_console.sh` — the extended all-ops
  console gate (11/11).

M6 (Tasks 1–5 landed):

- `[x]` `platform/audio_win9x.zig` — Win9x waveOut backend (16-bit PCM,
  44100/48000, 1/2 channels, two 500 ms buffers, blocking write, drain/close;
  `OpenFailed`/`ConfigUnsupported`).
- `[x]` `platform/audio_win9x_pal.zig` — winmm/PAL `waveOut*` externs and the
  `WAVEFORMATEX`/`WAVEHDR` mirrors.
- `[x]` `platform/console_win9x.zig` — complete nine-op Win9x `Console` backend
  (raw mode with processed input off for Ctrl-C Option 3, non-blocking
  `ReadConsoleInput` key decode, Win32 output/size/cursor ops, `atexit`
  restore backstop).
- `[x]` `platform/console_win9x_pal.zig` — Win32 console API externs and
  `INPUT_RECORD`/`COORD`/cursor/screen-buffer mirrors.
- `[x]` `main.zig` — compile-time `@isWindows()` selection (WAV-sink env
  override first; explicit Linux `else`), with console restore on every exit
  path.
- `[x]` `tests/tier_win9x.sh` — the M6 gate (mingw PE32 build + Wine WAV parity
  + pty console restore; 14/14).
- `[x]` `tests/win9x_console_probe.zig` — Wine pty probe asserting
  `entered=1,raw_changed=1,restored=1`.
- `[x]` `demo/win9x_README.txt` — manual Win98 build/copy/run procedure,
  console/raw-mode caveats, Ctrl-C semantics and waveOut limits.

## Build and Run

The Linux tiers use the seed built from `release/seed/zig1-seed.tgz` (current
seed v98; two-hop closure `hop1 == hop2 == f18b69ece1917bf970a036b276e5e403`).
The M6 Win9x tier instead uses the compiler rebuilt from the current `sf/src`
(post-D1/D2; see the Windows 9x section below).

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
Z9PLAY_WAV_OUT=/tmp/play.wav \
    /tmp/z9play_out/prog examples/z98/z9play/testdata/sine_stereo_44100.ogg
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

`z9play <file.ogg> [--volume N|--start SEC|--loop|--quiet]` (`M5`) plays
interactively. It prints a startup metadata line

```
z9play: <title-or-path>  <mm:ss>  <ch>ch <rate>Hz
```

and, unless `--quiet`, a per-second `\r` status line from `fmt.statusLine`:

```
00:42 / 03:15  vol  80%  [########------------]
```

Keys: **space** pause/resume, **`+`**/**`-`** volume ±5, **`q`**/Ctrl-C quit. On
exit it prints `Stopped at mm:ss.`. `--volume N` is a percentage (`0..100`,
default `80`); `--start SEC` skips to integer second `SEC` before playing (the
seek decodes and discards, so it is block-granular, ≤0.5 s); `--loop` repeats
until quit. Playback drives the M4 `Player` into the hermetic WAV sink when
`Z9PLAY_WAV_OUT=<file>` is set (all platforms); otherwise `@isWindows()` selects
the Win9x waveOut backend, else the Linux OSS `/dev/dsp` backend. Exit
codes: `0` ok, `1` arguments, `2` open, `3` decoder, `4` audio, `5` internal.
The M0–M4 request modes (`--info`/`--dump-setup`/`--pcm`/`--wav`) are unchanged.

### Windows 9x (M6)

The Win9x build is a PE32 i386 console executable produced by the shared mingw
cross harness (`scripts/win32_cross/cross_build_run.sh`, `-osw`, `-lwinmm`).
Build the compiler from the **current `sf/src`** (post-D1/D2 parity fixes; the
seed-v98 binary predates them), then cross-build:

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_m6
ROOT=/workspace/znineeight bash scripts/win32_cross/cross_build_run.sh \
    /tmp/z9play_m6/zig1_5_clean examples/z98/z9play/main.zig \
    /tmp/z9play_win9x_build /tmp/z9play_win9x_build/z9play.exe -lwinmm
```

Copy `z9play.exe` plus an `.ogg` to the Win98 box and run `z9play.exe song.ogg`
from an MS-DOS Prompt; the full manual procedure (copy/run, console behavior,
Ctrl-C Option 3, raw-mode restore/recovery, waveOut limits) is
`demo/win9x_README.txt`.

```bash
ZIG=/tmp/z9play_m6/zig1_5_clean sh examples/z98/z9play/tests/tier_win9x.sh
```

The Linux gates are unchanged:

```bash
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_info.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_setup.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_decode.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_audio.sh
ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_cli.sh
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

`NOTES.md` holds the build recipe, the `--dump-c89` md5, the golden formats, and
the milestone log. The M6 gate value is the Win9x target
`87856b43091e2bf5d992fc795d9764f2` (`-osw --dump-c89`, stable 2×; compiler
rebuilt from current `sf/src` post-D1/D2). The prior Linux `--dump-c89` value
was `4c9f760ae825d7fcf91cbf7a2500a4a4` (M5b; prior M5
`0a60a27846476a73d2fac8e183d52d48`, M4
`d695bf99dadb7f6dbbc0f2a94bb42f43`, M3
`a5f208b5c8034e9c9f2be9c6800913f4`, M2 `88ad559ce5e4a3dae6f11a0c52b35792`,
M1 `344c26ed89dd0830443fa5e16b870ec0`,
M0 `--info`-only `ba86cbe8b2229667f4c8084a0b0e75da`).
