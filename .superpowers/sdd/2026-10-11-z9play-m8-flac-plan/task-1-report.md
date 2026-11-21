# M8 Task 1 report — decoder abstraction (Vorbis via selector)

**Status:** COMPLETE (no behavior change; no FLAC implementation).

**Commit (a):** `c4b53d84621c6bbbdb2410af217a8215e8e373ce` —
`example(z9play): decoder abstraction (vorbis via selector)`

**Seed:** v102 `/tmp/z9play_seed/zig1_5_clean`
(`b299b4b435e624d0ddbd2edde681cbc3`); archive
`release/seed/zig1-seed.tgz` md5 `702f34d87b7e6bf401dd206d2517dbee`
(unchanged).

## Selector design / API

New `examples/z98/z9play/decoder.zig` (frontend-side, no `player.zig`
change):

- `VorbisDecoder { vc: *player.VorbisCtx }`.
- `FlacDecoder {}` — intentionally empty placeholder; `flac.zig` and the FLAC
  context land in Task 2.
- `DecoderKind = union(enum) { vorbis: VorbisDecoder, flac: FlacDecoder }`.
- `decoderOpenVorbis(out: *player.Decoder, vc: *player.VorbisCtx) void` fills
  the caller-owned vtable via an out-param. It never returns `player.Decoder`
  (or a struct embedding one) by value, preserving the D8-safe
  caller-owned/by-pointer shape.
- OGG/Vorbis header parsing and arena ownership stay in the frontends;
  `player.zig` remains codec-agnostic and unchanged.

## main/ui routing

- `main.zig`: added `const decoder = @import("decoder.zig");`.
  - `--wav` site (`main.zig:498`): literal assembly replaced with
    `var decv: player.Decoder = undefined; decoder.decoderOpenVorbis(&decv, vc);`
  - interactive site (`main.zig:748`): same replacement.
- `ui.zig`: added the same import; `playTrack` (`ui.zig:522`) replaces the
  `g_decoder` literal with `decoder.decoderOpenVorbis(&g_decoder, vc);`.
- All values (`ctx`, `next_fn`, `max_frames`, `sample_rate`, `channels`,
  `total_frames`) are byte-for-byte the same fields as the removed literals.

## Gates (command + observed output)

### Seed / workspace

```
$ md5sum /tmp/z9play_seed/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/z9play_seed/zig1_5_clean
$ md5sum release/seed/zig1-seed.tgz
702f34d87b7e6bf401dd206d2517dbee  release/seed/zig1-seed.tgz
$ git status --short
 M examples/z98/z9play/main.zig
 M examples/z98/z9play/ui.zig
?? examples/z98/z9play/decoder.zig
?? run.err
```

`run.err` left untouched.

### Linux `-fsafe` compile + emitted build (main.zig)

```
$ rm -rf /tmp/z9play_t1_main && mkdir -p /tmp/z9play_t1_main
$ timeout 180 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_t1_main \
      examples/z98/z9play/main.zig
main_emit_rc=0
$ sh /tmp/z9play_t1_main/build_target.sh linux /tmp/z9play_t1_main/prog
Built: /tmp/z9play_t1_main/prog
main_build_rc=0
-rwxr-xr-x 1 node node 605820 ... /tmp/z9play_t1_main/prog
```

### Linux `-fsafe` compile + emitted build (ui.zig)

```
$ rm -rf /tmp/z9play_t1_ui && mkdir -p /tmp/z9play_t1_ui
$ timeout 180 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/z9play_t1_ui \
      examples/z98/z9play/ui.zig
ui_emit_rc=0
$ sh /tmp/z9play_t1_ui/build_target.sh linux /tmp/z9play_t1_ui/prog
Built: /tmp/z9play_t1_ui/prog
ui_build_rc=0
-rwxr-xr-x 1 node node 603556 ... /tmp/z9play_t1_ui/prog
```

### Existing tiers (seed v102)

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

`tier_cli` startup/metadata/playback assertions unchanged, including:

```
ok   - startup line: z9play: examples/z98/z9play/testdata/sine_stereo_44100.ogg  00:02  2ch 44100Hz
ok   - status line at t=00:00 present (CR redraw)
ok   - later status line at t=00:01 present (per-second cadence)
ok   - hermetic WAV sink written (2.000 s = 352844 bytes)
```

### Win9x compile/build + import gate

```
$ ZIG=/tmp/z9play_seed/zig1_5_clean sh examples/z98/z9play/tests/tier_win9x.sh
== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
TIER_WIN9X PASS
tier_win9x_rc=0
```

`tier_tui.sh` also covered the `ui.zig` root:

```
ok   - ui.zig -osw emit produced build_target.sh (default 9x no-CRT)
ok   - emitted build_target.sh mingw produced exe (602856 bytes)
ok   - file: .../z9play-tui.exe: PE32 executable (console) Intel 80386 ... 7 sections
imports: KERNEL32.DLL WINMM.DLL
ok   - no msvcrt import
ok   - check_win9x_imports.sh 9x whitelist PASS
note: real Win98/Me hardware verification is operator-pending (not claimed)
```

### `--dump-c89` old -> new (record only, not a gate)

Measured with seed v102; old values from a pristine `git archive HEAD` copy
under `/tmp/t1_oldroot` at the same relative entry paths (the old `ui.zig`
measurement reproduces the recorded M7 pin `e7bc57a2...`, validating the
method):

| root | old md5 | new md5 |
|---|---|---|
| `main.zig` | `75133080832b3ed7dbfb8b7a935c7e5e` | `1a0e54402c2625dfbbb338ea65084486` |
| `ui.zig` | `e7bc57a2a38a72cb83f51a1ce7497239` | `38e4e1ca2346ae0f3578d737306155a6` |

The move is expected from splitting the vtable assembly into `decoder.zig`
(module split), not a behavior change; both new values were stable over the
tiers' 2x checks.

### Diff scope

```
$ git diff --stat HEAD~1 HEAD
 examples/z98/z9play/decoder.zig | 50 +++++++++++++++++++++++++++++++++++++++++
 examples/z98/z9play/main.zig    | 21 +++++------------
 examples/z98/z9play/ui.zig      | 10 ++-------
 3 files changed, 57 insertions(+), 24 deletions(-)
```

Only `decoder.zig`, `main.zig`, `ui.zig` changed. No `player.zig`, compiler,
std, seed, `NOTES.md`, `README.md`, or test changes.

## Concerns

- `DecoderKind` exists as specified but is not yet constructed or dispatched:
  Task 1 only routes the Vorbis path through `decoderOpenVorbis`. Task 2 owns
  the `flac` arm, signature/extension selection, and any `decoderOpen`
  dispatch. This is intentional per the task brief/context, not a behavior
  gap.
- `FlacDecoder` is an empty placeholder so the union arm type exists without
  implementing FLAC. Task 2 will replace it with the real `flac.zig` context.
- `--dump-c89` md5s moved (module split); recorded above. No gate depends on
  the old values.
- Win9x behavior is emission/build/import-gated only; no hardware claim.
