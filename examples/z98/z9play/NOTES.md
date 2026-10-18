# z9play — Z98 Example

**Status:** M0 complete (Tasks 0–5). M1 complete (Tasks 0–5, closed out): setup header parse + codebook construction, exposed via `--dump-setup`. M2 (native pure-Z98 `std_math` f64 `sqrt`/`sin`/`cos`) complete and closed out (Tasks 0–6): std fixture registered, `tests/tier_math.sh` gate green, docs, and the Task 6 M3 amendment review. M3 (audio decode → interleaved s16 PCM) complete and closed out (Tasks 0–6): `dsp`/`floor`/`residue`/`decode`, `z9play --pcm <in.ogg> <out.wav>` (canonical 44-byte-header PCM WAV), `tests/tier_decode.sh` (tolerance + 3× determinism vs the `oggdec` goldens), and the Task 6 M4 amendment review (no amendment needed). M4 (audio output + ring buffer + Player core) complete and closed out (Tasks 0–6): the `AudioOut` vtable (`platform/audio.zig`), the hermetic WAV sink (`platform/audio_wavfile.zig`) and Linux OSS `/dev/dsp` backend (`platform/audio_oss.zig`/`audio_oss_pal.zig`), the shared `Player` + double-buffer `RingBuffer` (`player.zig`), the `z9play --wav <in.ogg> <out.wav>` gate subcommand, and `tests/tier_audio.sh` (tolerance + completion/monotonicity + 3× determinism vs the M3 goldens; 27/27). M4's Task 6 closeout (below) records the M5 CLI-plan amendment review: **no amendment needed** — M4's caller-owned, field-exposed `Player` API plus the `AudioOut` vtable cover the CLI's status line, keys, volume, clean stop, and the D8 pointer-vtable shape. M5 (interactive CLI playback) complete (Tasks 0–5): the `fmt.zig` status formatter, the `platform/console_linux.zig` raw `termios` console (`readKey`), the `cli.zig`/`main.zig` playback mode (`<file.ogg>` + `--volume`/`--start`/`--loop`/`--quiet`; startup metadata line, per-second `\r` status, keys space/`+`/`-`/`q`/Ctrl-C, `Stopped at mm:ss.`, exit codes 0/1/2/3/4/5), and `tests/tier_cli.sh` (PASS 23/23). M5b (console abstraction + complete Linux backend) complete (Tasks 1–4): the `platform/console.zig` `Console` contract (`Key = {none,char,sigint,up,down,left,right,enter,esc}`; the nine ops `clear`/`setCursor`/`writeStr`/`readKey`/`enterRaw`/`leaveRaw`/`width`/`height`/`cursorShow` + `state`; `readKey_fn: fn (*void) Key`), the rewritten `platform/console_linux.zig` backend over a caller-owned `ConsoleLinState` (`termios` raw mode, persistent ESC/arrow state machine, ANSI clear/setCursor/cursorShow, `ioctl(TIOCGWINSZ)` size), `main.zig` driving the CLI through the assembled `Console`, and the extended `tests/tier_console.sh` (PASS 11/11). M6 (Win9x audio + console) complete (Tasks 0–5): `platform/audio_win9x.zig` (+PAL) waveOut backend (16-bit PCM, 44100/48000, 1/2 ch, two 500 ms buffers, blocking write, drain/close), `platform/console_win9x.zig` (+PAL) complete nine-op `Console` backend with Amendment 1 Option 3 Ctrl-C (processed input off → `KEY_EVENT` 0x03 → `.sigint`; no stdcall callback), `main.zig` compile-time `@isWindows()` selection (`Z9PLAY_WAV_OUT` WAV-sink override first, explicit Linux `else`), `tests/tier_win9x.sh` 14/14 (PE32 + real undefined-symbol check, Wine WAV parity, pty console restore; `-osw --dump-c89` `87856b43091e2bf5d992fc795d9764f2`), and `demo/win9x_README.txt` manual Win98 procedure. Defect status (current numbering): D1/D2 FIXED; D3/D4 OPEN; D5 OPEN (Option 3 workaround).

**Entry file:** `main.zig`

**Working commit:** `a0a7616f` (`example(z9play): M6 T4 fix — real undefined-symbol check`; the last commit of the M6 Win9x surface, pinned at M6 closeout; this docs commit is docs-only and does not bump `--version`, which remains `(M5)`). Prior closeout: `5a096122` (`example(z9play): M5b console tier`; the last commit of the M5b console surface, pinned at M5b closeout). Prior closeout: `06321a72` (`example(z9play): M5 CLI tier`; the last commit of the M5 CLI surface, pinned at M5 closeout; the docs commit that follows also bumps the `--version` string to `(M5)`, so the recorded M5 MD5 is measured at that closeout tree, not at `06321a72`). Prior closeouts: M4 `61e93e72` (`example(z9play): M4 audio tier`; the last commit of the M4 audio surface — the docs commit that followed bumped `--version` to `(M4)`); M3 `c7af78ac` (`example(z9play): M3 --pcm + tier_decode`; the M3 `--pcm` + `tier_decode` commit — the last commit of the M3 decode surface, pinned at M3 closeout); M2 `b5ca08d2` (`feat(std_math): f64 sin/cos (pure Z98)`; the last `std_math` surface commit; full M2 chain `4d6fb5dd` (f64 `sqrt`) → `b5ca08d2` (f64 `sin`/`cos`) → `52958705` (`tests/tier_math.sh`) → `6844aad5` (docs)); M1 `100c35ce` (`example(z9play): M1 --dump-setup + tier_setup`); M0 `27b1fddf` (`example(z9play): z9play --info CLI + tier_info gate`). **M3 decode chain:** `bb211810` (IMDCT + window + overlap-add) → `b497323a` (floor1) → `d925cb55` (residue type 0/1/2) → `16ae3eea` (packet → PCM) → `de48b5cf` (docs: D7 + cumulative-defect warning) → `c7af78ac` (M3 `--pcm` + `tier_decode`; this closeout). **M5 CLI chain:** `4154098c` (CLI status formatter) → `437c12cc` (T1 fix: fixed-width volume field) → `2a5384b4` (Linux raw console input) → `8dcb0072` (CLI playback loop + keys) → `7f447896` (T3 fix: `--start` pacing + integer-seconds message) → `06321a72` (M5 `tier_cli`; M5 closeout). **M5b chain:** `c554d666` (Console contract) → `8f968713` (complete Linux backend) → `4a96a0fa` (escape-decode state machine fix) → `35c9893d` (CLI drives the Console contract) → `5a096122` (M5b console tier; M5b closeout). **M6 chain:** `866b260f` (Win9x waveOut backend) → `d86b3441` + `85234e21` (Win9x console backend + Option 3 Ctrl-C fix) → `2e0f194a` (`@isWindows()` backend selection) → `f91eb8b2` + `a0a7616f` (Win9x tier + real undefined-symbol check; this closeout).

**MD5 (`-osw --dump-c89`):** `87856b43091e2bf5d992fc795d9764f2` (M6 compiler rebuilt from current `sf/src` post-D1/D2, md5 `2c48fa702393032c2b711a8d982bd388`; stable 2×; M6). **M6 added the `-osw` target value**; the prior primary value was the Linux default `--dump-c89` `4c9f760ae825d7fcf91cbf7a2500a4a4` (M5b), because the M6 compile now emits the Win9x import closure behind `@isWindows()`. The z9play **compiler fixed point for M6** is `b0e5f3b4e580f69eacdac7bd0e07dda1` (compiler rebuilt from current `sf/src`; bootstrap seed v98 — the post-D1/D2 fixes landed after seed v98, so the old v98 binary fixed point `f18b69ece1917bf970a036b276e5e403` must not be used). Prior: M5b Linux `--dump-c89` `4c9f760ae825d7fcf91cbf7a2500a4a4` (seed v98), M5 `0a60a27846476a73d2fac8e183d52d48` (seed v98), M4 `d695bf99dadb7f6dbbc0f2a94bb42f43` (seed v97), M3 `a5f208b5c8034e9c9f2be9c6800913f4`, M2 `88ad559ce5e4a3dae6f11a0c52b35792`, M1 `344c26ed89dd0830443fa5e16b870ec0`, M0 `--info`-only `ba86cbe8b2229667f4c8084a0b0e75da`.

