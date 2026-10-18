# M6 Task T5.4 report — z9torr Win9x default profile build + docs

**Status:** DONE_WITH_CONCERNS (all import/build/functional smoke gates green;
the committed `tier4_wine.sh` progress assertion is timing-sensitive and its
one-shot mock-peer harness is flaky on this Wine host; real-hardware
verification remains operator-pending per Amendment 5).

**Base:** `ea9c361d` (`docs(sdd): T5.3 complete — ledger`).

**Scope:** `examples/z98/z9torr/**` documentation + this report only. No
compiler changes, no seed rotation, no test source changes. `run.err`,
`run.out`, and `progress.md` were left untouched. No push.

---

## 1. Investigate — existing z9torr Win9x assets

- `examples/z98/z9torr/demo/win9x_README.txt` was still the M5 (seed v96)
  manual Win98 procedure: old seed path, old `-osw` dump md5
  `4a330207a420462a9ad4376ace7d0a63`, and a `SetFilePointerEx` claim that is
  no longer the default 9x path.
- `examples/z98/z9torr/README.md` still presented M5 as current, quoted the
  M5 emit md5 and `tier4_wine.sh` `19/0`, and described Windows 64-bit seeks
  as `SetFilePointerEx`.
- The emitted tree already carries the T5.3 no-CRT default: `build_target.sh`
  mingw uses `-DZIG_NO_CRT -nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32
  -lwinmm -lwsock32`; `build_target_nocrt.bat` / `build_owc_nocrt.bat` are the
  native 9x defaults; `*_crt.bat` are the static-CRT alternates;
  `build_target.bat` / `build_owc.bat` are aliases; `net_prelude.h` is emitted.
- `scripts/win32_cross/check_win9x_imports.sh <exe> 9x` is the closed-world
  PE32 import gate (KERNEL32/WINMM/WSOCK32 allowed; msvcrt is a policy failure
  on the 9x profile).
- `tests/tier_win9x_io.sh` is a POSIX-host gate (it builds Linux binaries via
  `build_target.sh linux`); `tests/tier4_wine.sh` is the Windows `-osw` +
  mingw + 32-bit Wine loopback smoke.

No plan step was impossible; no STOP-present.

---

## 2. Implement — docs touched

- `examples/z98/z9torr/demo/win9x_README.txt`
  - default `-osw` = 9x no-CRT, single drag-and-drop EXE, no msvcrt.dll
    redistributable; OS DLLs KERNEL32 + WSOCK32 allowed;
  - `build_target_nocrt.bat` / `build_owc_nocrt.bat` default,
    `*_crt.bat` alternates, aliases kept;
  - seed v101 / fixed point and `-osw --dump-c89` md5
    `54146cf3afc4c25cb5d98efccc68a2f1`;
  - “design-verified; hardware verification pending (operator, after the
    z9play milestone)”;
  - corrected the 64-bit-seek wording to the Win95 `pal_file_seek64`
    `SetFilePointer` path (the `*Ex` calls are `-osw nt`).
- `examples/z98/z9torr/README.md`
  - current milestone/status is M6 Win9x default profile;
  - new M6 section (profile, emitted scripts, seed/md5, imports, Wine smoke);
  - M5 history keeps the old md5 explicitly as “M5-era”, updates build paths to
    seed v101, and points to the M6 results;
  - final status no longer claims z9torr is the last milestone; hardware
    verification is operator-pending.

No source, emitter, test, or seed files were changed.

---

## 3. Runtime smoke — commands + observed output

### 3.1 Seed v101 rebuild

```text
$ bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/t54
[seed] hop2 binary md5: b299b4b435e624d0ddbd2edde681cbc3
[seed] two-hop closure OK: hop1 == hop2 == b299b4b435e624d0ddbd2edde681cbc3
=== [seed] Done: /tmp/t54 ===
$ md5sum /tmp/t54/zig1_5_clean
b299b4b435e624d0ddbd2edde681cbc3  /tmp/t54/zig1_5_clean
```

### 3.2 Builds (default 9x profile; both modes)

