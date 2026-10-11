# z9play — Z98 Example

**Status:** M0 complete (Tasks 0–5). M1 complete (Tasks 0–5, closed out): setup header parse + codebook construction, exposed via `--dump-setup`. M2 (native pure-Z98 `std_math` f64 `sqrt`/`sin`/`cos`) complete and closed out (Tasks 0–6): std fixture registered, `tests/tier_math.sh` gate green, docs, and the Task 6 M3 amendment review. M3 (audio decode → interleaved s16 PCM) complete and closed out (Tasks 0–6): `dsp`/`floor`/`residue`/`decode`, `z9play --pcm <in.ogg> <out.wav>` (canonical 44-byte-header PCM WAV), `tests/tier_decode.sh` (tolerance + 3× determinism vs the `oggdec` goldens), and the Task 6 M4 amendment review (no amendment needed). M4 (audio output + ring buffer + Player core) complete and closed out (Tasks 0–5): the `AudioOut` vtable (`platform/audio.zig`), the hermetic WAV sink (`platform/audio_wavfile.zig`) and Linux OSS `/dev/dsp` backend (`platform/audio_oss.zig`/`audio_oss_pal.zig`), the shared `Player` + double-buffer `RingBuffer` (`player.zig`), the `z9play --wav <in.ogg> <out.wav>` gate subcommand, and `tests/tier_audio.sh` (tolerance + completion/monotonicity + 3× determinism vs the M3 goldens; 27/27).

**Entry file:** `main.zig`

**Working commit:** `61e93e72` (`example(z9play): M4 audio tier`; the last commit of the M4 audio surface, pinned at M4 closeout; the docs commit that follows also bumps the `--version` string to `(M4)`, so the recorded MD5 is measured at that closeout tree, not at `61e93e72`). Prior closeouts: M3 `c7af78ac` (`example(z9play): M3 --pcm + tier_decode`; the M3 `--pcm` + `tier_decode` commit — the last commit of the M3 decode surface, pinned at M3 closeout); M2 `b5ca08d2` (`feat(std_math): f64 sin/cos (pure Z98)`; the last `std_math` surface commit; full M2 chain `4d6fb5dd` (f64 `sqrt`) → `b5ca08d2` (f64 `sin`/`cos`) → `52958705` (`tests/tier_math.sh`) → `6844aad5` (docs)); M1 `100c35ce` (`example(z9play): M1 --dump-setup + tier_setup`); M0 `27b1fddf` (`example(z9play): z9play --info CLI + tier_info gate`). **M3 decode chain:** `bb211810` (IMDCT + window + overlap-add) → `b497323a` (floor1) → `d925cb55` (residue type 0/1/2) → `16ae3eea` (packet → PCM) → `de48b5cf` (docs: D7 + cumulative-defect warning) → `c7af78ac` (M3 `--pcm` + `tier_decode`; this closeout).

**MD5 (`--dump-c89`):** `d695bf99dadb7f6dbbc0f2a94bb42f43` (seed `zig1_5_clean`, seed **v97**; stable 2×; M4). **M4 changed this value** (M3 was `a5f208b5c8034e9c9f2be9c6800913f4`): `--dump-c89` for `main.zig` transitively emits every imported module, and M4 makes `main.zig` import the audio/player closure — `platform/audio.zig`, `platform/audio_wavfile.zig`, `platform/audio_oss.zig`, `platform/audio_oss_pal.zig`, and `player.zig` — and adds the `--wav` subcommand, so the whole M4 audio graph now appears in the dump (alongside the M3 decode closure and the M2 `std_math` functions). The docs commit also bumps the `--version` string `(M3)`→`(M4)` in `cli.zig`, a same-length literal change that likewise shifts the dump content; the value above is measured at that closeout tree. The z9play **build seed / fixed point is unchanged** (`bafbba9454cd2b134bdc3d50c65384e0`; M4 is example-only, no compiler change). Prior: M3 `a5f208b5c8034e9c9f2be9c6800913f4`, M2 `88ad559ce5e4a3dae6f11a0c52b35792`, M1 `344c26ed89dd0830443fa5e16b870ec0`, M0 `--info`-only `ba86cbe8b2229667f4c8084a0b0e75da`.

Spec: `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).
M0 plan: `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md`.

## Build Recipe (binding for M0)

The seed is built from `release/seed/zig1-seed.tgz` (current seed **v97**):

```bash
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9play_seed
# two-hop closure OK: hop1 == hop2 == bafbba9454cd2b134bdc3d50c65384e0 (v97)

mkdir -p /tmp/z9play_out
timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_out \
    examples/z98/z9play/main.zig
sh /tmp/z9play_out/build_target.sh linux /tmp/z9play_out/prog
```

All tiers run under **`-fsafe`**.

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

### `--dump-c89` (for the MD5 above)

```bash
timeout 120 /tmp/z9play_seed/zig1_5_clean --dump-c89 examples/z98/z9play/main.zig | md5sum
# d695bf99dadb7f6dbbc0f2a94bb42f43  -
# (M3, before M4's audio/player import closure + the (M4) version bump: a5f208b5c8034e9c9f2be9c6800913f4;
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