Spec: `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).
M0 plan: `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md`.

## Build Recipe (binding for M0)

The seed is built from `release/seed/zig1-seed.tgz` (current seed **v98**):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed
# two-hop closure OK: hop1 == hop2 == f18b69ece1917bf970a036b276e5e403 (v98)

mkdir -p /tmp/z9play_out
timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_out \
    examples/z98/z9play/main.zig
sh /tmp/z9play_out/build_target.sh linux /tmp/z9play_out/prog
```

All tiers run under **`-fsafe`**. The M5 base seed is **v98**, which supersedes
the v97 this milestone was authored against; compiler defects **D1–D8 are all
FIXED** in seed v98 (see `examples/torrent_example_defects.md`), so the prior
D7-class workaround warning is retired (M5 needed none). *Note:* that defects
doc was **reset on 2026-10-16** — the earlier D1–D8 are all fixed (history in
git) and its numbering **restarted**, so the doc's current **D1** is the new
*open* defect (a function pointer returning optional-of-aggregate cannot be
emitted); see the M5b section.

### `--info` usage (M0)

```bash
/tmp/z9play_out/prog --info examples/z98/z9play/testdata/tagged_unicode.ogg
# channels=2
# sample_rate=44100
# duration_s=1.000
# TITLE=Café déjà vu
# ARTIST=Naïve 日本
# ALBUM=Ünïcodé
```

The output is a fixed `key=value` block (LF-terminated) in the same format as
the committed `testdata/expected/*.meta` goldens; `TITLE`/`ARTIST`/`ALBUM` are
emitted only when the stream carries them (raw UTF-8 value bytes). Exit codes:
`0` ok, `1` arguments, `2` open, `3` decoder (malformed container/header, or a
non-Vorbis stream). `--help` and `--version` exit `0`.

### `--dump-setup` usage (M1)

```bash
/tmp/z9play_out/prog --dump-setup examples/z98/z9play/testdata/tagged_unicode.ogg
# codebooks=38 floors=2 residues=2 mappings=2 modes=2
```

`--dump-setup <file.ogg>` parses the OGG container, the identification header
(for the channel count the mapping parser needs), and the Vorbis setup header
(packet index 2, `\x05vorbis`), then prints exactly ONE fixed, LF-terminated
summary line:

```
codebooks=<n> floors=<n> residues=<n> mappings=<n> modes=<n>
```

The count is each header object's parsed list length (`Setup.codebooks` /
`.floors` / `.residues` / `.mappings` / `.modes`). The line is compared
byte-for-byte against the committed `testdata/expected/*.setup` goldens. Exit
codes mirror `--info`: `0` ok, `1` arguments, `2` open, `3` decoder (malformed
container / identification / setup header, or a non-Vorbis stream).

### `--pcm` usage (M3)

```bash
/tmp/z9play_out/prog --pcm examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/out.wav
# writes a canonical 44-byte-header PCM WAV (RIFF/WAVE, fmt 16, audio format 1
# (PCM), the fixture's channels/sample-rate, 16 bits/sample, block align
# channels*2), whose `data` payload is the decoded interleaved s16 LE frames.
```

`--pcm <in.ogg> <out.wav>` parses the container, the identification/comment/
setup headers, then decodes every audio packet (`7. 3.0` in `decode.zig`,
`DecoderState` carried across packets) to interleaved signed-16-bit PCM and
writes it with a canonical 44-byte WAV header. The payload is **trimmed to the
stream granule** (`testdata/expected/*.pcm` has no padding) so it lines up with
the `oggdec` golden. A correct float decoder is not required to be bit-identical
to libvorbis: the gate `tests/tier_decode.sh` compares the payload to the golden
by tolerance (per-sample max |Δ| and RMS LSB) and additionally asserts 3×
determinism (identical SHA-1), reporting exact-match SHA-1 as informational.
Exit codes mirror `--info`: `0` ok, `1` arguments (incl. a missing output path),
`2` open, `3` decoder (malformed container/header/packet, or floor-0/unsupported).

```
$ sh examples/z98/z9play/tests/tier_decode.sh
== tier_decode summary: 24 passed, 0 failed ==
TIER_DECODE PASS
```

### `--wav` usage (M4)

```bash
/tmp/z9play_out/prog --wav examples/z98/z9play/testdata/sine_stereo_44100.ogg /tmp/out.wav
# wav: ended frames=88200 pos_ms=2000 monotonic=1
```

`--wav <in.ogg> <out.wav>` drives the whole M4 player path — decode → the
double-buffer PCM ring (`player.zig`) → the `AudioOut` vtable
(`platform/audio.zig`) — into the hermetic WAV sink
(`platform/audio_wavfile.zig`); **no audio device is touched**. It writes a
canonical 44-byte-header PCM WAV with the same shape and granule trim as `--pcm`,
and prints exactly one line:

```
wav: ended frames=<n> pos_ms=<n> monotonic=<0|1>
```

i.e. the Player reached `ended` with no error (`frames` = frames handed to the
audio backend, `pos_ms` = the final `playerPositionMs`), and `monotonic=1` means
`playerPositionMs` never went backwards. It is the M4 gate subcommand
(`tests/tier_audio.sh`); the Linux OSS `/dev/dsp` backend
(`platform/audio_oss.zig`) is best-effort and device-dependent — v1 uses the WAV
sink for the gate, not a `--wav` device path. Exit codes mirror
`--info`/`--pcm`: `0` ok, `1` arguments, `2` open, `3` decoder/player.

```
$ sh examples/z98/z9play/tests/tier_audio.sh
== tier_audio summary: 27 passed, 0 failed ==
TIER_AUDIO PASS
```

### Playback usage (M5)

```bash
Z9PLAY_WAV_OUT=/tmp/play.wav \
    /tmp/z9play_out/prog examples/z98/z9play/testdata/sine_stereo_44100.ogg \
    --volume 80
# z9play: examples/z98/z9play/testdata/sine_stereo_44100.ogg  00:02  2ch 44100Hz
# 00:00 / 00:02  vol  80%  [--------------------]     (then, once per second, \r-redrawn)
# ...
# Stopped at 00:02.
```

`z9play <file.ogg> [--volume N|--start SEC|--loop|--quiet]` is the interactive
M5 playback mode (a bare positional selects it; the M0–M4 request modes
`--info`/`--dump-setup`/`--pcm`/`--wav` are unchanged). It prints a startup
metadata line

```
z9play: <title-or-path>  <mm:ss>  <ch>ch <rate>Hz
```

(the `TITLE` tag when present, else the file path), then — unless `--quiet` — a
per-second `\r`-redrawn status line from `fmt.statusLine`:

```
00:42 / 03:15  vol  80%  [########------------]
```

The status line is fixed-width (the volume field is a 3-char right-aligned
field, so `\r` redraw needs no clear-to-EOL); the bar is 20 cells, filled by
`floor(pos_ms * 20 / dur_ms)`. Keys: **space** pause/resume, **`+`**/**`-`**
volume ±5 (0–100), **`q`**/**Ctrl-C** quit. On exit it prints `Stopped at mm:ss.`
(the final `playerPositionMs`). Options:

- `--volume N` — percentage `0..100` (default `80`); applied by the M5 `mix*`
  `AudioOut` wrapper (the M4 `Player` only stores `volume`). `--volume 100`
  reproduces the M3 golden payload byte-for-byte.
- `--start SEC` — integer seconds; skips to `SEC` before playing by decoding and
  discarding into a throwaway sink (so the seek is block-granular, ≤0.5 s). An
  invalid/missing value prints `z9play: --start expects an integer number of
  seconds` and exits 1.
- `--loop` — re-inits the decode chain per pass into the same open sink and
  repeats until quit.
- `--quiet` — suppress the per-second status line (the startup and `Stopped`
  lines remain).

