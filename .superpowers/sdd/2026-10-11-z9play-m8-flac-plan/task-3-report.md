# M8 Task 3 report — `tier_flac.sh`

**Status:** COMPLETE.

**Commit (a):** `903ea2ab487c51f1433a903a80bb484f4931981f` —
`example(z9play): M8 FLAC tier`

**Seed:** v102 `/tmp/z9play_seed/zig1_5_clean`
(`b299b4b435e624d0ddbd2edde681cbc3`); archive
`release/seed/zig1-seed.tgz` md5 `702f34d87b7e6bf401dd206d2517dbee`
(unchanged).

## Tier design / fixtures

`examples/z98/z9play/tests/tier_flac.sh` (new, mode 100755) is a standalone
POSIX-sh gate. It:

1. resolves the v102 seed (env `ZIG`, conventional scratch paths, or rebuild
   from `release/seed/zig1-seed.tgz`) and asserts the fixed-point md5;
2. builds `main.zig` and `ui.zig` with `-fsafe` through the emitted
   `build_target.sh linux` recipe;
3. obtains `flac` with the committed no-root `tests/get_flac_tools.sh`
   (private apt state/cache + `dpkg-deb -x`; no reuse of a host install);
4. regenerates three `.flac` fixtures from the committed raw PCM goldens with
   the T2 recipe, taking channels/rate from `<name>.meta`:

   ```
   flac -f --force-raw-format --endian=little --sign=signed \
       --channels=<ch> --bps=16 --sample-rate=<sr> \
       -o <name>.flac testdata/expected/<name>.pcm
   ```

   Fixtures: `sine_mono_44100` (1 ch, 44100 Hz), `sine_stereo_44100`
   (2 ch, 44100 Hz), `sine_stereo_48000` (2 ch, 48000 Hz). Each fixture is
   decoded back with `flac -d --force-raw-format ...` to the comparison
   golden, and that golden is required to be byte-identical to the source PCM;
5. drives the public Player path `z9play --wav <in.flac> <out.wav>` for every
   fixture and asserts exit 0, `wav: ended ... monotonic=1`, a canonical
   44-byte WAV header with the exact payload size, payload byte-exactness
   against the `flac -d` golden (FLAC is lossless; the M3 tolerance is not
   used), and 3x determinism by raw-PCM SHA-1;
6. runs one mixed `.ogg`/`.flac` TUI session (below);
7. runs the OGG regression tiers and requires the exact historical counts
   (`tier_cli` 23/0, `tier_tui` 40/0, `tier_audio` 27/0);
8. emits/builds `main.zig` for default `-osw` and checks the Win9x profile;
9. records `--dump-c89` md5s for `main.zig` and `ui.zig`, stable 2x.

Scratch lives only under `$OUT` (default `/tmp/z9play_tier_flac`); the tier
does not write into the repository. Child regression tiers use short scratch
paths under `$OUT/r/{cli,tui,audio}` so `tier_tui`'s 80x25 path-pane check is
not truncated by the parent scratch path.

## Gates

Command (run twice, sequentially, from the repo root; exit code checked):

```
$ bash examples/z98/z9play/tests/tier_flac.sh
```

Both runs exited 0 with the same summary: **59 passed, 0 failed**.

### Run 1 — exit 0

