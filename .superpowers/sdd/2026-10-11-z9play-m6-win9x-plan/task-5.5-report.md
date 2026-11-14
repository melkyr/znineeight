# M6 Task T5.5 report — z9play Win9x default profile tier + docs

**Status:** DONE_WITH_CONCERNS (all automated gates green; native scripts and
real Win98/Me hardware remain design-verified / operator-pending per
Amendment 5).

**Base:** `b3101d51` (`docs(sdd): T5.4 complete — ledger`).

**Commits:**
- `eda98754` `example(z9play): Win9x default profile tier`
- `5a905212` `docs(z9play): Win9x default profile`
- `docs(sdd): T5.5 report` (this report)

**Scope:** `examples/z98/z9play/**` + this report only. No compiler changes, no
native MSVC/OpenWatcom probes, no seed rotation, no push. `run.err`,
`run.out`, and `progress.md` were left untouched.

---

## 1. Investigate — existing tier/docs

- `tests/tier_win9x.sh` built through `scripts/win32_cross/cross_build_run.sh`
  (the legacy CRT harness) and accepted `KERNEL32/msvcrt/WINMM` imports. That
  no longer represented the default `-osw` path after T5.3, whose emitted
  `build_target.sh` mingw branch is `-DZIG_NO_CRT -nostdlib
  -Wl,-e,_mainCRTStartup ... -lkernel32 -lwinmm`.
- The emitted tree for z9play already carries:
  `-DZIG_NO_CRT`; `-nostdlib`; `-lkernel32 -lwinmm` (no wsock32 — z9play does
  not import it); `build_target_nocrt.bat` / `build_target_crt.bat` (MSVC 6)
  and `build_owc_nocrt.bat` / `build_owc_crt.bat` (OpenWatcom), with
  `build_target.bat` / `build_owc.bat` as aliases.
- `scripts/win32_cross/check_win9x_imports.sh <exe> 9x` is the closed-world
  PE32 per-DLL/per-import whitelist gate; on 9x it rejects msvcrt and the
  XP+/NT4 APIs.
- Docs were still M6-era: they told users to build through the CRT harness,
  claimed KERNEL32/msvcrt/WINMM imports, quoted seed v98 / old dump md5
  `87856b43091e2bf5d992fc795d9764f2`, and did not state the no-CRT single-EXE
  redistribution guarantee.
- The default `-osw` build is implementable and the plan/brief did not conflict;
  no STOP-present.

## 2. Implement

### 2.1 `examples/z98/z9play/tests/tier_win9x.sh`

Gates the **emitted default no-CRT path**, still **14 assertions**:

1. emit default `-osw`; assert the emitted `build_target.sh` has
   `-DZIG_NO_CRT`, `-nostdlib`, `-lkernel32`, `-lwinmm`;
2. build through `sh <emit>/build_target.sh mingw` and assert the EXE exists;
3. `file` → PE32 i386;
4. real unresolved-symbol check (`nm -u`, `zF_`/`zT_` with optional `_`);
5. imports exactly `KERNEL32.DLL + WINMM.DLL` (no msvcrt);
6. `check_win9x_imports.sh <exe> 9x` PASS;
7. `-osw --dump-c89` md5 stable 2×;
8. Wine full playback exit 0;
9. Wine playback reaches `Stopped at 00:02.`;
10. canonical 44-byte WAV header + golden payload size;
11. WAV parity within `max_delta <= 2`, `rms_milli <= 100`;
12. 2× deterministic payload;
13. console probe emitted/built through its own `build_target.sh`;
14. pty probe asserts `entered=1,raw_changed=1,restored=1`.

PASS/FAIL/SKIP semantics are unchanged. The default `ZIG` path now points at
the seed-v101 build (`/tmp/z9play_seed/zig1_5_clean`) and the obsolete harness
variable/check was removed. The `cross_build_run.sh` harness is not referenced.

### 2.2 Docs truth-up

- `demo/win9x_README.txt`
  - seed v101 rebuild (`b299b4b435e624d0ddbd2edde681cbc3`, `hop1 == hop2`);
  - default `-osw` = 9x no-CRT, emitted mingw recipe, single drag-and-drop
    PE32 EXE importing **KERNEL32 + WINMM only**; **no msvcrt.dll and no CRT
    redistributable**; no DLL bundling;
  - `build_target_nocrt.bat` / `build_owc_nocrt.bat` are the 9x no-CRT
    defaults; `*_crt.bat` are static-CRT alternates; `build_target.bat` /
    `build_owc.bat` are aliases; `-osw nt` is explicit opt-in (`ZIG_WIN_NT`,
    XP+ APIs);
  - dump md5 `ad9ccfd34aa2ba26c38abbcf48eedeb0`; tier `14/14`;
  - “design-verified; hardware verification operator-pending after the z9play
    milestone”.
- `NOTES.md`
  - current seed v101; default `-osw` = 9x no-CRT; seed v101 dump md5;
  - M6 section now records the emitted-path tier, exact import policy,
    no-CRT/no-msvcrt redistribution, native-script defaults/alternates, and
    operator-pending hardware verification;
  - old `87856b43…` and seed-v98 values are retained only as explicit
    pre-rotation history.