```text
$ /tmp/t54/zig1_5_clean -fsafe -osw -o /tmp/t54_z9torr \
    examples/z98/z9torr/main.zig            # rc=0
$ sh /tmp/t54_z9torr/build_target.sh mingw /tmp/t54_z9torr/z9torr.exe
                                            # rc=0
$ /tmp/t54/zig1_5_clean -ffast -osw -o /tmp/t54_z9torr_fast \
    examples/z98/z9torr/main.zig            # rc=0
$ sh /tmp/t54_z9torr_fast/build_target.sh mingw \
    /tmp/t54_z9torr_fast/z9torr.exe         # rc=0
$ file /tmp/t54_z9torr/z9torr.exe /tmp/t54_z9torr_fast/z9torr.exe
... PE32 executable (console) Intel 80386 ... for MS Windows
```

Both images pass the import gate:

```text
$ bash scripts/win32_cross/check_win9x_imports.sh /tmp/t54_z9torr/z9torr.exe 9x
DLL KERNEL32.DLL
DLL WSOCK32.DLL
IMPORT GATE PASS (9x)
$ bash scripts/win32_cross/check_win9x_imports.sh /tmp/t54_z9torr_fast/z9torr.exe 9x
IMPORT GATE PASS (9x)
```

Exact import list (identical `-fsafe` and `-ffast`; 29 KERNEL32 + 20 WSOCK32,
no msvcrt):

```text
KERNEL32.DLL: CloseHandle CreateFileA DeleteFileA ExitProcess FindClose
  FindFirstFileA FlushFileBuffers GetCommandLineA GetCurrentDirectoryA
  GetCurrentProcess GetEnvironmentVariableA GetFileAttributesA GetFileSize
  GetFileType GetLastError GetModuleFileNameA GetStdHandle
  GetSystemTimeAsFileTime GetTickCount MoveFileA QueryPerformanceCounter
  QueryPerformanceFrequency ReadFile SetFilePointer SetLastError Sleep
  TerminateProcess WriteConsoleA WriteFile
WSOCK32.DLL: WSACleanup WSAGetLastError WSAStartup accept bind closesocket
  connect gethostbyname getsockopt htonl htons ioctlsocket listen recv
  recvfrom select send sendto setsockopt socket
```

`-osw --dump-c89` (repo root, seed v101) is stable 3/3:

```text
54146cf3afc4c25cb5d98efccc68a2f1  -
54146cf3afc4c25cb5d98efccc68a2f1  -
54146cf3afc4c25cb5d98efccc68a2f1  -
```

(`-osw` and `-osw nt` emit the same C; the profile is a build define.)

### 3.3 File/disk CLI under Wine

```text
$ WINEPREFIX=/home/node/.wine-t54 WINEARCH=win32 \
    wine /tmp/t54_z9torr/z9torr.exe --help
usage: z9torr [--help] [--max-peers N] [--max-up N] [--max-down N] <file.torrent>
...
HELP_RC=0

$ wine /tmp/t54_z9torr/z9torr.exe <win path>/t1_single_1m.torrent
name: t1.bin
length: 1048576
piece length: 262144
pieces: 4
info_hash: 5bb27f309ea4f5a0a1bf338c0cf2462295d694b5
z9torr: tracker error
INFO_RC=3        # expected: local torrent parsed; no tracker at 127.0.0.1:6969
```

### 3.4 POSIX console/redirect gate

```text
$ ZIG=/tmp/t54/zig1_5_clean OUT=/tmp/t54_win9x_io \
    sh examples/z98/z9torr/tests/tier_win9x_io.sh
ok   - redirected run emitted a progress line
ok   - redirected progress has no bare CR (line-per-refresh)
ok   - console run uses in-place CR (CR bytes=12)
== tier_win9x_io summary: 3 passed, 0 failed ==
TIER_WIN9X_IO PASS
```

### 3.5 `tier4_wine.sh` (Windows `-osw` + mingw + 32-bit Wine loopback)

Representative functional-pass runs (all checks except the progress sample):