```
== seed ==
compiler: /tmp/z9play_seed/zig1_5_clean
md5:      b299b4b435e624d0ddbd2edde681cbc3
ok   - seed v102 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3

== building z9play main.zig and ui.zig (binding recipe, -fsafe) ==
ok   - main.zig -fsafe compile + emitted build_target.sh linux
ok   - ui.zig -fsafe compile + emitted build_target.sh linux

== no-root flac tool (tests/get_flac_tools.sh) ==
ok   - flac acquired without root (flac 1.4.2)
flac: /tmp/z9play_tier_flac/flac_tools/sys/usr/bin/flac
LD_LIBRARY_PATH: /tmp/z9play_tier_flac/flac_tools/sys/etc:/tmp/z9play_tier_flac/flac_tools/sys/lib/x86_64-linux-gnu:/tmp/z9play_tier_flac/flac_tools/sys/lib64:/tmp/z9play_tier_flac/flac_tools/sys/usr/lib/x86_64-linux-gnu:/tmp/z9play_tier_flac/flac_tools/sys/usr/lib/x86_64-linux-gnu/gconv:

== generate .flac fixtures from raw PCM goldens (T2 recipe) ==
ok   - sine_mono_44100: generated .flac (1 ch @ 44100Hz, 21753 bytes)
ok   - sine_mono_44100: flac -d golden produced
ok   - sine_mono_44100: flac -d golden is byte-identical to the source golden PCM
ok   - sine_stereo_44100: generated .flac (2 ch @ 44100Hz, 74017 bytes)
ok   - sine_stereo_44100: flac -d golden produced
ok   - sine_stereo_44100: flac -d golden is byte-identical to the source golden PCM
ok   - sine_stereo_48000: generated .flac (2 ch @ 48000Hz, 49289 bytes)
ok   - sine_stereo_48000: flac -d golden produced
ok   - sine_stereo_48000: flac -d golden is byte-identical to the source golden PCM

== Player --wav vs flac -d golden (exact) + determinism 3x ==
ok   - sine_mono_44100: --wav exit 0
ok   - sine_mono_44100: player ended + position monotonic (wav: ended frames=44100 pos_ms=1000 monotonic=1)
ok   - sine_mono_44100: canonical WAV header + payload size (88244 bytes)
ok   - sine_mono_44100: payload byte-exact vs flac -d golden (sha1=538300de08246ac477de08656adcedf4b8c282b6)
ok   - sine_mono_44100: deterministic 3x (sha1=538300de08246ac477de08656adcedf4b8c282b6)
ok   - sine_stereo_44100: --wav exit 0
ok   - sine_stereo_44100: player ended + position monotonic (wav: ended frames=88200 pos_ms=2000 monotonic=1)
ok   - sine_stereo_44100: canonical WAV header + payload size (352844 bytes)
ok   - sine_stereo_44100: payload byte-exact vs flac -d golden (sha1=0e31277ffee2bd62a707fc9732e9eb7281da58df)
ok   - sine_stereo_44100: deterministic 3x (sha1=0e31277ffee2bd62a707fc9732e9eb7281da58df)
ok   - sine_stereo_48000: --wav exit 0
ok   - sine_stereo_48000: player ended + position monotonic (wav: ended frames=48000 pos_ms=1000 monotonic=1)
ok   - sine_stereo_48000: canonical WAV header + payload size (192044 bytes)
ok   - sine_stereo_48000: payload byte-exact vs flac -d golden (sha1=79bb14ed3c7f342a1cf215a2ca0c618ba8750605)
ok   - sine_stereo_48000: deterministic 3x (sha1=79bb14ed3c7f342a1cf215a2ca0c618ba8750605)

== mixed .ogg/.flac selection through the TUI (pty) ==
ok   - mixed-listing-both
ok   - mixed-initial-selection-parent
ok   - mixed-filters-non-audio
ok   - mixed-wav-absent-before-play
ok   - mixed-select-flac
ok   - mixed-opens-flac
ok   - mixed-flac-volume-100
ok   - mixed-flac-playing
ok   - mixed-flac-ended
ok   - mixed-flac-wav-complete
ok   - mixed-flac-wav-copied
ok   - mixed-select-ogg
ok   - mixed-opens-ogg
ok   - mixed-ogg-playing
ok   - mixed-ogg-ended
ok   - mixed-ogg-wav-complete
ok   - mixed-ogg-wav-copied
ok   - mixed-q-exits-rc0
driver: total=18 passed=18 failed=0
mixed pty log: /tmp/z9play_tier_flac/mixed.log (32516 bytes)
ok   - mixed TUI FLAC payload byte-exact vs flac -d golden
ok   - mixed TUI OGG payload tolerance max_delta=1 rms_milli=39 (<= 2 / 100)

== OGG regression tiers ==
tier_cli: == tier_cli summary: 23 passed, 0 failed == (rc=0)
ok   - tier_cli green (23 passed, 0 failed)
tier_tui: == tier_tui summary: 40 passed, 0 failed == (rc=0)
ok   - tier_tui green (40 passed, 0 failed)
tier_audio: == tier_audio summary: 27 passed, 0 failed == (rc=0)
ok   - tier_audio green (27 passed, 0 failed)

== Win9x gate: main.zig -osw emit/build + PE/import check ==
ok   - main.zig -osw emit is the 9x no-CRT recipe (DZIG_NO_CRT, nostdlib, kernel32+winmm)
ok   - emitted Win9x build produced exe (670696 bytes)
          31 | static usize pal_strlen(const char* s)
             |              ^~~~~~~~~~
       Built: /tmp/z9play_tier_flac/z9play.exe
ok   - file: /tmp/z9play_tier_flac/z9play.exe: PE32 executable (console) Intel 80386 (stripped to external PDB), for MS Windows, 7 sections
imports: KERNEL32.DLL WINMM.DLL 
ok   - imports are exactly KERNEL32 + WINMM (no msvcrt)
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
       DLL KERNEL32.DLL
       DLL WINMM.DLL
       IMPORT GATE PASS (9x): /tmp/z9play_tier_flac/z9play.exe
note: real Win98/Me hardware verification is operator-pending (not claimed)

== --dump-c89 md5 (main.zig, ui.zig; stable 2x) ==
--dump-c89 main.zig md5: e56af7916edd199e796f3ef11d5e49c4
ok   - --dump-c89 main.zig md5 recorded stable 2x: e56af7916edd199e796f3ef11d5e49c4
--dump-c89 ui.zig md5: 22676fd997471df1c4c3a3f04397121d
ok   - --dump-c89 ui.zig md5 recorded stable 2x: 22676fd997471df1c4c3a3f04397121d

== tier_flac summary: 59 passed, 0 failed ==
TIER_FLAC PASS
```