- `README.md`
  - Win9x default profile + `-osw nt` opt-in; no-DLL-bundling; single EXE;
  - current tier result (14/14), seed v101, imports, md5;
  - manual procedure points at the truth-up'd `demo/win9x_README.txt`.

## 3. Runtime — commands + output

### 3.1 Seed v101 rebuild

```text
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t55
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/t55 ===
$ md5sum /tmp/t55/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/t55/zig1_5_clean
```

### 3.2 Default `-osw` emit + emitted build

```text
$ /tmp/t55/zig1_5_clean -osw -o /tmp/t55_z9play examples/z98/z9play/main.zig
# rc=0
$ sh /tmp/t55_z9play/build_target.sh mingw /tmp/t55_z9play/z9play.exe
# rc=0; Built: /tmp/t55_z9play/z9play.exe
$ file /tmp/t55_z9play/z9play.exe
... PE32 executable (console) Intel 80386 ..., for MS Windows, 7 sections
$ bash scripts/win32_cross/check_win9x_imports.sh /tmp/t55_z9play/z9play.exe 9x
DLL KERNEL32.DLL
DLL WINMM.DLL
IMPORT GATE PASS (9x): /tmp/t55_z9play/z9play.exe
```

Exact DLL set: **KERNEL32.DLL + WINMM.DLL only; no msvcrt.dll**.

- KERNEL32 (37): CloseHandle CreateFileA DeleteFileA ExitProcess
  FillConsoleOutputCharacterA FindClose FindFirstFileA FlushFileBuffers
  GetCommandLineA GetConsoleCursorInfo GetConsoleMode
  GetConsoleScreenBufferInfo GetCurrentDirectoryA GetCurrentProcess
  GetEnvironmentVariableA GetFileAttributesA GetFileSize GetLastError
  GetModuleFileNameA GetNumberOfConsoleInputEvents GetStdHandle
  GetSystemTimeAsFileTime GetTickCount MoveFileA QueryPerformanceCounter
  QueryPerformanceFrequency ReadConsoleInputA ReadFile SetConsoleCursorInfo
  SetConsoleCursorPosition SetConsoleMode SetFilePointer SetLastError Sleep
  TerminateProcess WriteConsoleA WriteFile
- WINMM (6): waveOutClose waveOutOpen waveOutPrepareHeader waveOutReset
  waveOutUnprepareHeader waveOutWrite

### 3.3 C89 dump

```text
$ /tmp/t55/zig1_5_clean -osw --dump-c89 examples/z98/z9play/main.zig | md5sum
ad9ccfd34aa2ba26c38abbcf48eedeb0  -
ad9ccfd34aa2ba26c38abbcf48eedeb0  -
```

### 3.4 Tier

Wine requires a WINEPREFIX owned by the invoking user; a prefix under `/tmp`
is refused by this host’s Wine. The gate was therefore run with the prefix in
the user home (same tool, not a test change):

```text
$ ZIG=/tmp/t55/zig1_5_clean OUT=/tmp/t55_tier \
    WINEPREFIX=/home/node/.wine-t55 WINEARCH=win32 \
    bash examples/z98/z9play/tests/tier_win9x.sh
== (a) emit + build z9play (default -osw = 9x no-CRT) ==
ok   - emitted mingw recipe is 9x no-CRT (DZIG_NO_CRT, nostdlib, kernel32+winmm)
ok   - emitted build_target.sh mingw produced exe (591573 bytes)
ok   - file: ... PE32 executable (console) Intel 80386 ...
ok   - no unresolved zF_/zT_ program symbols
ok   - imports are exactly KERNEL32 + WINMM (no msvcrt)
ok   - check_win9x_imports.sh 9x whitelist PASS
ok   - -osw --dump-c89 md5 recorded stable 2x: ad9ccfd34aa2ba26c38abbcf48eedeb0
== (b) Wine: WAV sink vs Linux golden (tolerance + determinism) ==
ok   - Wine full playback exit 0
ok   - Wine playback reached the end (Stopped at 00:02.)
ok   - canonical WAV header + payload size (352844 bytes = 44 + 352800)
ok   - Wine WAV parity max_delta=1 rms_milli=36 (<= 2 / 100)
ok   - Wine output deterministic 2x (sha1=f891394376e3012753ddcb6e4a18cf1cfe321b14)
== (c) Win9x console raw-mode restore under Wine (probe, pty) ==
ok   - console probe emitted no-CRT build produced exe
ok   - raw-mode restore asserted under Wine (win9x_console_probe:entered=1,raw_changed=1,restored=1)

== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
TIER_WIN9X PASS
```

## 4. Concerns

- **Amendment 5:** native MSVC 6 / OpenWatcom no-CRT scripts and real
  Win98/Me hardware remain **design-verified / operator-pending**. No native
  toolchain probes were run, by instruction.
- The tier is Wine-based: it proves the PE32 import table, no-CRT link, WAV
  parity, determinism, and console raw-mode restore. It cannot prove a real
  Win98 loader/audio device. The docs state this explicitly.
- Wine on this host requires a user-owned `WINEPREFIX`; using one under `/tmp`
  fails with “refusing to create a configuration directory there”. This is a
  host/prefix constraint, not a tier or product failure.