The backend is chosen by the environment: `Z9PLAY_WAV_OUT=<file>` selects the
hermetic WAV sink (`platform/audio_wavfile.zig`; no device touched) on every
platform. Otherwise the platform is selected at compile time with
`@isWindows()`: Win9x uses the waveOut backend (`platform/audio_win9x.zig`),
else Linux uses OSS `/dev/dsp` (`platform/audio_oss.zig`); either device path
exits 4 when the device is absent/unopenable. Raw keyboard input goes through
the `Console` contract (`platform/console.zig`), assembled from the matching
platform backend — `platform/console_win9x.zig` on Win9x or
`platform/console_linux.zig` on Linux (`termios` raw mode; both restore on
every exit path). When stdin is not a console/tty the keys are not polled, so a
redirected run still completes. Exit codes: `0` ok, `1`
arguments, `2` open, `3` decoder, `4` audio, `5` internal.

```
$ sh examples/z98/z9play/tests/tier_cli.sh
== tier_cli summary: 23 passed, 0 failed ==
TIER_CLI PASS
```

### `--dump-c89` (for the MD5 above)

```bash
# M6: Win9x target (compiler rebuilt from current sf/src, post-D1/D2)
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 examples/z98/z9play/main.zig | md5sum
# 87856b43091e2bf5d992fc795d9764f2  -
# (M6's recorded value is the -osw target above; the prior Linux value was M5b's:)
# timeout 120 /tmp/z9play_seed/zig1_5_clean --dump-c89 examples/z98/z9play/main.zig | md5sum
# 4c9f760ae825d7fcf91cbf7a2500a4a4  -
# (M5, before M5b's platform/console.zig import closure + the Console-contract dispatch
#  in main.zig and the platform/console_linux.zig rewrite: 0a60a27846476a73d2fac8e183d52d48;
#  M4, before M5's fmt.zig + platform/console_linux.zig import closure, the playback
#  mode, and the (M5) version bump: d695bf99dadb7f6dbbc0f2a94bb42f43;
#  M3, before M4's audio/player import closure + the (M4) version bump: a5f208b5c8034e9c9f2be9c6800913f4;
#  M2, before M3's decode.zig import closure: 88ad559ce5e4a3dae6f11a0c52b35792;
#  M1, before the M2 std_math f64 functions: 344c26ed89dd0830443fa5e16b870ec0)
```

## Baseline (Task 0)

- Seed build succeeded and reached the expected fixed point
  `bafbba9454cd2b134bdc3d50c65384e0` (seed v97).
- Corpus discovery: `scripts/corpus/list_corpus_dirs.sh` enumerates every
  immediate subdir of `examples/z98/`, but emits a directory only if it has a
  resolvable entry (`main.zig`, else `<basename>.zig`, else the first `*.zig`).
  `examples/z98/z9play/` currently has **no** `.zig` entry, so it is not yet
  listed; with a `main.zig` present it is listed as
  `examples/z98/z9play/` (verified with a throwaway stub, removed immediately).
  **Task 5 update:** `main.zig` now exists, so `examples/z98/z9play/` is listed
  with `main.zig` as the resolved entry; the `examples/z98/` corpus count is now
  **26** (was 25).

## Fixtures and goldens (Task 0)

Generated once and **committed** under `testdata/` (the committed bytes, not the
script, are the source of truth). Regeneration is a deliberate manual act:

```bash
sh examples/z98/z9play/tests/mkfixtures.sh
```

`mkfixtures.sh` obtains `oggenc`/`ogginfo` via
`tests/get_vorbis_tools.sh` (no root: private apt state/cache +
`apt-get install --download-only --no-install-recommends -y vorbis-tools` +
`dpkg-deb -x` into a prefix). `get_vorbis_tools.sh` prints:

```
oggenc: <path>
ogginfo: <path>
LD_LIBRARY_PATH: <colon-separated dirs>
oggenc_version: oggenc from vorbis-tools 1.4.2
```

Both binaries require the printed `LD_LIBRARY_PATH`.

| fixture | ch | rate | dur | tags |
|:--|:--|:--|:--|:--|
| `sine_mono_44100.ogg` | 1 | 44100 | 1.0 s | — |
| `sine_stereo_44100.ogg` | 2 | 44100 | 2.0 s | — |
| `sine_stereo_48000.ogg` | 2 | 48000 | 1.0 s | — |
| `tagged_unicode.ogg` | 2 | 44100 | 1.0 s | TITLE/ARTIST/ALBUM (UTF-8) |
| `short.ogg` | 1 | 44100 | 0.3 s | — |

### Golden `.meta` format (fixed)

One `key=value` per line, LF-terminated, no comments:

```
channels=<decimal>
sample_rate=<decimal>
duration_s=<seconds, 3 decimals>
TITLE=<raw UTF-8 value>      # only when the fixture carries the tag
ARTIST=<raw UTF-8 value>     # only when the fixture carries the tag
ALBUM=<raw UTF-8 value>      # only when the fixture carries the tag
```

`channels`, `sample_rate`, and `duration_s` are read from `ogginfo`
(`Channels:`, `Rate:`, and `Playback length: <m>m:<s>s`). Tag lines are parsed
directly from the **comment packet stored in the `.ogg`** (uppercase keys, raw
bytes), in fixed `TITLE`, `ARTIST`, `ALBUM` order and present only when set;
they match the Vorbis-convention uppercase keys Task 3 produces.

### Determinism contract

1. PCM samples are computed in `python3` from `math.sin` (no random); the
   committed `.ogg` bytes are authoritative.
2. `oggenc` picks a random Ogg bitstream serial per run, so every encode pins it
   with `-s <serial>` (a fixed serial per fixture: 1001–1005). Re-running
   `mkfixtures.sh` reproduces **all** `.ogg` and `.meta` files byte-for-byte
   (verified: two consecutive runs compared `cmp`-identical).

### Non-ASCII tags: encode-time locale (fix round 1)

`oggenc` converts non-ASCII tag arguments through the locale. Under a non-UTF-8
locale (e.g. `C`) it substitutes each non-ASCII byte with `#` **at encode
time**, so the `.ogg` itself stores `#` — a later reader (our parser, `ogginfo`,
or `vorbiscomment`) then sees `#`. The original generator exported `LC_ALL=C`
globally, which leaked into `oggenc` and corrupted `tagged_unicode.ogg` (its tag
bytes were `#`, not UTF-8).

Fix: `mkfixtures.sh` runs `oggenc` under a UTF-8 locale (auto-detected
`C.UTF-8`/`C.utf8`/`en_US.UTF-8`; STOP if none) and scopes `LC_ALL=C` to only
the byte/numeric parsing helpers. The golden tag values are now read back from
the actual stored comment packet, and a self-check asserts the stored bytes
round-trip to the requested values (and that the non-ASCII bytes appear verbatim
in the file). Forcing `UTF8_LC=C` makes the script fail loudly with the `##`
round-trip mismatch, proving the guard.


## Milestone Log

### M0 — OGG container + Vorbis headers + `--info` (complete)

- **Task 0 (preflight) — DONE.** `tests/get_vorbis_tools.sh` (no-root
  acquisition) and `tests/mkfixtures.sh` (deterministic fixtures + goldens);
  skeleton docs; baseline seed build + corpus-discovery check.
- **Task 1 — DONE.** `ogg.zig`: 27-byte page header + segment-table parse,
  page walk, local OGG CRC-32 verify, packet reassembly; `tests/ogg_test.zig`.
- **Task 2 — DONE.** `vorbis_info.parseId` + `IdHeader`; malformed cases reject.
- **Task 3 — DONE.** `vorbis_info.parseComment` + `Comment`/`Tag` (uppercased
  keys, arena-owned slices, raw UTF-8 value bytes).