### Run 2 — exit 0

```
== seed ==
compiler: /tmp/z9play_seed/zig1_5_clean
md5:      b299b4b435e624d0ddbd2edde681cbc3
ok   - seed v102 compiler md5 is the fixed point b299b4b435e624d0ddbd2edde681cbc3

== building z9play main.zig and ui.zig (binding recipe, -fsafe) ==
ok   - main.zig -fsafe compile + emitted build_target.sh linux
ok   - ui.zig -fsafe compile + emitted build_target.sh linux

== no-root flac tool (tests/get_flac_tools.sh) ==
ok   - flac acquired without root (flac 1.4.2)
flac: /tmp/z9play_tier_flac/flac_tools/sys/usr/bin/flac
LD_LIBRARY_PATH: /tmp/z9play_tier_flac/flac_tools/sys/etc:/tmp/z9play_tier_flac/flac_tools/sys/lib/x86_64-linux-gnu:/tmp/z9play_tier_flac/flac_tools/sys/lib64:/tmp/z9play_tier_flac/flac_tools/sys/usr/lib/x86_64-linux-gnu:/tmp/z9play_tier_flac/flac_tools/sys/usr/lib/x86_64-linux-gnu/gconv:

== generate .flac fixtures from raw PCM goldens (T2 recipe) ==
ok   - sine_mono_44100: generated .flac (1 ch @ 44100Hz, 21753 bytes)
ok   - sine_mono_44100: flac -d golden produced
ok   - sine_mono_44100: flac -d golden is byte-identical to the source golden PCM
ok   - sine_stereo_44100: generated .flac (2 ch @ 44100Hz, 74017 bytes)
ok   - sine_stereo_44100: flac -d golden produced
ok   - sine_stereo_44100: flac -d golden is byte-identical to the source golden PCM
ok   - sine_stereo_48000: generated .flac (2 ch @ 48000Hz, 49289 bytes)
ok   - sine_stereo_48000: flac -d golden produced
ok   - sine_stereo_48000: flac -d golden is byte-identical to the source golden PCM

== Player --wav vs flac -d golden (exact) + determinism 3x ==
ok   - sine_mono_44100: --wav exit 0
ok   - sine_mono_44100: player ended + position monotonic (wav: ended frames=44100 pos_ms=1000 monotonic=1)
ok   - sine_mono_44100: canonical WAV header + payload size (88244 bytes)
ok   - sine_mono_44100: payload byte-exact vs flac -d golden (sha1=538300de08246ac477de08656adcedf4b8c282b6)
ok   - sine_mono_44100: deterministic 3x (sha1=538300de08246ac477de08656adcedf4b8c282b6)
ok   - sine_stereo_44100: --wav exit 0
ok   - sine_stereo_44100: player ended + position monotonic (wav: ended frames=88200 pos_ms=2000 monotonic=1)
ok   - sine_stereo_44100: canonical WAV header + payload size (352844 bytes)
ok   - sine_stereo_44100: payload byte-exact vs flac -d golden (sha1=0e31277ffee2bd62a707fc9732e9eb7281da58df)
ok   - sine_stereo_44100: deterministic 3x (sha1=0e31277ffee2bd62a707fc9732e9eb7281da58df)
ok   - sine_stereo_48000: --wav exit 0
ok   - sine_stereo_48000: player ended + position monotonic (wav: ended frames=48000 pos_ms=1000 monotonic=1)
ok   - sine_stereo_48000: canonical WAV header + payload size (192044 bytes)
ok   - sine_stereo_48000: payload byte-exact vs flac -d golden (sha1=79bb14ed3c7f342a1cf215a2ca0c618ba8750605)
ok   - sine_stereo_48000: deterministic 3x (sha1=79bb14ed3c7f342a1cf215a2ca0c618ba8750605)

== mixed .ogg/.flac selection through the TUI (pty) ==
ok   - mixed-listing-both
ok   - mixed-initial-selection-parent
ok   - mixed-filters-non-audio
ok   - mixed-wav-absent-before-play
ok   - mixed-select-flac
ok   - mixed-opens-flac
ok   - mixed-flac-volume-100
ok   - mixed-flac-playing
ok   - mixed-flac-ended
ok   - mixed-flac-wav-complete
ok   - mixed-flac-wav-copied
ok   - mixed-select-ogg
ok   - mixed-opens-ogg
ok   - mixed-ogg-playing
ok   - mixed-ogg-ended
ok   - mixed-ogg-wav-complete
ok   - mixed-ogg-wav-copied
ok   - mixed-q-exits-rc0
driver: total=18 passed=18 failed=0
mixed pty log: /tmp/z9play_tier_flac/mixed.log (32516 bytes)
ok   - mixed TUI FLAC payload byte-exact vs flac -d golden
ok   - mixed TUI OGG payload tolerance max_delta=1 rms_milli=39 (<= 2 / 100)

== OGG regression tiers ==
tier_cli: == tier_cli summary: 23 passed, 0 failed == (rc=0)
ok   - tier_cli green (23 passed, 0 failed)
tier_tui: == tier_tui summary: 40 passed, 0 failed == (rc=0)
ok   - tier_tui green (40 passed, 0 failed)
tier_audio: == tier_audio summary: 27 passed, 0 failed == (rc=0)
ok   - tier_audio green (27 passed, 0 failed)

== Win9x gate: main.zig -osw emit/build + PE/import check ==
ok   - main.zig -osw emit is the 9x no-CRT recipe (DZIG_NO_CRT, nostdlib, kernel32+winmm)
ok   - emitted Win9x build produced exe (670696 bytes)
          31 | static usize pal_strlen(const char* s)
             |              ^~~~~~~~~~
       Built: /tmp/z9play_tier_flac/z9play.exe
ok   - file: /tmp/z9play_tier_flac/z9play.exe: PE32 executable (console) Intel 80386 (stripped to external PDB), for MS Windows, 7 sections
imports: KERNEL32.DLL WINMM.DLL 
ok   - imports are exactly KERNEL32 + WINMM (no msvcrt)
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
       DLL KERNEL32.DLL
       DLL WINMM.DLL
       IMPORT GATE PASS (9x): /tmp/z9play_tier_flac/z9play.exe
note: real Win98/Me hardware verification is operator-pending (not claimed)

== --dump-c89 md5 (main.zig, ui.zig; stable 2x) ==
--dump-c89 main.zig md5: e56af7916edd199e796f3ef11d5e49c4
ok   - --dump-c89 main.zig md5 recorded stable 2x: e56af7916edd199e796f3ef11d5e49c4
--dump-c89 ui.zig md5: 22676fd997471df1c4c3a3f04397121d
ok   - --dump-c89 ui.zig md5 recorded stable 2x: 22676fd997471df1c4c3a3f04397121d

== tier_flac summary: 59 passed, 0 failed ==
TIER_FLAC PASS
```

