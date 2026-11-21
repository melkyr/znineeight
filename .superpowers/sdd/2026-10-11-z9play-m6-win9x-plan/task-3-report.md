# Task 3 report — backend selection via `@isWindows()`

**Status:** DONE.

**Commit sha:** `2e0f194a` `example(z9play): select Win9x backends via @isWindows()`
(1 file: `examples/z98/z9play/main.zig`).

## What changed

- `examples/z98/z9play/main.zig` — added
  `const cwin = @import("platform/console_win9x.zig");` and platform-selected
  the `Console` assembly with an explicit `else`:
  - `@isWindows()` arm assembles the vtable from `cwin.*` with a
    `cwin.ConsoleWinState`;
  - `else` arm assembles it from `con.*` (Linux) with a `con.ConsoleLinState`.
  - `cs.enterRaw_fn(cs.state)` is still called once after selection;
    `interactive` is read from the selected state's `entered` flag
    (`entered_ptr.*`) after `enterRaw`, preserving M5's behavior.
- T1's audio block is unchanged: `Z9PLAY_WAV_OUT` → `audio_wavfile` on every
  platform; else `@isWindows()` → `audio_win9x`; explicit `else` →
  `audio_oss`. Exit 4 on audio-open failure in all three arms.
- Exit paths: every `std.os.exit` after `enterRaw` either goes through
  `playFail` (`cs.leaveRaw_fn(cs.state)` first, `main.zig:166`) or the final
  path (`cs.leaveRaw_fn(cs.state)` at `main.zig:896`, then `exit(0)` at
  `main.zig:905`). No `defer` added. Exit codes 0–5 are unchanged.
- `cli.zig` was not modified (args/exit codes are platform-neutral).

### Deviation from the context's suggested state declaration

The context suggested both state vars at function scope
(`var st_lin: con.ConsoleLinState = undefined;` /
`var st_win: cwin.ConsoleWinState = undefined;`). That shape unconditionally
references the `cwin` type, so Z98 emitted `console_win9x`/`console_win9x_pal`
on the Linux target and the Linux build failed on `windows.h`:

```sh
timeout 180 /tmp/z9play_m6/zig1_5_clean -fsafe -o /tmp/m6t3_lin \
    examples/z98/z9play/main.zig    # ZIGRC=0
sh /tmp/m6t3_lin/build_target.sh linux /tmp/m6t3_lin/prog
# console_win9x_pal_BD404AB2.h:6:10: fatal error: windows.h: No such file or directory
# BUILDRC=1
```

The final shape declares each backend state inside its own `if`/`else` arm
(so the wrong-platform type is only referenced in a comptime-dead arm) and
keeps a target-neutral `entered_ptr: *bool` to read the selected state's
`entered` after `enterRaw`. The explicit `else` and both-arms-valid-C property
are unchanged. No other task-3 scope change.

## Both-target evidence

### Linux (`-osl`) build + run

```sh
timeout 180 /tmp/z9play_m6/zig1_5_clean -fsafe -o /tmp/m6t3_lin_final \
    examples/z98/z9play/main.zig
# ZIGRC=0
sh /tmp/m6t3_lin_final/build_target.sh linux /tmp/m6t3_lin_final/prog
# BUILDRC=0 ; Built: /tmp/m6t3_lin_final/prog
/tmp/m6t3_lin_final/prog --info examples/z98/z9play/testdata/tagged_unicode.ogg
# RUNRC=0
# channels=2
# sample_rate=44100
# duration_s=1.000
```

Linux dump has the Linux modules and **not** the Win9x ones:

```sh
timeout 180 /tmp/z9play_m6/zig1_5_clean -osl --dump-c89 \
    --output-dir /tmp/m6t3_ldump_final examples/z98/z9play/main.zig
# LDUMPRC=0
# linux dump win9x console count: 0
# linux dump linux console count: 4
# linux dump audio_win9x count: 0
# linux dump audio_oss count: 4
```

### Windows (`-osw`) cross build + run

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/main.zig /tmp/m6t3_ws_final \
    /tmp/m6t3_ws_final/z9play.exe -lwinmm
# dump: rc=0 error_brk=0 panic=0 c=32 link ok
# XRUNRC=0
file /tmp/m6t3_ws_final/z9play.exe
# PE32 executable (console) Intel 80386, for MS Windows, 17 sections
```

`-osw` dump has the Win9x modules and **not** the Linux ones:

```sh
# osw dump win9x console count: 6
# osw dump linux console count: 0
# osw dump audio_win9x count: 6
# osw dump audio_oss count: 0
```

Hermetic Wine smoke of the real exe (`Z9PLAY_WAV_OUT`, redirected console):

```sh
WINEDEBUG=-all Z9PLAY_WAV_OUT='Z:\tmp\m6t3_wine\out.wav' timeout 90 wine \
    /tmp/m6t3_ws_final/z9play.exe \
    'Z:\workspace\znineeight\examples\z98\z9play\testdata\tagged_unicode.ogg'
# WINE_RC=0
# /tmp/m6t3_wine/out.wav: 176444 bytes
```

(No real Win9x hardware run; that remains Task 4/5 scope.)

### New `-osw --dump-c89` md5 (2× stable)

```sh
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 \
    examples/z98/z9play/main.zig > /tmp/m6t3_probe_final/osw1.c89   # RC1=0
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 \
    examples/z98/z9play/main.zig > /tmp/m6t3_probe_final/osw2.c89   # RC2=0
md5sum /tmp/m6t3_probe_final/osw1.c89 /tmp/m6t3_probe_final/osw2.c89
# 87856b43091e2bf5d992fc795d9764f2  osw1.c89
# 87856b43091e2bf5d992fc795d9764f2  osw2.c89
```

New md5: **`87856b43091e2bf5d992fc795d9764f2`**.

## Linux tiers (post-change)

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t3_tier_info \
    sh examples/z98/z9play/tests/tier_info.sh
# == tier_info summary: 20 passed, 0 failed ==
# TIER_INFO PASS

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t3_tier_setup \
    sh examples/z98/z9play/tests/tier_setup.sh
# == tier_setup summary: 21 passed, 0 failed ==
# TIER_SETUP PASS

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t3_tier_audio \
    sh examples/z98/z9play/tests/tier_audio.sh
# == tier_audio summary: 27 passed, 0 failed ==
# TIER_AUDIO PASS

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t3_tier_cli \
    sh examples/z98/z9play/tests/tier_cli.sh
# --dump-c89 md5: 6798f235a96aecf2fd510a5eafcb34ad
# == tier_cli summary: 23 passed, 0 failed ==
# TIER_CLI PASS

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t3_tier_console \
    sh examples/z98/z9play/tests/tier_console.sh
# == tier_console summary: 11 passed, 0 failed ==
# TIER_CONSOLE PASS
```

## Concerns

1. **State-declaration shape deviation (documented above).** Function-scope
   typed `cwin.ConsoleWinState` makes the Win9x module reachable on Linux and
   breaks the required `-osl` build; arm-local states + `entered_ptr` are the
   minimal example-only adjustment. There is no plan/contract change.
2. `interactive` is sampled after `enterRaw`, exactly as M5 did; a non-console
   stdin leaves `entered == false` on both backends, so redirected runs still
   complete without polling keys.
3. Wine smoke used the WAV override (hermetic path). The non-WAV `waveOut` path
   and raw-mode restore on real hardware remain Task 4/5 coverage.