```text
$ ZIG=/tmp/t54/zig1_5_clean OUT=/tmp/t54_tier4_e \
    WINEPREFIX=/home/node/.wine-t54b WINEARCH=win32 \
    sh examples/z98/z9torr/tests/tier4_wine.sh
ok   - windows emit rc=0
ok   - emit tree carries module .c/.h (39 .c, 41 .h)
ok   - emit tree carries build_target*.bat / build_owc*.bat / net_prelude.h
ok   - mingw cross-build produced z9torr.exe (XRUNRC=0)
ok   - file reports PE32 (... 17 sections)
ok   - objdump -p shows a wsock32 import
ok   - -fsafe run exe produced (z9torr_run.exe)
ok   - 32-bit wine runs the artifact (--help rc=0)
FAIL - win32 redirected progress is line-per-refresh (progress=0 bare_cr=yes)
  WINE_RC=0
ok   - wine client exit 0
ok   - wine output sha1 == expected (7a985d40cf76ef129b2889fa5bfce75304067dc9)
ok   - client reported download complete
ok   - non-blocking connect: mock peer served fetched=1048576 requests=64
PARITY=OK wine_rc=0 output_sha1=7a985d40... fetched=1048576
== tier4 summary: 22 passed, 1 failed ==
TIER4 FAIL
```

The single failure is the 1 Hz progress sample: the 1 MiB loopback transfer
completes before the first 1000 ms sample (`progress=0`, but `bare_cr=yes` is
the script's wording; the raw log contained **zero** CR bytes). On this host
the same test is also flaky: several runs (`/tmp/t54_tier4x`, `_c`, `_d`, `_f`,
`_g`) hit the committed one-shot mock-peer/MSE-probe restart race and ended
`WINE_RC=4` with `PEER error` before fetching (`PARITY=DIFF`). The successful
runs above are the functional evidence (rc 0, `PARITY=OK`, fetched 1048576,
golden SHA-1). This race is in the M5 mock harness, not the no-CRT import/link
path; the failed runs still emitted progress lines and the `--help`/PE32/import
gates pass.

### 3.6 Throttled Wine loopback (forces the 1 Hz progress path)

```text
$ wine /tmp/t54_z9torr/z9torr.exe --max-down 32768 <t1 torrent>
WINE_RC=0
ELAPSED=34.71
progress lines: 34
bare CR bytes: 0
sha1: 7a985d40cf76ef129b2889fa5bfce75304067dc9  t1.bin
tail:
75.0% [##############################----------] 0.75MB/1.00MB 32KB/s peers=1 eta=8s
75.0% [##############################----------] 0.75MB/1.00MB 32KB/s peers=1 eta=8s
z9torr: download complete
summary: fetched=1048576 requests=64
```

This exercises tracker announce, peer handshake/fallback, piece download,
file write/pre-extend, progress rendering, and clean exit entirely on the
loopback interface. No real peers were contacted.

---

## 4. Gates

- z9torr 9x: PE32, import whitelist green (KERNEL32 + WSOCK32 only, no
  msvcrt), both `-fsafe` and `-ffast`, Wine smoke recorded above.
- No compiler changes / no compiler hops; seed v101 fixed point
  `b299b4b435e624d0ddbd2edde681cbc3` (md5 of `/tmp/t54/zig1_5_clean`).
- `-osw --dump-c89` md5 `54146cf3afc4c25cb5d98efccc68a2f1`, stable 3×.
- `tier_win9x_io.sh` 3/0; `tier4_wine.sh` functional loopback PASS in
  representative runs (22/1; the one failure is the sub-second progress
  sample), with the documented mock-restart flakiness.

---

## 5. Concerns

1. **Hardware verification is operator-pending.** Win98/Me load/run, console,
   FAT pre-extend, and real network behavior remain unverified locally
   (Amendment 5). The docs state “design-verified; hardware verification
   pending”.
2. **`tier4_wine.sh` timing/race flakiness.** The 1 MiB loopback transfer can
   finish in <1 s, so the script's “at least one progress line” assertion is
   not valid on this host; the independent throttled loopback run proves the
   progress/redirect path (34 lines, 0 bare CR). The one-shot mock-peer restart
   occasionally loses the MSE-probe race and exits 4 before fetching. Both are
   harness timing issues, not import/link failures; no test source was changed
   in this task.
3. **Native MSVC/OpenWatcom no-CRT scripts remain design-verified only** (no
   `cl`/`wcc386` was run; Amendment 5). Their emitted headers say so.
4. **No compiler/std gates were re-run** because `sf/src` was untouched; the
   seed fixed point and dump md5 above are the recorded anchors.