The two captured logs were byte-identical (`diff` empty, 98 lines each).

## Mixed selection

One pty session runs the TUI in a scratch directory containing `a.flac`
(generated from `sine_stereo_44100.pcm`), `b.ogg` (committed `short.ogg`), and
`notes.txt`. The driver:

- observes both audio files in the listing and no `notes.txt`;
- raises the volume to 100 (`++++`), so the mixer is the identity, and sees
  `vol 100%` once a track is playing;
- moves from the initial `> ..` to `> a.flac`, opens it, observes
  `Now: a.flac`, `State: Playing`, then `State: Ended`, and copies the
  completed 44 + 352800 = 352844-byte WAV;
- moves to `> b.ogg`, opens it, observes `Now: b.ogg`, `State: Playing`, then
  `State: Ended`, and copies the completed 44 + 26460 = 26504-byte WAV;
- quits with `q`, exit 0.

Post-run payload checks: FLAC is byte-exact against the `flac -d` golden; OGG
is within the M3 tolerance (`max_delta=1`, `rms_milli=39`, bounds 2 / 100).
This exercises both selector arms in the same directory through the public TUI
path; it is not a build-only check.

## OGG regression / seed / dumps / diff

- `tier_cli`: 23 passed, 0 failed (rc 0)
- `tier_tui`: 40 passed, 0 failed (rc 0)
- `tier_audio`: 27 passed, 0 failed (rc 0)
- seed binary md5 `b299b4b435e624d0ddbd2edde681cbc3`; seed archive md5
  `702f34d87b7e6bf401dd206d2517dbee` (unchanged)