- **Task 4 — DONE.** `ogg.lastGranule` + `ogg.durationMs`.
- **Task 5 — DONE.** `cli.zig` (`--info`/`--help`/`--version`, exit 1 on a
  malformed command line) + `main.zig` (fixed `key=value` info block; exit 2
  open / 3 decoder); `tests/tier_info.sh` (5 fixtures vs golden + exit codes,
  non-vacuous negatives). Seed v97; `--dump-c89` md5
  `ba86cbe8b2229667f4c8084a0b0e75da` (stable 3×); `ogg_test` + `info_test` PASS.

  ```
  $ sh examples/z98/z9play/tests/tier_info.sh
  == tier_info summary: 20 passed, 0 failed ==
  TIER_INFO PASS
  ```

### M1 — Setup header + codebooks (Tasks 0–5 complete; closed out)

- **Task 1 — DONE.** `vorbis_setup.zig`: setup skeleton + codebook dimensions
  (count, per-codebook `BCV` sync / dimensions / entries / flags / lengths);
  `tests/setup_test.zig`. Plan Task 2 bit-order amended (byte reader is
  LSB-first).
- **Task 2 — DONE.** `codebook.zig`: canonical Huffman decode tables
  (`buildDecodeTable` / `decodeScalar`) + VQ vector unpack
  (`entryToVector` / `decodeVector`, lookup types 1/2, basic f64 scaling).
- **Task 3 — DONE.** `vorbis_setup.zig`: time count, floors (0/1), residues
  (0/1/2), mappings (coupling/submaps/mux), modes, framing. `parseSetup` gained
  a `channels` parameter (`parseSetup(arena, packet, channels)`), forwarded from
  the identification header's channel count.
- **Task 4 — DONE.** `cli.zig` (`--dump-setup` mode; conflicting/duplicate
  requests exit 1) + `main.zig` (`codebooks=<n> floors=<n> residues=<n>
  mappings=<n> modes=<n>` summary; exit 2 open / 3 decoder);
  `testdata/expected/*.setup` goldens + `tests/tier_setup.sh` (5 fixtures vs
  golden + argument/open/decoder exit codes). Seed v97; `--dump-c89` md5
  `344c26ed89dd0830443fa5e16b870ec0` (stable 3×); `ogg_test` + `info_test` +
  `setup_test` + `tier_info` (20/20) + `tier_setup` (21/21) PASS.

  ```
  $ sh examples/z98/z9play/tests/tier_setup.sh
  == tier_setup summary: 21 passed, 0 failed ==
  TIER_SETUP PASS
  ```

### Task 5 — M2 amendment review + M1 closeout — DONE

- **Part A (M2 amendment review) — no amendment needed.** M1's `Setup` /
  `Codebook` / bit-reader output is independent of M2 (`std_math` f64): M2
  consumes no M1 structure, so M1's actual output invalidates no M2 assumption.
  M3's window/IMDCT math needs `sin` (Vorbis window `sin(π/2·sin²(π/(2n)·(i+.5)))`)
  and `cos` (IMDCT basis); the residue/VQ/coupling paths need only the baseline
  f64 `+ - * /` M1 already uses. `π` is a compile-time constant local to the
  example. `floor0` (`exp`/`log`/`atan` `bark()`) is rejected in v1 (M3 Task 2 →
  `error.UnsupportedFloor`); `pow`/`atan`/`atan2`/`floor` are on no M3 path. So
  M2's declared set `{sqrt, sin, cos}` fully covers M3's exact function needs.
- **Part B (M1 closeout).** Working commit pinned to `100c35ce`
  (`example(z9play): M1 --dump-setup + tier_setup`). Gates re-run under seed v97:
  `ogg_test`, `info_test`, `setup_test` PASS; `tier_info` 20/20; `tier_setup`
  21/21; two-hop seed closure `bafbba9454cd2b134bdc3d50c65384e0`; `--dump-c89`
  md5 `344c26ed89dd0830443fa5e16b870ec0`. The M1 plan carries no status field,
  so there is nothing to flip to "done".

### M2 — Native float math (`std_math` f64; Tasks 3–5) — DONE

Plan: `docs/superpowers/plans/2026-10-11-z9play-m2-native-math-plan.md`. This is
the one z9play milestone that edits the **standard library** (`sf/src/std_math.zig`),
not the example: pure-Z98 f64 math so the Vorbis IMDCT/window can run on Win9x
(no libm).

- **Tasks 1–2 (`std_math`) — DONE (prior commits).** `4d6fb5dd`
  `feat(std_math): f64 sqrt (pure Z98)` and `b5ca08d2`
  `feat(std_math): f64 sin/cos (pure Z98)`. `sqrt` is correctly rounded (exact
  integer square root of the significand: 0 ULP); `sin`/`cos` use a Cody-Waite
  argument reduction (split `2/pi`) + fdlibm `__kernel_sin`/`__kernel_cos`,
  <= 1 ULP vs the glibc/python oracle over `|x| <= 2^20*(pi/2) ≈ 1.65e6`, NaN
  outside that domain (no Payne-Hanek). No libm, no compiler math builtins.
- **Task 3 (fixture registration) — already registered, no change.** The std
  fixture `repro/mi_matrix/stdlib_math_f64_xmod/` (`main.zig` + `expected.txt` +
  `expected.rc`) is pinned in `scripts/stdlib/expected_dirs.txt` (added by the
  Task 1 commit `4d6fb5dd`, adjacent to `stdlib_math_xmod`; no duplicate).
  `bash scripts/stdlib/verify_stdlib.sh /tmp/z9play_seed/zig1_5_clean` →
  `285 PASS / 0 FAIL`, `STDLIB GATE OK` (284 baseline + the new f64 fixture).
  Nothing to change, so no commit ("already registered").
