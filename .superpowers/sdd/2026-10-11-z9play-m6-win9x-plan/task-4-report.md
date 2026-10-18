# M6 Task 4 report — `tier_win9x.sh` (mingw build + Wine smoke)

Status: **PASS** (`14 passed, 0 failed, 0 skipped`).
Commit: `f91eb8b2439501b2cd2354b8a8968e4066d77436` — `example(z9play): M6 Win9x tier`.
Branch: `zig1_improvements`.
Compiler: `/tmp/z9play_m6/zig1_5_clean`, md5 `2c48fa702393032c2b711a8d982bd388`.
Host tools observed: `wine-8.0 (Debian 8.0~repack-4)`,
`i686-w64-mingw32-gcc (GCC) 12-win32`.

## Tier anatomy

`examples/z98/z9play/tests/tier_win9x.sh` follows the sibling-tier shape
(`SCRIPT_DIR`/`Z9DIR`/`ROOT`, `ZIG`/`OUT` overrides, `pass_case`/`fail_case`,
exit nonzero on FAIL), plus a skip counter used only when Wine/mingw is absent.

- **(a)** `cross_build_run.sh` (`-osw`, `-lwinmm`) → `XRUNRC=0`; `file` → PE32
  i386; `nm -u` has no `zF_`/`zT_` program symbols; `objdump -p` imports are
  only `KERNEL32.dll`, `msvcrt.dll`, `WINMM.DLL`. Also records the
  `-osw --dump-c89` md5, stable over two dumps.
- **(b)** Runs the real `.exe` under Wine inside a pty (`script`) with
  `Z9PLAY_WAV_OUT` set (hermetic WAV sink, so the device-less `waveOut` path is
  never touched) on `sine_stereo_44100` at `--volume 100` (the volume mixer is
  the identity at 100/100). Asserts exit 0, end-of-playback, canonical 44-byte
  WAV, payload size == Linux golden, M3 tolerance, and 2x determinism.
- **(c)** Builds `tests/win9x_console_probe.zig` for `-osw` through the same
  harness and runs it under Wine in a pty. The probe calls the real
  `console_win9x.enterRaw` → `leaveRaw` and reads `GetConsoleMode` before/raw/
  after. It reports `entered=1,raw_changed=1,restored=1` (and the DWORDs).
- Skip only if `i686-w64-mingw32-{gcc,nm,objdump}` or `wine` is absent. If Wine
  is present but gives no console, the tier FAILS (`nocons=1`) rather than
  faking a pass.

## (a) Cross build / PE32 / undefined symbols

Command (tier and manual):

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/main.zig /tmp/z9play_tier_win9x_final2/build \
    /tmp/z9play_tier_win9x_final2/z9play.exe -lwinmm
# dump: rc=0 error_brk=0 panic=0 c=32 link ok
# XRUNRC=0

file /tmp/z9play_tier_win9x_final2/z9play.exe
# PE32 executable (console) Intel 80386, for MS Windows, 17 sections
```

Tier output:

```
ok   - cross harness XRUNRC=0
ok   - exe produced (680724 bytes)
ok   - file: .../z9play.exe: PE32 executable (console) Intel 80386, for MS Windows, 17 sections
ok   - no unresolved zF_/zT_ program symbols
ok   - imports include WINMM.dll
ok   - only expected DLL imports (KERNEL32.dll msvcrt.dll WINMM.DLL )
```

Undefined-symbol check:

```sh
i686-w64-mingw32-nm -u /tmp/z9play_tier_win9x_final2/z9play.exe \
    | awk '{print $NF}' | sort | uniq -c