- `--dump-c89` md5, stable 2x:
  - `main.zig`: `e56af7916edd199e796f3ef11d5e49c4`
  - `ui.zig`: `22676fd997471df1c4c3a3f04397121d`
- commit (a) touches only `examples/z98/z9play/tests/tier_flac.sh`
  (create mode 100755, 661 lines). No source, std, compiler, fixture, or seed
  change.

## Win9x build gate

`main.zig` emitted with `-osw`, built through the emitted mingw recipe:
`670696`-byte PE32 i386 console executable, imports exactly
`KERNEL32.DLL WINMM.DLL`, no msvcrt, and
`scripts/win32_cross/check_win9x_imports.sh ... 9x` PASS. Real Win98/Me
hardware verification remains operator-pending and is not claimed.

## Concerns

- `--info`, `--dump-setup`, and `--pcm` remain Vorbis-only per T2 scope; the
  tier exercises FLAC through `--wav` and the interactive/TUI path, as scoped.
- FLAC frame CRC-16 is still not verified (T2 explicitly allowed this); header
  CRC-8 is. The tier's exact golden comparison is independent of that choice.
- The three fixtures are regenerated per run, so the gate depends on the
  no-root `get_flac_tools.sh` download path; a network/apt failure aborts the
  tier with evidence rather than fabricating fixtures.
- `tier_tui`'s directory-pane check requires the scratch path to fit the pane;
  the tier therefore keeps child scratch paths short under `$OUT/r/...`.
- Win9x is emission/build/import-gated only; no hardware claim.