- **Task 4 (z9play math tier) — DONE.** `mathtest.zig` + `tests/tier_math.sh` +
  `tests/mathtest.expected` (8 checks): builds the z9play-local probe under
  `-fsafe`, diffs stdout against the committed oracle (identical to the std
  fixture's `expected.txt`), and asserts the linked binary imports **no libm**
  (`nm -u` has no undefined `sqrt`/`sin`/`cos`/`pow`; DT_NEEDED is libc only; a
  real `-lm` control binary is flagged non-vacuously).

  ```
  $ sh examples/z98/z9play/tests/tier_math.sh
  == tier_math summary: 8 passed, 0 failed ==
  TIER_MATH PASS
  ```

- **Task 5 (docs) — DONE.** `docs/sf/QUICK_REF.md` notes the `std_math` f64
  surface (`sqrt`/`sin`/`cos`, the `~1.65e6` argument-reduction domain cap, pure
  Z98 / no libm).
- **Regression:** `tier_info` 20/20, `tier_setup` 21/21; seed closure unchanged
  `bafbba9454cd2b134bdc3d50c65384e0`. (The M3 amendment review is M2 Task 6, a
  separate dispatch.)

### Task 6 — M3 amendment review + M2 closeout — DONE

- **Part A (M3 amendment review) — no amendment needed.** M3's only
  transcendental consumer is the Task 1 `dsp.zig` window/IMDCT, which uses
  exactly `sin` (Vorbis window `sin(π/2·sin²(π/(2n)·(i+0.5)))`) and `cos` (the
  inverse-MDCT basis `cos(π/n·(2i+1+n/2)(2k+1))`), plus the baseline f64
  `+ - * /`. `π` is a local compile-time constant, not a std function. The
  floor1 path uses the committed static `floor1_inverse_dB_table` + linear
  interpolation; residue/VQ/coupling use only baseline f64 arithmetic; floor0
  (`exp`/`log`/`atan` `bark()`) is rejected in v1 (`error.UnsupportedFloor`).
  So M3 needs no `exp`/`log`/`pow`/`atan2`/`floor`; M2's `sqrt` is not on any
  M3 path but is harmless. **Angle-domain check:** the M2 `sin`/`cos` cap is
  `~1.647e6` rad (NaN beyond). The largest phase on any M3 path is the IMDCT:
  for the maximum Vorbis block `n = 8192`, `max|arg| ≈ π/n·(2n-1+n/2)·(n-1) ≈
  6.4e4` rad; the window outer argument is ≤ `π/2`. Both are ≥ 25× inside the
  cap, so no M3 block size reaches the NaN region.
- **Part B (M2 closeout).** Working commit pinned to the M2 `std_math`
  implementation commit `b5ca08d2` (`feat(std_math): f64 sin/cos (pure Z98)`);
  full M2 chain recorded above. Gates re-run under seed v97 (`-fsafe`,
  example-only, no compiler/seed change): `tier_math` 8/8, `verify_stdlib`
  285/0 `STDLIB GATE OK`, `tier_setup` 21/21, `tier_info` 20/20; two-hop seed
  closure `bafbba9454cd2b134bdc3d50c65384e0`. `--dump-c89` md5 re-pinned to the
  true M2 value `88ad559ce5e4a3dae6f11a0c52b35792` (see the MD5 note above:
  M2's `std_math` is embedded in the `std` module the dump emits, so the md5
  **did** change from the M1 value `344c26ed89dd0830443fa5e16b870ec0`).

### M3 — Audio decode to PCM (`dsp`/`floor`/`residue`/`decode`; Tasks 0–5) — DONE

Plan: `docs/superpowers/plans/2026-10-11-z9play-m3-audio-decode-plan.md`. Largely
example-only; the only compiler-adjacent interaction is the documented open
defect D7 (see `examples/torrent_example_defects.md`), worked around in
`vorbis_setup.zig` (mode struct renamed `VorbisMode`) rather than by a compiler
change.

- **Task 0 (preflight) — DONE.** `mkfixtures.sh` extended to also run `oggdec`
  (`-Q -R -b 16 -e 0 -s 1`) → `testdata/expected/<name>.pcm` (raw s16 LE,
  headerless); run-twice self-check proves libvorbis determinism.
- **Task 1 (`dsp.zig`) — DONE.** Window slope + direct unnormalized inverse MDCT
  (analytic unit check) + overlap-add (TDAC closing test).
- **Task 2 (`floor.zig`) — DONE.** floor1 decode (`decodeY`/`renderLine`, the
  committed `floor1_inverse_dB_table`); floor0 → `error.UnsupportedFloor`.
- **Task 3 (`residue.zig`) — DONE.** residue type 0/1/2, partitioned vectors
  over the affected channels, type-0 EOP rule, do-not-decode skip.
- **Task 4 (`decode.zig`) — DONE.** packet → interleaved s16 (`decodePacket`
  driven by a caller-owned `DecoderState`). Golden gate `decode_test`:
  `frames=88640 golden_frames=88200 max_delta=1 rms_milli=36`, 3× deterministic
  (decoded SHA-1 `f891394376e3012753ddcb6e4a18cf1cfe321b14`).
- **Task 5 (--pcm + gate) — DONE (this commit).** `cli.zig`/`main.zig` gained
  `--pcm <in.ogg> <out.wav>`, decoding the whole file and writing a canonical
  44-byte-header PCM WAV (payload trimmed to the stream granule). New gate
  `tests/tier_decode.sh`: for all 5 fixtures, header/size check, tolerance vs the
  `oggdec` golden (`max |Δ| = 1 LSB`, `rms_milli` 34–39), 3× determinism, and the
  non-vacuous negative exit codes (args 1 / open 2 / decoder 3); exact-match
  SHA-1 vs golden reported informationally. Seed v97; `--dump-c89` md5
  `a5f208b5c8034e9c9f2be9c6800913f4` (stable 3×).

  ```
  $ sh examples/z98/z9play/tests/tier_decode.sh
  == tier_decode summary: 24 passed, 0 failed ==
  TIER_DECODE PASS
  ```

  Regression: `tier_info` 20/20, `tier_setup` 21/21, `tier_math` 8/8; unit tests
  `ogg_test`/`info_test`/`setup_test`/`dsp_test`/`floor_test`/`residue_test`/
  `decode_test` all PASS.

### Task 6 — M4 amendment review + M3 closeout — DONE

- **Part A (M4 amendment review) — no amendment needed.** M3's
  `decode.zig` output contract is already streaming-shaped:
  `decodePacket(arena, setup, *DecoderState, packet, pcm_out) !usize` decodes
  **one audio packet per call**, returns the finished frame count (samples per
  channel; `0` for the priming packet), writes interleaved s16 L,R,… into the
  caller's `pcm_out`, and keeps all cross-packet state (codebook tables,
  previous block size, per-channel overlap tail) in the caller-owned
  `DecoderState`. The only whole-stream buffering lives in `main.zig`'s `--pcm`
  path (one `big` buffer + 16 MiB `dec_arena_buf`), and that is a CLI
  convenience, not the decoder contract. M4's `Player`/double-buffer ring is
  designed to "decode one block when room" (`playerPump`) and its Task 3 test
  compares the WAV-sink bytes to the **same** `--pcm` output byte-for-byte —
  which matches exactly because `--pcm` itself drives `decodePacket`
  packet-by-packet with one `DecoderState`, so a ring that concatenates the
  same per-packet outputs reproduces the identical PCM sequence. Variable
  per-packet framing (short/long blocks, the priming packet emitting nothing) is
  absorbed by `playerPump`'s "decode one packet, append `frames*channels`"
  loop; the granule trim M3 does at WAV-write time becomes M4's
  length/duration bookkeeping, already in the M4 `Player` fields. Therefore M3's
  actual output invalidates no M4 `Player`/ring-buffer/audio-out assumption.
  (Non-assertion note, not an amendment: M3 flags that `residue.zig`'s
  `entryToVector` allocates per-codeword arena scratch, so a long-running player
  should reset a per-packet scratch arena or reuse buffers; M4's unit gate is a
  2 s fixture, so this does not block it.)
- **Part B (M3 closeout).** Working commit pinned to `c7af78ac`
  (`example(z9play): M3 --pcm + tier_decode`); full M3 chain recorded above.
  Gates re-run under seed v97 (`-fsafe`, example-only, no compiler/seed change):
  `tier_decode` 24/24, `tier_info` 20/20, `tier_setup` 21/21, `tier_math` 8/8;
  unit tests `ogg_test`/`info_test`/`setup_test`/`dsp_test`/`floor_test`/
  `residue_test`/`decode_test` all PASS; two-hop seed closure
  `bafbba9454cd2b134bdc3d50c65384e0`; `--dump-c89` md5
  `a5f208b5c8034e9c9f2be9c6800913f4` (stable). The M3 plan carries no status
  field, so there is nothing to flip to "done".

### M4 — Audio output + ring buffer + Player core (`platform/audio*`, `player.zig`; Tasks 0–5) — DONE

Plan: `docs/superpowers/plans/2026-10-11-z9play-m4-audio-out-plan.md`. Example-only
(no compiler/seed change). M4 splits audio output from the decoder: an
application-level `AudioOut` vtable (`platform/audio.zig`), two backends
(`platform/audio_wavfile.zig` hermetic WAV/null sink, `platform/audio_oss.zig`
Linux OSS `/dev/dsp` + its C-extern PAL `platform/audio_oss_pal.zig`), and the
shared `Player` core + double-buffer `RingBuffer` (`player.zig`) that drives
decode → ring → audio.

- **Task 1 (`platform/audio.zig` + `audio_wavfile.zig`) — DONE.** `AudioError`
  (`error{ OpenFailed, WriteFailed, ConfigUnsupported, DeviceError }`) and the
  blueprint §2.2 `AudioOut` vtable (`open_fn`/`write_fn`/`close_fn`/`drain_fn` +
  `state`, methods returning `AudioError!T`). `audio_wavfile` implements it as a
  canonical 44-byte-header PCM WAV writer (header written with zeroed size
  fields, patched in `close`); the destination path comes from a setter
  (`setOutputPath`, `Z9PLAY_WAV_OUT` env fallback). First D8 contact.
- **Task 2 (`audio_oss.zig` + `audio_oss_pal.zig`) — DONE.** Linux OSS
  `/dev/dsp` backend: `extern "c"` `open`/`ioctl`/`write`/`close` plus the
  numeric `SNDCTL_DSP_{SETFMT,CHANNELS,SPEED,SYNC}` ioctls (hardcoded for the
  pinned i386 target, so `<sys/soundcard.h>` need not be installed); configures
  AFMT_S16_LE at the requested rate/channels, blocking `write`. Best-effort: on
  a device-less host `open` returns `error.OpenFailed` cleanly (`tests/oss_test.zig`;
  the WAV sink stays the gate backend). The C externs live in the PAL module
  because an `extern "c" fn open` cannot share a module with the required
  `pub fn open` (same-name collision), the same split `std_file`/`std_file_pal` uses.