#      51 .text
#       1 ___deregister_frame_info
#       1 ___register_frame_info
#       1 __end__
i686-w64-mingw32-nm -u .../z9play.exe | awk '{print $NF}' | grep -E '^z[FT]_'
# (no output)
```

Honest interpretation: the PE has no unresolved **program** (`zF_`/`zT_`)
symbols. The three `nm -u` non-section entries are mingw CRT weak/reserved
symbols (`___register_frame_info` / `___deregister_frame_info` are `A` weak
symbols at address 0; `__end__` is the linker end marker); the PE import table
contains only the three expected DLLs above.

Imports:

```sh
i686-w64-mingw32-objdump -p /tmp/z9play_tier_win9x_final2/z9play.exe \
    | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p'
# KERNEL32.dll
# msvcrt.dll
# WINMM.DLL
```

## (b) Wine WAV-sink parity vs Linux golden

Tier run output:

```
ok   - Wine full playback exit 0
ok   - Wine playback reached the end (Stopped at 00:02.)
ok   - canonical WAV header + payload size (352844 bytes = 44 + 352800)
ok   - Wine WAV parity max_delta=1 rms_milli=36 (<= 2 / 100)
ok   - Wine output deterministic 2x (sha1=f891394376e3012753ddcb6e4a18cf1cfe321b14)
```

Artifacts:

```sh
ls -l /tmp/z9play_tier_win9x_final2/*.wav
# .../sine_stereo_44100.1.wav  352844
# .../sine_stereo_44100.2.wav  352844
sha1sum /tmp/z9play_tier_win9x_final2/*.pcm
# f891394376e3012753ddcb6e4a18cf1cfe321b14  .../sine_stereo_44100.1.pcm
# f891394376e3012753ddcb6e4a18cf1cfe321b14  .../sine_stereo_44100.2.pcm
```

The comparison uses the exact `tier_audio.sh` tolerance method (per-sample
`max |delta|` and RMS LSB) against
`testdata/expected/sine_stereo_44100.pcm` (352800 bytes). `--volume 100` is
required so the mixer's default 80% scaling does not alter the payload; the
sink/decode path itself is backend-independent.

Wine path handling note: the `script -c` command is re-parsed by a shell, which
eats `Z:\...` backslashes, so the tier converts `winepath -w` output to
`Z:/...` (valid to Wine) before putting it in the command string.

## (c) Raw-mode restore under Wine (honest assertion)

Probe build (tier):

```
ok   - console probe cross build XRUNRC=0
       dump: rc=0 error_brk=0 panic=0 c=11 link ok
       XRUNRC=0
ok   - raw-mode restore asserted under Wine (win9x_console_probe:entered=1,raw_changed=1,restored=1)
```

Probe output after stripping Wine's ANSI cursor noise
(`/tmp/z9play_tier_win9x_final2/probe.norm`):

```
win9x_console_probe:entered=1,raw_changed=1,restored=1
win9x_console_probe:modesbefore=503raw=496after=503
```

Interpretation: Wine under `script` supplied a console handle
(`GetConsoleMode` mode `503`); `enterRaw` cleared line/echo/processed-input
(`raw=496`); `leaveRaw` restored the exact original DWORD (`after=503`). This is
a live read-back from Win32, not a claim derived from the backend's own state.
The probe also exercises the real backend functions (not a reimplementation).

## `-osw --dump-c89` md5

```sh
md5sum /tmp/z9play_tier_win9x_final2/dump1.c89 /tmp/z9play_tier_win9x_final2/dump2.c89
# 87856b43091e2bf5d992fc795d9764f2  dump1.c89
# 87856b43091e2bf5d992fc795d9764f2  dump2.c89
```

Tier line: `--dump-c89 (-osw) md5: 87856b43091e2bf5d992fc795d9764f2`
(stable 2x; matches the T3 recorded md5).

## Skip reasons

None: Wine 8.0 and the i686 mingw toolchain were present, and Wine provided a
console under the pty, so (c) was asserted rather than skipped. The skip branch
(`TIER_WIN9X SKIP (wine/mingw absent)`) was not exercised on this host.

## Concerns

1. **(c) covers explicit `leaveRaw`, not the atexit backstop.** The probe drives
   `enterRaw` → `leaveRaw` (the path `main.zig` uses on both the normal and
   `playFail` exits). The atexit crash backstop is not independently observable
   after process exit with this probe shape; it remains covered by code review,
   not by this tier.
2. **`nm -u` on PE is noisy.** The assertion is deliberately scoped to
   `zF_`/`zT_` program symbols plus the import table; the three CRT weak/section
   entries above are not runtime imports (Wine executed the image successfully).
3. **`--volume 100` is load-bearing for parity.** At the default 80% the mixer
   scales the payload and the golden comparison would fail by design, not by a
   decode defect.
4. **Wine prefix location.** The tier defaults `WINEPREFIX=$OUT/wineprefix`.
   Wine refuses a prefix whose parent it cannot own; a normal per-user `$OUT`
   under `/tmp` works (observed). A pre-existing non-writable/foreign `$OUT`
   would fail early.
5. **No real Win9x hardware run.** This is the Wine smoke only; the manual
   Win98 procedure remains Task 5 scope.

## Reproduce

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/z9play_tier_win9x_final2 \
    sh examples/z98/z9play/tests/tier_win9x.sh
# == tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
# TIER_WIN9X PASS
```

## Fix round 1

Review finding: the (a) undefined-symbol filter was vacuous. `i686-w64-mingw32-nm
-u` reports i386 PE names underscore-prefixed (an unresolved program symbol is
`U _zF_...`), so `grep -E '^z[FT]_'` could never match. Fix commit:
`a0a7616f514faa5078724426408c55ea6482df96` —
`example(z9play): M6 T4 fix — real undefined-symbol check`.

The filter now allows the optional leading underscore (symbol-name column):

```sh
grep -n 'UNDEF=' examples/z98/z9play/tests/tier_win9x.sh
# 155:UNDEF="$(i686-w64-mingw32-nm -u "$EXE" 2>/dev/null | awk '{print $NF}' | grep -E '^_?z[FT]_' || true)"
```

Non-vacuity demonstration against synthetic `nm -u` lines:

```sh
printf '         U _zF_MISSING_weak\n         U _zT_ALSO_MISSING\n         U ___register_frame_info\n' \
    | awk '{print $NF}' | grep -E '^_?z[FT]_'
# _zF_MISSING_weak
# _zT_ALSO_MISSING
printf '         U _zF_MISSING_weak\n' | awk '{print $NF}' | grep -E '^z[FT]_'
# (no output; the old filter misses it)
```

So a `weak_z.exe`-style unresolved `_zF_`/`_zT_` symbol now produces `UNDEF`
non-empty and the tier takes the FAIL branch.

Real exe's complete undefined set (only the benign CRT/section entries):

```sh
i686-w64-mingw32-nm -u /tmp/z9play_tier_win9x_fix1/z9play.exe \
    | awk '{print $NF}' | sort -u
# .text
# ___deregister_frame_info
# ___register_frame_info
# __end__
i686-w64-mingw32-nm -u /tmp/z9play_tier_win9x_fix1/z9play.exe \
    | awk '{print $NF}' | grep -E '^_?z[FT]_'
# (no output -> PASS)
```

Tier re-run after the fix:

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/z9play_tier_win9x_fix1 \
    sh examples/z98/z9play/tests/tier_win9x.sh
# ok   - no unresolved zF_/zT_ program symbols
# == tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
# TIER_WIN9X PASS
```

PE32/link/import checks are unchanged and still pass
(`XRUNRC=0`, PE32 i386, `KERNEL32.dll`/`msvcrt.dll`/`WINMM.DLL` only). The
`-osw --dump-c89` md5 remains
`87856b43091e2bf5d992fc795d9764f2`; Wine parity remains
`max_delta=1 rms_milli=36`; probe restore remains
`entered=1,raw_changed=1,restored=1` (`before=503 raw=496 after=503`).