- **Task 3 (`player.zig`) — DONE.** `Player` + `RingBuffer` (2 × 0.5 s @
  44.1 kHz stereo s16 = 176,400 bytes = 88,200 interleaved i16, allocated once
  from the player arena); blocking v1 loop — `playerPump` decodes one block when
  the ring has room, flushes a half (`flush_threshold = capacity/2`) or the tail
  at end of stream; `playerPositionMs` monotonic. The `Decoder` vtable abstracts
  the codec; the M3 Vorbis backend (`vorbisCreate`/`vorbisNext`) implements it and
  resets its per-packet scratch arena on every call (the M3 `entryToVector`
  per-codeword arena-scratch residual). The Player stops handing samples to audio
  at exactly `decoder.total_frames` (granule trim), so its output matches M3's
  `--pcm`. vtables are held **by pointer** and the `Player` is **caller-owned**
  (`playerInit(p: *Player, …)`) — the D8 refinement (see below).
- **Task 4 (`--wav` + `tests/tier_audio.sh`) — DONE.** `z9play --wav <in.ogg>
  <out.wav>` drives the whole M4 path (decode → double-buffer ring → `AudioOut`)
  into the hermetic WAV sink (no device touched) and prints `wav: ended …
  monotonic=1`. New gate `tests/tier_audio.sh`: for all 5 fixtures — exit 0 +
  completion + position monotonicity, canonical WAV header + payload size == the
  M3 `--pcm` golden, tolerance vs the `oggdec` golden (max |Δ| = 1 LSB, RMS
  34–39), 3× determinism — plus `oss_test` asserting the OSS backend reports
  `OpenFailed` cleanly when `/dev/dsp` is absent. Green (27/27).
- **Task 5 (docs) — DONE (this commit).** `NOTES.md`/`README.md` document the
  M4 audio layer + `--wav`; the user-facing version string is bumped to
  `z9play 0.1.0 (M4)` (was `(M3)`); the `--dump-c89` md5 re-pinned (below).

#### D8 workaround (vtables held by pointer)

The blueprint §2.2 vtable methods return `AudioError!T`. Emitting an aggregate
that carries the error-union-returning function-pointer typedef **by value** —
either a function *returning* the vtable struct, or (T3 refinement) a struct that
*embeds* a vtable struct as a field — makes the C89 emitter write the
function-pointer typedef before the error-union typedef it references (invalid
C89). This is compiler defect **D8**, recorded in
`examples/torrent_example_defects.md`.

Workaround (example-only; the vtable ABI is unchanged): backends expose their
vtable entries as **public free functions** (`open`/`write`/`close`/`drain`) and
the **caller assembles the vtable literal**
(`audio.AudioOut{ .open_fn = wav.open, …, .state = ctx }`); `player.Player` holds
its vtables **by pointer** (`decoder: *const Decoder`, `audio: *const audio.AudioOut`)
and is **caller-owned** (`playerInit(p: *Player, …)`), never returned by value.
Holding vtables by pointer is clean; only embedding/returning an aggregate that
carries the fnptr field by value triggers D8.

  ```
  $ sh examples/z98/z9play/tests/tier_audio.sh
  == tier_audio summary: 27 passed, 0 failed ==
  TIER_AUDIO PASS
  ```

  Regression: `tier_info` 20/20, `tier_setup` 21/21, `tier_math` 8/8,
  `tier_decode` 24/24, `tier_audio` 27/27; unit tests `audio_test`/`player_test`/
  `oss_test` PASS (plus all earlier harnesses); seed closure unchanged
  `bafbba9454cd2b134bdc3d50c65384e0`; `--dump-c89` md5
  `d695bf99dadb7f6dbbc0f2a94bb42f43` (stable 2×). M4 chain: `f1044ec6` (audio
  vtable + WAV sink) → `6a66afd9` (OSS `/dev/dsp` backend) → `0fcc5f41` (Player
   core + double-buffer ring) → `61e93e72` (M4 `--wav` + `tier_audio`; the M4
   working commit) → this docs commit (version bump + MD5 re-pin). The M4 plan
   carries no status field, so there is nothing to flip to "done".

### Task 6 — M5 amendment review + M4 closeout — DONE

- **Part A (M5 amendment review) — no amendment needed.** M5's CLI plan does not
  name any `Player` operation M4 lacks; it "drives `Player` (M4)" and its Task 0
  explicitly defers the API to this review. M4 exposes everything the CLI reads
  or writes:
  - the `\r` status line `mm:ss / mm:ss  vol N%  [####----]` needs
    `playerPositionMs(p)` (position), `p.duration_ms` (duration) and `p.volume`
    (volume) — all present;
  - the keys act on the public `Player` fields: `p.state = .paused` / `.playing`
    for space (`playerPump` early-returns unless `state == .playing`; because
    `position_ms` is sample-based, not clock-based, a pause simply stops
    advancing, so no `started_ms`/offset bookkeeping is needed for v1);
    `p.volume` for `+`/`-`; `p.state = .stopped` + leaving the loop for
    `q`/Ctrl-C; and the CLI already holds the vtable pointer (`p.audio`), so
    `drain_fn`/`close_fn` give the clean stop/device release;
  - the `Player` is **caller-owned** and its vtables are held **by pointer** (the
    D8 workaround). M5's sketched `main(argc, argv)` + formatter + `termios`
    calls reuse exactly that shape (assemble the `AudioOut`/`Decoder` literals at
    the caller as `main.zig --wav` already does; never return/embed a vtable by
    value), so D8 does not bite M5; `playerInit(p: *Player, …)`, `playerPump(p)`
    and `playerPositionMs(p)` remain the right calls;
  - **no `playerSetVolume`/`playerPause`/`playerStop` functions exist, and none
    is required**: Z98 struct fields are public, so M5 mutates them directly;
    function helpers would be optional sugar, not a missing API;
  - the `AudioOut` vtable (`open_fn`/`write_fn`/`close_fn`/`drain_fn` + `state`)
    is sufficient — it carries no volume method because volume is a
    Player/frontend concern, not a backend one.
  - **Additive M5 work explicitly noted (not amendments; no M4 assumption
    broken):** M4 only *carries* `volume`, it does not scale the PCM it flushes,
    so M5 must apply the volume (e.g. in its own flush/sink path) for `+`/`-` to
    change output; `--start SEC` needs a sample-skip (M4 has the reserved
    `started_ms` field but no seek logic); `--loop` needs a decoder reset/re-init
    (the `Player` ends and stops; `VorbisCtx.next_packet` must be reset). All are
    example-only extensions in `player.zig`/`cli.zig`, consistent with the
    milestone sequence; M5's plan does not assume M4 already does them.
- **Part B (M4 closeout).** Working commit pinned to `61e93e72`
  (`example(z9play): M4 audio tier`); M4 chain `f1044ec6` (audio vtable + WAV
  sink) → `6a66afd9` (OSS `/dev/dsp` backend) → `0fcc5f41` (Player core +
  double-buffer ring) → `61e93e72` (M4 `--wav` + `tier_audio`) → the docs commit.
  Gates re-run under seed v97 (`-fsafe`, example-only, no compiler/seed change):
  `tier_audio` 27/27, `tier_info` 20/20, `tier_setup` 21/21, `tier_math` 8/8,
  `tier_decode` 24/24; unit tests
  `ogg_test`/`info_test`/`setup_test`/`dsp_test`/`floor_test`/`residue_test`/
  `decode_test`/`audio_test`/`player_test`/`oss_test` all PASS; two-hop seed
  closure `bafbba9454cd2b134bdc3d50c65384e0`; `--dump-c89` md5
  `d695bf99dadb7f6dbbc0f2a94bb42f43` (unchanged — this is a docs-only commit).
  The M4 plan carries no status field, so there is nothing to flip to "done".

### M5 — Interactive CLI playback (`fmt.zig`, `platform/console_linux.zig`, playback mode; Tasks 0–5) — DONE

Plan: `docs/superpowers/plans/2026-10-11-z9play-m5-cli-plan.md`. Example-only; no
compiler/seed change. Seed **v98** (two-hop closure
`f18b69ece1917bf970a036b276e5e403`); compiler defects **D1–D8 are all FIXED** in
seed v98, so the prior D7-class workaround warning is retired — M5 hit no
compiler defect and needed no workaround. (The examples compiler-defects doc was
**reset 2026-10-16**: the earlier D1–D8 remain fixed, but its numbering
**restarted**, so its current **D1** is the new *open* defect —
optional-of-aggregate function-pointer returns cannot be emitted; see the M5b
section.)

- **Task 0 (preflight) — DONE.** `script` (pty) present; `gcc -m32` ok;
  `termios.h` present; `/dev/dsp` absent (the WAV sink is the hermetic gate, as
  in M4). M4 `Player` API confirmed.
- **Task 1 (`fmt.zig`) — DONE (fix round 1).** `mmss(buf, ms)` and
  `statusLine(buf, pos, dur, vol)` → `00:42 / 03:15  vol  80%  [########------------]`,
  a fixed-width `\r`-ready line (volume field padded to a fixed 3-char width,
  per the operator ruling), `--` duration guard; `tests/fmt_test.zig` exact-byte
  + width checks. Commits `4154098c` + fix `437c12cc`.
- **Task 2 (`platform/console_linux.zig`) — DONE.** M5's raw `termios` console: a
  raw-mode enter/leave pair plus a non-blocking single-key reader over a
  `Key = union(enum){ char: u8, sigint }` (sticky SIGINT); C externs in
  `platform/console_linux_pal.zig`; `tests/console_test.zig` + `tier_console.sh`
  (pty: echo off, key read back, SIGINT, termios restored). Commit `2a5384b4`.
  **M5b replaced this 3-op shape with the `Console` contract** (`enterRaw` /
  `leaveRaw` / `readKey` free functions over `ConsoleLinState`; `readKey`
  returns `Key` with the in-band `Key.none`) — see the M5b section below.
- **Task 3 (playback loop + exit codes) — DONE (fix round 1).** `cli.zig` adds
  `MODE_PLAY` (bare `<file.ogg>` positional) + `--volume N` / `--start SEC` /
  `--loop` / `--quiet`; `main.zig` adds the playback branch (startup metadata
  line, per-second `fmt.statusLine`, keys space / `+` / `-` / `q` / Ctrl-C, the
  `mix*` volume wrapper, the `discard*` `--start` seek sink, and
  `Stopped at mm:ss.` on exit). Exit codes 0/1/2/3/4/5; `--start` is integer
  seconds (block-granular ≤0.5 s; an invalid value prints an informative message
  and still exits 1). Commit `8dcb0072` + fix `7f447896`.
- **Task 4 (`tests/tier_cli.sh`) — DONE.** Builds `-fsafe`; drives the CLI under
  a pty (`script -qec "exec …"`) into the WAV sink (`Z9PLAY_WAV_OUT`): startup
  line (path form + TITLE form), the t=0 and per-second status lines (`\r`-count
  ≥2), `q`/Ctrl-C exit 0, a bad flag → 1, a missing file → 2, a non-OGG → 3, and
  `--quiet` suppressing the status but keeping the startup/`Stopped` lines.
  Green (23/23). Commit `06321a72`.

  ```
  $ sh examples/z98/z9play/tests/tier_cli.sh
  == tier_cli summary: 23 passed, 0 failed ==
  TIER_CLI PASS
  ```

- **Task 5 (docs) — DONE (this commit).** `NOTES.md`/`README.md` document the
  M5 playback surface, re-pin the build recipe to seed v98, and re-measure the
  `--dump-c89` md5 (below). The user-facing `--version` string is now
  `z9play 0.1.0 (M5)`. The M0–M4 request modes are unchanged (example-only; the
  request-mode paths were not touched).
- M5 chain: `4154098c`+`437c12cc` (formatter) → `2a5384b4` (raw console) →
  `8dcb0072`+`7f447896` (playback loop) → `06321a72` (M5 `tier_cli`; the M5
  working commit) → this docs commit. The M5 plan's Task 6 (M6 amendment review)
  is a separate dispatch; the plan carries no status field, so there is nothing
  to flip to "done".

### M5b — Console contract + complete Linux backend (`platform/console.zig`, `platform/console_linux.zig`; Tasks 1–4) — DONE

Plan: `docs/superpowers/plans/2026-10-16-z9play-m5b-console-contract-plan.md`.
Example-only; no compiler/seed change. Seed **v98** (two-hop closure
`f18b69ece1917bf970a036b276e5e403`). Introduces the app-level `Console`
abstraction that M6 (Win9x) and M7 (TUI) build on.

- **`platform/console.zig` (new) — the `Console` contract.** `Key =
  union(enum){ none, char: u8, sigint, up, down, left, right, enter, esc }` and
  the nine ops `clear_fn` / `setCursor_fn` / `writeStr_fn` / `readKey_fn` /
  `enterRaw_fn` / `leaveRaw_fn` / `width_fn` / `height_fn` / `cursorShow_fn`
  plus `state: *void`. `readKey_fn: fn (*void) Key` returns the in-band
  `Key.none` when nothing is pending (there is no optional-of-aggregate
  function-pointer return). Commit `c554d666`.
- **`platform/console_linux.zig` (rewritten) — the complete Linux backend.**
  Every op is a public free function whose signature matches its contract field
  exactly, over a caller-owned `ConsoleLinState` (`saved` termios + `entered` +
  the persistent ESC parse state); the caller assembles the `Console` literal,
  mirroring the `AudioOut` assembly. Raw mode keeps ISIG (Ctrl-C → SIGINT →
  `.sigint`) and OPOST, has the non-tty guard, and restores on every exit path.
  `readKey` is a non-blocking persistent ESC/arrow state machine: contiguous and
  byte-split `ESC[A/B/C/D` → up/down/right/left; lone `ESC` → `.esc` after a
  bounded window; a non-`[` byte after `ESC` is preserved and returned as its
  own key (`ESC` `CR` → `.esc` then `.enter`); otherwise `.none` / `.char` /
  `.enter`. `clear` = `ESC[2J ESC[H`; `setCursor(row,col)` (0-based) =
  `ESC[<row+1>;<col+1>H`; `cursorShow(true/false)` = `ESC[?25h`/`ESC[?25l`;
  `width`/`height` read `ioctl(TIOCGWINSZ)` (80×24 fallback only on failure).
  Commit `8f968713`, with the review fix `4a96a0fa`.
- **`main.zig` — the CLI drives the contract.** The playback mode assembles a
  Linux `Console` literal and calls `enterRaw_fn` / `readKey_fn` / `leaveRaw_fn`;
  the new `Key.none` means "no key pending" and `.sigint` quits. No user-visible
  behavior change (`tests/tier_cli.sh` 23/23). Commit `35c9893d`.
- **`tests/tier_console.sh` — extended all-ops gate.** Asserts raw/no-echo, key
  read, SIGINT, restore, contiguous + byte-split arrows, lone/`ESC`-`CR` decode,
  the exact `clear`/`setCursor`/`cursorShow`/`writeStr` ANSI bytes, and
  `width`/`height` against a pinned `stty` 100×30 pty window (so the 80×24
  fallback cannot pass). Green (11/11). Commit `5a096122`.
- **Compiler defect D1 / workaround.** Seed v98 rejects a function→function-
  pointer coercion whose return type is an optional-of-aggregate (`?Key`) and
  mis-emits its C89 typedef order; the contract therefore returns `Key` directly
  with the in-band `Key.none` sentinel. Example-only workaround; recorded in
  `examples/torrent_example_defects.md` (D1).
- **Spec §5 amendment.** The binding spec
  (`docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` §5) lists the
  `Console` vtable with the 9th op `cursorShow_fn` (the 2026-10-16 M5b
  extension, committed in `075e1bf1`); blueprint `examples/z9play.txt` §2.2
  already carries the same `cursorShow_fn` note.
- M5b chain: `c554d666` (contract) → `8f968713` (Linux backend) → `4a96a0fa`
  (escape-decode state machine fix) → `35c9893d` (CLI retrofit) → `5a096122`
  (M5b console tier; this surface's last commit) → this docs commit. The M5b
  plan's Task 6 (M6 amendment review) is a separate dispatch; the plan carries no
  status field, so there is nothing to flip to "done".

### M6 — Win9x audio + console (`platform/audio_win9x.zig`, `platform/console_win9x.zig`, `@isWindows()` selection; Tasks 0–5) — DONE

Plan: `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`. Example-only;
no compiler change and no seed rotation. **Compiler note:** M6 was built with a
compiler regenerated from the **current `sf/src`** (the post-D1/D2 parity fixes),
not with a prebuilt seed-v98 binary. Bootstrap seed v98 archive, then:

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_m6
# /tmp/z9play_m6/zig1_5_clean
# md5         2c48fa702393032c2b711a8d982bd388
# fixed point b0e5f3b4e580f69eacdac7bd0e07dda1 (three-hop closure OK)
```

The old v98 seed binary (`f18b69ece1917bf970a036b276e5e403`) predates those
fixes and still exhibits old D2; it is **not** the M6 compiler.

- **Task 0 (preflight) — DONE.** mingw i686 + Wine available; shared
  `scripts/win32_cross/cross_build_run.sh` recipe (`-osw` + `-lwinmm`) confirmed;
  M5b `Console` contract and M4 `AudioOut` vtable confirmed.
- **Task 1 (`platform/audio_win9x.zig` + `audio_win9x_pal.zig`) — DONE.**
  waveOut backend implementing the M4 `AudioOut` vtable
  (`waveOutOpen`/`waveOutPrepareHeader`/`waveOutWrite`/`waveOutUnprepareHeader`/
  `waveOutReset`/`waveOutClose`), 16-bit little-endian PCM at 44100/48000 Hz,
  1/2 channels; anything else is `ConfigUnsupported`, a failed open is
  `OpenFailed`. Two 500 ms buffers (`NBUF = 2`, max 96000 B each) make the
  asynchronous waveOut writes behave like the M4 blocking `write`; `drain`
  submits the final partial buffer and waits, `close` resets/unqueues/closes.
  The backend exposes free functions (the caller assembles the vtable — the D8
  pointer shape; it does not return `AudioOut`). Commit `866b260f`.
- **Task 2 (`platform/console_win9x.zig` + `console_win9x_pal.zig`) — DONE.**
  Complete nine-op `Console` backend: raw mode via Get/SetConsoleMode, keys via
  GetNumberOfConsoleInputEvents/ReadConsoleInputA (non-blocking; `VK_*` arrows,
  Enter, Esc, other characters, in-band `Key.none`), output via
  WriteConsoleA/FillConsoleOutputCharacterA/SetConsoleCursorPosition,
  width/height via GetConsoleScreenBufferInfo, cursor visibility via
  Get/SetConsoleCursorInfo. **Ctrl-C is Amendment 1, Option 3** (this is the
  defect-D5 workaround): `enterRaw` clears `ENABLE_LINE_INPUT`,
  `ENABLE_ECHO_INPUT` **and** `ENABLE_PROCESSED_INPUT`; Ctrl-C then arrives as a
  `KEY_EVENT` with `uChar == 0x03`, which `readKey` maps to `.sigint`.
  `SetConsoleCtrlHandler` is not used; an idempotent `leaveRaw` plus an
  `atexit` backstop restore the saved input mode. Known limits: Ctrl-Break still
  terminates through the default handler; console-close/shutdown restore is
  moot. Commits `d86b3441` + fix `85234e21`.
- **Task 3 (`main.zig`) — DONE.** Backend selection is compile-time via
  `@isWindows()` with an explicit `else`: `Z9PLAY_WAV_OUT` still selects the
  hermetic WAV sink on **all** platforms (test/hermetic override), else Win9x
  gets waveOut + the Win9x console, else Linux OSS `/dev/dsp` + the Linux
  console. Exit codes 0–5 are preserved; playback restores the console through
  the selected `leaveRaw_fn` on `playFail` and the final exit-0 path (Z98
  `std.os.exit` runs no `defer`). Commit `2e0f194a`.
- **Task 4 (`tests/tier_win9x.sh` + `tests/win9x_console_probe.zig`) — DONE.**
  Green **14/14** (0 failed, 0 skipped). It gates: (a) cross-build via the
  shared harness with `XRUNRC=0`, a produced **PE32 i386** executable, **no
  unresolved `zF_`/`zT_` program symbols**, a `WINMM.dll` import, and imports
  limited to KERNEL32/msvcrt/WINMM; the **`-osw --dump-c89` md5**, stable 2×;
  (b) Wine full 2 s playback with `Z9PLAY_WAV_OUT` (real waveOut not touched) —
  exit 0, `Stopped at 00:02.`, canonical 44-byte WAV + golden payload size, WAV
  parity vs `testdata/expected/sine_stereo_44100.pcm`
  (`max_delta=1`, `rms_milli=36`), deterministic 2×; (c) the Win9x console
  probe under a Wine pty asserting `entered=1,raw_changed=1,restored=1`
  (`before=503 raw=496 after=503`). SKIP-with-reason only when mingw/Wine is
  genuinely absent; a present Wine with no console is a FAIL, not a pass.
  Commits `f91eb8b2` + fix `a0a7616f`.
- **Task 5 (docs) — DONE (this commit).** New
  `examples/z98/z9play/demo/win9x_README.txt`: the manual Win98 procedure
  (cross-build/copy/run, expected console behavior, Ctrl-C Option 3 semantics,
  raw-mode restore caveat + abnormal-termination recovery, waveOut
  best-effort/format limits, and the `Z9PLAY_WAV_OUT` no-device test override).
  This section plus `README.md` record the M6 truth.

**MD5 (`-osw --dump-c89`):** `87856b43091e2bf5d992fc795d9764f2` (M6 compiler
rebuilt from current `sf/src`; stable 2×). It is distinct from the Linux
`--dump-c89` value `4c9f760ae825d7fcf91cbf7a2500a4a4` recorded for M5b because
the target changes the emitted platform closure.

**Defect status (numbering disambiguation).** `examples/torrent_example_defects.md`
was **reset 2026-10-16**: the old M0–M5 **D1–D8** are all FIXED at root cause
and live in history. Under the **current** numbering: **D1** (optional-of-
aggregate function-pointer return) is **FIXED**; **D2** (`@isWindows()`
dead-arm module leak) is **FIXED** — both at root cause by the 2026-10-17
compiler D1/D2 parity milestone, and both are the reason M6 must build from
current `sf/src` rather than a pre-fix binary. **D3** (conditional `@import`
lazy-load gap) and **D4** (static-analyzer cluster) remain **OPEN**. **D5**
(`extern fn` with a body silently treated as a declaration; no way to define a
non-cdecl/stdcall function) is **OPEN**; M6 works around D5 with Amendment 1
Option 3 above (no SetConsoleCtrlHandler/stdcall callback), and the defect entry
records the clean-reject / stdcall-definition fixes for a future compiler plan.

- M6 chain: `866b260f` (Win9x waveOut backend) → `d86b3441` + `85234e21`
  (Win9x console backend + Option 3 Ctrl-C fix) → `2e0f194a` (`@isWindows()`
  backend selection) → `f91eb8b2` + `a0a7616f` (Win9x tier + real
  undefined-symbol check; the M6 working commit) → this docs commit. The M6
  plan's Task 6 (M7 amendment review) is a separate dispatch; the plan carries
  no status field, so there is nothing to flip to "done". Example-only: no
  `sf/src` change, no seed rotation, and the Linux gates/behavior are unchanged
  (the `Z9PLAY_WAV_OUT` path still wins on every platform).
