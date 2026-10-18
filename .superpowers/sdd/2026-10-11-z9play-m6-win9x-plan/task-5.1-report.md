# M6 Task T5.1 report — Win9x inventory + capability table (REPORT ONLY)

**Status:** DONE_WITH_CONCERNS (report complete; concerns are recorded in §10).

**Scope:** report-only. No `sf/src`, `examples`, plan, spec, script, or doc edits.
The only file created by this task is this report. `run.err`/`run.out` and
`progress.md` were left untouched.

**Authority:** `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`
`### Amendment 2` → `#### Task T5.1` (operator-locked 2026-10-18).

**Base:** `git rev-parse HEAD` → `8dd4fa8ed693a4e34d09d0c7f21d13da87de2af7`
(`docs(sdd): M6 Amendment 2 ledger`). `git status --short` before this report:
only untracked `run.err`.

**Toolchain (observed):**

```sh
$ md5sum /tmp/z9play_m6/zig1_5_clean
2c48fa702393032c2b711a8d982bd388  /tmp/z9play_m6/zig1_5_clean
$ i686-w64-mingw32-gcc --version | head -1
i686-w64-mingw32-gcc (GCC) 12-win32
$ i686-w64-mingw32-objdump --version | head -1
GNU objdump (GNU Binutils) 2.40
$ wine --version
wine-8.0 (Debian 8.0~repack-4)
```

The compiler md5 matches the brief, so no seed rebuild was needed.

---

## 1. Per-DLL import inventory for z9play and z9torr

### 1.1 Builds (current compiler, PE32)

```sh
$ ROOT=/workspace/znineeight bash scripts/win32_cross/cross_build_run.sh \
    /tmp/z9play_m6/zig1_5_clean examples/z98/z9play/main.zig \
    /tmp/t51_z9play/work /tmp/t51_z9play/z9play.exe -lwinmm
dump: rc=0 error_brk=0 panic=0 c=32 link ok
XRUNRC=0

$ ROOT=/workspace/znineeight bash scripts/win32_cross/cross_build_run.sh \
    /tmp/z9play_m6/zig1_5_clean examples/z98/z9torr/main.zig \
    /tmp/t51_z9torr/work /tmp/t51_z9torr/z9torr.exe
dump: rc=0 error_brk=0 panic=0 c=38 link ok
XRUNRC=0

$ file /tmp/t51_z9play/z9play.exe /tmp/t51_z9torr/z9torr.exe
/tmp/t51_z9play/z9play.exe: PE32 executable (console) Intel 80386, for MS Windows, 17 sections
/tmp/t51_z9torr/z9torr.exe: PE32 executable (console) Intel 80386, for MS Windows, 17 sections

$ md5sum /tmp/t51_z9play/z9play.exe /tmp/t51_z9torr/z9torr.exe
9ca2c391333a22117788bbdcc1ed152c  /tmp/t51_z9play/z9play.exe
c350041bb64d76f198c0beed49defb17  /tmp/t51_z9torr/z9torr.exe
```

`nm -u` on the final images was also used to confirm there are no unresolved
program symbols; `tier_win9x.sh` (re-run, §11) independently asserts
`no unresolved zF_/zT_ program symbols`.

### 1.2 Per-DLL counts

```sh
$ i686-w64-mingw32-objdump -p <exe> | \
    awk '/DLL Name:/{dll=$3} /^\t[0-9a-f]+[[:space:]]+[0-9]+[[:space:]]/{n++}
         END{print dll": "n}'
```

| Binary | DLL | Imports |
|:--|:--|--:|
| z9play | KERNEL32.dll | 44 |
| z9play | msvcrt.dll | 28 |
| z9play | WINMM.DLL | 6 |
| z9torr | KERNEL32.dll | 36 |
| z9torr | msvcrt.dll | 28 |
| z9torr | WSOCK32.DLL | 20 |

### 1.3 z9play import table (`objdump -p`)

```text
KERNEL32.dll (44):
  CloseHandle CreateFileA DeleteCriticalSection DeleteFileA
  EnterCriticalSection FillConsoleOutputCharacterA FlushFileBuffers
  FreeLibrary GetConsoleCursorInfo GetConsoleMode
  GetConsoleScreenBufferInfo GetCurrentDirectoryA GetCurrentProcess
  GetFileAttributesA GetFileAttributesExA GetFileSizeEx GetLastError
  GetModuleFileNameA GetModuleHandleA GetNumberOfConsoleInputEvents
  GetProcAddress GetStartupInfoA GetStdHandle GetTickCount
  InitializeCriticalSection LeaveCriticalSection LoadLibraryA MoveFileA
  QueryPerformanceCounter QueryPerformanceFrequency ReadConsoleInputA
  ReadFile SetConsoleCursorInfo SetConsoleCursorPosition SetConsoleMode
  SetFilePointerEx SetUnhandledExceptionFilter Sleep TerminateProcess
  TlsGetValue VirtualProtect VirtualQuery WriteConsoleA WriteFile
msvcrt.dll (28):
  __getmainargs __initenv __p__acmdln __p__commode __p__fmode
  __set_app_type __setusermatherr _amsg_exit _cexit _initterm _iob
  _onexit abort calloc exit fprintf free fwrite getchar getenv malloc
  memcpy putchar signal strlen strncmp vfprintf time
WINMM.DLL (6):
  waveOutClose waveOutOpen waveOutPrepareHeader waveOutReset
  waveOutUnprepareHeader waveOutWrite
```

### 1.4 z9torr import table (`objdump -p`)

```text
KERNEL32.dll (36):
  CloseHandle CreateFileA DeleteCriticalSection DeleteFileA
  EnterCriticalSection FlushFileBuffers FreeLibrary GetCurrentDirectoryA
  GetCurrentProcess GetFileAttributesA GetFileAttributesExA GetFileSizeEx
  GetFileType GetLastError GetModuleFileNameA GetModuleHandleA
  GetProcAddress GetStartupInfoA GetStdHandle GetTickCount
  InitializeCriticalSection LeaveCriticalSection LoadLibraryA MoveFileA
  QueryPerformanceCounter QueryPerformanceFrequency ReadFile
  SetFilePointerEx SetUnhandledExceptionFilter Sleep TerminateProcess
  TlsGetValue VirtualProtect VirtualQuery WriteConsoleA WriteFile
msvcrt.dll (28):
  __getmainargs __initenv __p__acmdln __p__commode __p__fmode
  __set_app_type __setusermatherr _amsg_exit _cexit _initterm _iob
  _onexit abort calloc exit fprintf free fwrite getchar getenv malloc
  memcpy putchar signal strlen strncmp vfprintf time
WSOCK32.DLL (20):
  WSACleanup WSAGetLastError WSAStartup accept bind closesocket connect
  gethostbyname getsockopt htonl htons ioctlsocket listen recv recvfrom
  select send sendto setsockopt socket
```

The only z9play↔z9torr KERNEL32 differences are the nine console/cursor
imports in z9play and `GetFileType` in z9torr.

### 1.5 `nm -u` object-level attribution

Command (per dump directory):

```sh
$ for f in *.o; do i686-w64-mingw32-nm -u "$f" | awk '{print $NF}'; done
```

Non-program, non-libgcc undefined symbols (program `_zF_*`/`_zG_*` symbols and
`__divdi3`/`__udivdi3`/`__umoddi3`/`__moddi3`/`__chkstk_ms` omitted):

| Object (z9play) | External imports referenced by that object |
|:--|:--|
| `std_file_2048D7A4.o` | `CloseHandle CreateFileA DeleteFileA FlushFileBuffers GetFileAttributesA GetFileAttributesExA GetFileSizeEx MoveFileA ReadFile SetFilePointerEx WriteFile` |
| `std_io_FCB87E0E.o` | `Sleep fwrite getchar putchar __acrt_iob_func pal_file_close/open/read/write` |
| `std_os_47144A3C.o` | `GetCurrentDirectoryA exit getenv` |
| `std_time_6E042473.o` | `GetTickCount QueryPerformanceCounter QueryPerformanceFrequency Sleep __time32` |
| `console_win9x_383D9AF4.o` | `FillConsoleOutputCharacterA GetConsoleCursorInfo GetConsoleMode GetConsoleScreenBufferInfo GetNumberOfConsoleInputEvents GetStdHandle ReadConsoleInputA SetConsoleCursorInfo SetConsoleCursorPosition SetConsoleMode WriteConsoleA atexit` |
| `audio_win9x_0B677AE3.o` | `waveOutClose waveOutOpen waveOutPrepareHeader waveOutReset waveOutUnprepareHeader waveOutWrite` |
| `c_exit.o` | `exit` |
| `zig_pal.o` | `CloseHandle CreateFileA GetCurrentProcess GetFileAttributesA GetModuleFileNameA GetStdHandle ReadFile TerminateProcess WriteConsoleA WriteFile` |
| `zig_runtime.o` | `pal_print_stderr pal_print_stdout pal_trap strlen` |

z9torr adds these emitted-code-only references (beyond the shared std objects):

| Object (z9torr) | External imports referenced by that object |
|:--|:--|
| `main_B8D622A5.o` | `memcpy` (+ `__main`) |
| `scheduler_DC60A925.o` | `__acrt_iob_func fwrite memcpy` |
| `std_async_07971A42.o` | `__acrt_iob_func fwrite` |
| `std_net_599C2381.o` | the 20 WSOCK32 names in §1.4 |
| `peer_E7BBEDD8.o` | `connect htons` |
| `std_stream_14FCB36E.o` | `htonl` |
| `wire_1286B6BD.o` | `htonl` |
| `console_D8597311.o` | `GetFileType GetStdHandle` |

The object-level split is therefore unambiguous: the three XP+ file APIs are
referenced by emitted `std_file_*.o`; the Windows console/audio/socket imports
are referenced by their emitted backend/std modules; the CRT startup names in
§3 are not referenced by any emitted object.

---

## 2. Every `@isWindows()` branch and Win9x safety

Search command:

```sh
$ grep -rn "@isWindows()" sf/src stdlib --include='*.zig'
```

Observations:
- `stdlib/`: 0 matches (no such source tree use).
- `sf/src`: 61 textual matches, of which 21 are pure-comment lines and 1 is
  the diagnostic string `semantic_analyzer.zig:477`; excluding those leaves 39
  actual branch sites: `std_file.zig` 12, `std_net.zig` 20, `std_time.zig` 5,
  `std_os.zig` 1, `std_stdin.zig` 1 = **39 branches**.
- `examples/z98/z9play/main.zig`: 2 branch sites (lines 649, 698; the other 4
  matches are comments). `examples/z98/z9torr/console.zig`: 1 branch site
  (line 34). Other examples (`rogue_mud*`) also use `@isWindows()` but are out
  of scope for this task.

Classification key: **PASS-9x** = the Win32 API named exists on the Win95/98
export/API surface; **FAIL-9x** = missing on 9x; **N/A** = branch contains no
OS call (layout/constant only).

### 2.1 `sf/src/std_file.zig`

| Line | Function | Win32 branch uses | 9x |
|--:|:--|:--|:--|
| 141 | `openHandle` | `CreateFileA` (+ `seekHandle` for Append) | PASS |
| 168 | `closeHandle` | `CloseHandle` | PASS |
| 177 | `readHandle` | `ReadFile` | PASS |
| 190 | `writeHandle` | `WriteFile` | PASS |
| 208 | `llseekHandle` | returns `SeekFailed` (POSIX-only helper; pruned) | N/A |
| 224 | `seekHandle` | `SetFilePointerEx` | **FAIL** |
| 237 | `sizeHandle` | `GetFileSizeEx` | **FAIL** |
| 258 | `flushHandle` | `FlushFileBuffers` | PASS |
| 304 | `exists` | `GetFileAttributesA` | PASS |
| 319 | `mtime` | `GetFileAttributesExA` | **FAIL** |
| 336 | `remove` | `DeleteFileA` | PASS |
| 348 | `rename` | `MoveFileA` | PASS |

`std_file.zig:226` is the `SetFilePointerEx` call, `:239` the `GetFileSizeEx`
call, and `:321` the `GetFileAttributesExA` call recorded by the brief; the
declarations are `std_file_pal.zig:26-28` and `:39`.

### 2.2 `sf/src/std_net.zig`

All Win32 branches are Winsock 1.1 (`WSOCK32.DLL`), which ships with Win95.

| Lines | Function(s) | Win32 APIs | 9x |
|--:|:--|:--|:--|
| 98, 108 | `init`, `cleanup` | `WSAStartup`, `WSACleanup` | PASS |
| 116, 150 | `createTcpServer`, `createTcpClient` | `socket bind connect closesocket htons htonl` | PASS |
| 182, 194 | `bindListen`, `accept` | `listen`, `accept` | PASS |
| 210, 230 | `connect`, `close` | `connect`, `closesocket` | PASS |
| 242, 253 | `lastErr`, `mapErr` | `WSAGetLastError` / error-code mapping | PASS |
| 346, 361 | `udpRecvFrom`, `udpSetTimeout` | `recvfrom` (WSAEMSGSIZE branch), `setsockopt` | PASS |
| 404 | `select` | `select` | PASS |
| 429 | `setNonBlocking` | `ioctlsocket(FIONBIO)` | PASS |
| 458, 471, 491 | `fdZero`, `fdSet`, `fdIsset` | Winsock `fd_set` layout only | N/A |
| 587 | `isInProgress` | error-code mapping only | N/A |
| 608 | `resolve` | `gethostbyname` + `hostent` layout | PASS |
| 632 | `checkSoError` | `getsockopt(SOL_SOCKET, SO_ERROR)` | PASS |

### 2.3 `sf/src/std_time.zig`

| Line | Function | Win32 branch uses | 9x |
|--:|:--|:--|:--|
| 37 | `winQpcPair` | `QueryPerformanceCounter`, `QueryPerformanceFrequency` | PASS |
| 57 | `ticksMs` | `GetTickCount` | PASS |
| 73 | `highRes` | QPC (via `winQpcPair`) | PASS |
| 90 | `clockMonotonicAvailable` | returns `false` (no OS call) | N/A |
| 101 | `highResFreq` | QPF (via `winQpcPair`) | PASS |

Not an `@isWindows()` branch, but required by §4: `wallClockUnix` at
`std_time.zig:116-118` calls the CRT `time()` unconditionally.

### 2.4 `sf/src/std_os.zig` and `sf/src/std_stdin.zig`

| File:line | Function | Win32 branch uses | 9x |
|:--|:--|:--|:--|
| `std_os.zig:85` | `cwd` | `GetCurrentDirectoryA` | PASS |
| `std_stdin.zig:42` | `stdinHandle` | `GetStdHandle(STD_INPUT_HANDLE)` | PASS |

Not a branch: `std_os.zig:74` calls the CRT `getenv()` unconditionally.

### 2.5 Example branches (z9play/z9torr)

| File:line | Branch | Win9x safety |
|:--|:--|:--|
| `examples/z98/z9play/main.zig:649` | WAV-sink override else Win9x `audio_win9x` backend else OSS | PASS for API selection; the backend's `waveOut*` imports are Win95; its `atexit` call is a no-CRT gap (§4.8) |
| `examples/z98/z9play/main.zig:698` | Win9x `console_win9x` backend else Linux console | PASS for API selection; backend imports are Win95 console APIs |
| `examples/z98/z9torr/console.zig:34` | `GetStdHandle` + `GetFileType` | PASS |

### 2.6 Emitted build scripts

`zig1 -osw -o <dir>` emits `build_target.sh`, `build_target.bat`, and
`build_owc.bat` (the latter two only for Windows). Current emitted lines:

```text
# z9play/build_target.sh:19,26
CFLAGS="-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I ."
# z9play/build_target.sh:21,28
LIBS=""
# z9torr/build_target.sh:28
LIBS="-lwsock32"
# build_target.bat:11
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /I .
# build_owc.bat:12 (and every source line)
wcc386 /za /we /dZIG_WIN32 /i=. <module>.c
```

No `ZIG_WIN_NT`, no `ZIG_NO_CRT`, and no `-nostdlib`/`mainCRTStartup` link
form exists in any emitted script yet. `grep -rn "ZIG_WIN_NT\|ZIG_NO_CRT"
sf examples scripts` finds only `ZIG_NO_CRT` in `sf/src/include/zig_pal.c:348`
(the `mainCRTStartup` stub), its emit literal `sf/src/emit_support.zig:1027`,
and `scripts/win32_cross/cross_nocrt.sh`; `ZIG_WIN_NT` is absent everywhere.

---

## 3. CRT-startup vs emitted-code msvcrt import split

### 3.1 Attribution method

Linking with GNU ld tracing shows exactly which object pulled each msvcrt name:

```sh
$ i686-w64-mingw32-gcc -m32 -o /tmp/trace.exe *.o -lwsock32 -lwinmm \
    -Wl,--trace-symbol=_exit -Wl,--trace-symbol=_malloc ... 
```

Observed (z9play; z9torr identical for the shared names plus the z9torr-only
`memcpy`/`fwrite` objects from §1.5):

```text
crt2.o: reference to _exit
crt2.o: reference to _malloc
crt2.o: reference to _memcpy
crt2.o: reference to _strlen
libmingw32.a(crt_handler.o): reference to _signal
libmingw32.a(merr.o): reference to _fprintf
libmingw32.a(pesect.o): reference to _strlen, _strncmp
libmingw32.a(pseudo-reloc.o): reference to _abort, _fwrite, _vfprintf
libmingw32.a(tlsthrd.o): reference to _calloc, _free
c_exit.o: reference to _exit
std_io_FCB87E0E.o: reference to _fwrite, _getchar, _putchar
std_os_47144A3C.o: reference to _exit, _getenv
zig_runtime.o: reference to _strlen
```

`crt2.o` also references the pure startup imports `___getmainargs`,
`___set_app_type`, `___p__acmdln`, `___p__commode`, `___p__fmode`,
`__amsg_exit`, `__cexit`, `__initterm`, `__onexit`, `__imp____initenv`.
`_iob` is pulled by mingw's `__acrt_iob_func` wrapper, which emitted
`std_io`/`scheduler`/`std_async` reference.

### 3.2 The 28 msvcrt names

| msvcrt import | Source category | Referenced by emitted/runtime code? | No-CRT disposition |
|:--|:--|:--|:--|
| `__getmainargs` | CRT startup (`crt2.o`) | no | disappears |
| `__initenv` | CRT startup (`crt2.o`) | no | disappears |
| `__p__acmdln` | CRT startup (`crt2.o`) | no | disappears |
| `__p__commode` | CRT startup (`crt2.o`) | no | disappears |
| `__p__fmode` | CRT startup (`crt2.o`) | no | disappears |
| `__set_app_type` | CRT startup (`crt2.o`) | no | disappears |
| `__setusermatherr` | CRT startup/lib | no | disappears |
| `_amsg_exit` | CRT startup (`crt2.o`) | no | disappears |
| `_cexit` | CRT startup (`crt2.o`) | no | disappears |
| `_initterm` | CRT startup (`crt2.o`) | no | disappears |
| `_onexit` | CRT startup (`crt2.o`) | no | disappears |
| `_iob` | CRT support (`__acrt_iob_func`) | indirectly via `__acrt_iob_func` | disappears; wrapper shimmed |
| `abort` | libmingw32 `pseudo-reloc.o` | no (`pal_abort` uses `TerminateProcess` on `_WIN32`) | disappears |
| `calloc` | libmingw32 `tlsthrd.o` | no | disappears |
| `fprintf` | libmingw32 `merr.o` | no | disappears |
| `free` | libmingw32 `tlsthrd.o` | no | disappears |
| `malloc` | CRT startup (`crt2.o`) | no | disappears |
| `signal` | libmingw32 `crt_handler.o` | no | disappears |
| `strncmp` | libmingw32 `pesect.o` | no in these two programs | disappears; shim still required by T5.3 contract |
| `vfprintf` | libmingw32 `pseudo-reloc.o` | no | disappears |
| `exit` | `crt2.o`, `c_exit.o`, `std_os_*.o` | **yes** (`c_exit`, `std.os.exit`) | replace with `ExitProcess`/`c_exit` |
| `memcpy` | `crt2.o` + emitted `main`/`scheduler` (z9torr) | **yes** | shim required |
| `strlen` | `crt2.o` + libmingw32 + `zig_runtime.o` | **yes** | shim required |
| `fwrite` | libmingw32 + `std_io` + z9torr `scheduler`/`std_async` | **yes** | shim (cross_nocrt already does) |
| `getchar` | emitted `std_io` | **yes** | shim (cross_nocrt already does) |
| `putchar` | emitted `std_io` | **yes** | shim (cross_nocrt already does) |
| `getenv` | emitted `std_os` | **yes** | replace with `GetEnvironmentVariableA` |
| `time` | emitted `std_time` | **yes** | replace with `GetSystemTimeAsFileTime` |

Summary: **20 of 28** msvcrt names are CRT-startup/lib-only and disappear under
`-nostdlib`; **8** are referenced by emitted/runtime code and need a
replacement or shim. In addition, emitted `console_win9x` references `atexit`
(not in the PE msvcrt table because mingw's `libmingw32`/`crtbegin` provide it
on top of `_onexit`); under no-CRT it is also unresolved.

### 3.3 Observed no-CRT evidence

Compiling the emitted trees with `-DZIG_NO_CRT` and listing object undefined
symbols leaves exactly the emitted references above:

```text
z9play no-CRT:
  std_io: __acrt_iob_func fwrite getchar putchar
  std_os: exit getenv
  std_time: __time32
  zig_runtime: strlen
  c_exit: exit
z9torr no-CRT adds:
  main: memcpy
  scheduler: __acrt_iob_func fwrite memcpy
  std_async: __acrt_iob_func fwrite
```

The reference harness proves the mechanism works for a program with no such
references:

```sh
$ bash scripts/win32_cross/cross_nocrt.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/hello/main.zig /tmp/t51_nocrt_hello /tmp/t51_nocrt_hello/hello.exe
dump: rc=0 error_brk=0 panic=0 c=5 no-crt link ok
XRUNRC=0
$ i686-w64-mingw32-objdump -p /tmp/t51_nocrt_hello/hello.exe | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p'
KERNEL32.dll
```

`cross_nocrt.sh:125-156` currently generates a scratch shim providing `strlen`,
`__main`, `putchar`, `getchar`, `fwrite`, and `__acrt_iob_func`. It does **not**
provide `memcpy`, `strncmp`, `exit`, `getenv`, `time`, or `atexit`; it also
excludes `c_exit.o` from the link (`cross_nocrt.sh:164-174`).

---

## 4. Per-API Win9x equivalent/fallback

Availability evidence used below: Geoff Chappell's KERNEL32 export study
(`https://www.geoffchappell.com/studies/windows/win32/kernel32/api/`), whose
version table explicitly maps `4.0` = Windows 95 original/OSR2, `4.10` =
Windows 98, `4.90` = Windows Me, `5.0` = Windows 2000, `5.1` = Windows XP.
Observed rows:

```text
GetFileSize             3.51 and higher
GetFileSizeEx           5.0 and higher
SetFilePointer          3.51 and higher
SetFilePointerEx        5.0 and higher
GetFileAttributesExA    4.0 from Windows NT 4.0, and higher
FindFirstFileA          3.51 and higher
GetFileTime             3.51 and higher
GetSystemTimeAsFileTime 3.51 and higher
GetEnvironmentVariableA 3.51 and higher
GetTickCount            3.51 and higher
QueryPerformanceCounter 3.51 and higher
QueryPerformanceFrequency 3.51 and higher
GetLongPathNameA        4.10 and higher          # control: Win98+ is spelled 4.10
GetDiskFreeSpaceExA     4.0 from Windows 95 OSR2, and higher  # control: 9x OSR2+
```

The `4.0 from Windows NT 4.0` qualifier excludes the 9x 4.x line: the study
spells a Win98-present API as `4.10 and higher` (`GetLongPathNameA`) and a
Win95-OSR2-present API as `4.0 from Windows 95 OSR2, and higher`
(`GetDiskFreeSpaceExA`). `GetFileAttributesExA` and `FindFirstFileExA` are
qualified as NT 4.0, not 4.10/9x.

Note: Microsoft Learn's "Minimum supported client" is a post-XP support floor,
not an export floor (e.g. it lists Windows XP for `GetFileSize`, which is a
Win95 API). The export study is the loadability evidence; the Microsoft page
`https://learn.microsoft.com/en-us/windows/win32/api/profileapi/nf-profileapi-queryperformancecounter`
lists Windows 2000 as the support floor for QPC but its export is present on
9x. For the three known-bad APIs, Microsoft Learn independently lists Windows
XP as the minimum:
`https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfilesizeex`,
`.../setfilepointerex`, and `.../getfileattributesexa`.

### 4.1 `GetFileSizeEx` → `GetFileSize`

- `GetFileSize` is Win95 (3.51+). Signature returns the low DWORD and writes
  the high DWORD through `lpFileSizeHigh`; combine
  `((u64)hi << 32) | lo`.
- Error semantics: `INVALID_FILE_SIZE` (0xFFFFFFFF) is also a legal size, so
  the caller must check `GetLastError() == NO_ERROR` before treating it as
  failure. `GetFileSizeEx` has an unambiguous BOOL return.
- Proposed `pal_file_size(HANDLE, i64*)` in `zig_pal.c`: call `GetFileSize`,
  set `*out` to the combined 64-bit value, return 1/0. This preserves the
  `sizeHandle` i64 contract and supports >4 GiB files (Win98 FAT32 itself is
  limited to 4 GiB, but the API path is correct).

### 4.2 `SetFilePointerEx` → `SetFilePointer`

- `SetFilePointer` is Win95 (3.51+). It takes low 32 bits and `plDistanceHigh`;
  returns the new low 32 bits and writes the new high 32 bits.
- Split the i64 offset into low/high DWORD; for `FILE_END`/`FILE_CURRENT`
  negative offsets the high DWORD must be sign-extended (two's complement).
- Error semantics: return `INVALID_SET_FILE_POINTER` (0xFFFFFFFF) requires a
  `GetLastError() == NO_ERROR` check (same ambiguity as `GetFileSize`).
- Proposed `pal_file_seek64(HANDLE, i64 distance, i64* new_pos, u32 method)`:
  call `SetFilePointer`, combine the returned low + out high, return 1/0.
  Under `#ifdef ZIG_WIN_NT` keep `SetFilePointerEx` directly.

### 4.3 `GetFileAttributesExA` → `FindFirstFileA` (decision)

**Decision: `FindFirstFileA`, not `CreateFileA` + `GetFileTime`.**

Evidence:
- MinGW-w64 itself emulates `GetFileAttributesEx` on old Windows with
  `FindFirstFile` and copies the `WIN32_FIND_DATAA` fields into
  `WIN32_FILE_ATTRIBUTE_DATA` one-for-one, including `ftLastWriteTime`
  (`/usr/i686-w64-mingw32/include/newapis.h:193-219`, observed with
  `sed -n '180,250p'`). This is the maintainers' documented compatibility
  recipe, not a guess.
- Timestamp fidelity is identical: `WIN32_FILE_ATTRIBUTE_DATA.ftLastWriteTime`
  and `WIN32_FIND_DATA.ftLastWriteTime` are both a `FILETIME` (100-ns ticks
  since 1601). The leading layout is the same: `dwFileAttributes` at 0,
  `ftCreationTime` at 4, `ftLastAccessTime` at 12, `ftLastWriteTime` at 20.
  The existing `WIN_FT_LASTWRITE_OFF = 20` in `std_file.zig:98` works
  unchanged for `WIN32_FIND_DATA`.
- Availability: `FindFirstFileA` and `GetFileTime` are both Win95; the choice
  is semantic, not availability.
- `FindFirstFileA` needs no open handle, no `GENERIC_READ`/share mode, and
  works for directories; `CreateFileA` + `GetFileTime` fails on directories
  and on files locked against read sharing, and costs a handle. The mtime
  capability only needs the last-write time of the path.
- Caveats to record: `FindFirstFileA` treats `*`/`?` in the path as wildcards,
  returns `INVALID_HANDLE_VALUE` on failure, and is subject to `MAX_PATH`.
  `GetFileAttributesExA` has no wildcard behavior. z9torr calls `mtime` on the
  concrete torrent payload path (`resume.zig:201,318`), so this is safe for
  the committed use, but the PAL helper should document the difference.

Proposed `pal_file_mtime(const char* path, i64* out)`: `FindFirstFileA` into a
`WIN32_FIND_DATAA`, `FindClose` on success, read `ftLastWriteTime` at offset
20, convert with the existing `ticks / 10000000 - 11644473600` arithmetic.

### 4.4 `std_os.getenv` → `GetEnvironmentVariableA`

- `GetEnvironmentVariableA` is Win95 (3.51+). It requires a caller buffer:
  call with `size=0` to get the required size (including NUL), then allocate /
  use a static buffer, then call again. `GetLastError()==ERROR_ENVVAR_NOT_FOUND`
  or a non-zero return >= size means unset/error.
- **Semantic difference:** the current `std_os.env` returns a slice into the
  CRT's environment block (`std_os.zig:66-83`); `GetEnvironmentVariableA`
  requires a buffer whose lifetime the caller owns. `std_os.env` has no arena
  parameter, so T5.3 must choose a static/thread-local buffer (single-threaded
  Z98 runtime) or add an internal allocation. This must be explicit; it is not
  a drop-in declaration swap like the file APIs.
- `std_os_pal.zig:23-24` currently declares `getenv`; replace/add the Win32
  extern in the same std-side PAL, or add a `pal_getenv` helper in `zig_pal.c`.

### 4.5 `std_time.time` → `GetSystemTimeAsFileTime`

- `GetSystemTimeAsFileTime` is Win95 (3.51+). It returns a `FILETIME` (100-ns
  ticks since 1601); Unix seconds =
  `ticks / 10000000 - 11644473600` (the same constants already used for
  `mtime` in `std_file.zig:103-104`).
- Proposed `pal_wallclock_unix(i64*)` helper, or a Win32 branch in
  `std_time.zig:116-118` that fills a `FILETIME` via the std-side PAL and
  converts. `std_time_pal.zig:51` currently declares CRT `time`; remove it
  from the no-CRT path.
- Accuracy is coarser than `time()` in principle but the conversion to whole
  seconds is exact for UTC seconds.

### 4.6 `c_exit` / `exit`

- Current `c_exit.c:2` is `void c_exit(int code) { exit(code); }`.
- Current `@exit` lowering emits `exit(...)` directly, not `c_exit`:
  `sf/src/c89_emit.zig:7721-7728` (`.builtin_exit` writes `"exit("`).
  `std_os.zig:61-63` uses `@exit`, so emitted `std_os_*.c` has a direct `exit`
  reference (confirmed in §1.5 and §3).
- Under `ZIG_NO_CRT`, implement `c_exit` as `ExitProcess((UINT)code)` (or
  `TerminateProcess(GetCurrentProcess(), code)`). `ExitProcess` is Win95.
- T5.3 must also route `@exit` through `c_exit` (or provide a no-CRT `exit`
  symbol); changing only `c_exit.c` is insufficient because emitted code calls
  `exit` directly.

### 4.7 `pal_abort` / `abort`

- `pal_abort` is already Win9x-safe: `sf/src/include/zig_pal.c:126-133` uses
  `TerminateProcess(GetCurrentProcess(), 3)` under `_WIN32`, not `abort()`.
  The same is true of the emit literal (`emit_support.zig:805-812`).
- The `abort` import in the current exe comes only from libmingw32's
  `pseudo-reloc.o`, so it disappears under `-nostdlib`. No `abort` shim is
  required unless some future emitted code calls it directly.
- `pal_trap` uses `int3` on i386 (`zig_pal.c:135-166`); no CRT dependency.

### 4.8 `strlen` / `memcpy` / `strncmp` / `zig_runtime` strlen / `atexit`

| Name | Current reference | No-CRT requirement |
|:--|:--|:--|
| `strlen` | `zig_runtime.c:17,23`; `crt2.o`; libmingw32 `pesect.o` | Provide a runtime `strlen` (or local static) in `zig_runtime.c`/`zig_pal.c`. `cross_nocrt.sh:129` already demonstrates the shim. |
| `memcpy` | compiler-generated struct/array copies: z9torr `main`/`scheduler`; `crt2.o` | Add a `memcpy` implementation to the emitted runtime/shim. `cross_nocrt.sh` does **not** provide it today. |
| `strncmp` | libmingw32 `pesect.o` only (not these two programs' emitted code) | T5.3 mandates a shim for general emitted code; add it with `strlen`/`memcpy`. |
| `zig_runtime` strlen | `std_panic`/`std_print` in `zig_runtime.c:17,23` | Same `strlen` shim; no separate copy needed if the runtime defines it before use. |
| `atexit` | `examples/z98/z9play/platform/console_win9x.zig:145` (via `console_win9x_pal.zig:112`); libmingw32 `gccmain`/`crtbegin` also reference it | **Gap not listed in T5.3:** under `-nostdlib` the z9play link will fail unless an `atexit` shim/registry is added or the backstop is rewritten. This is required for the 9x default profile. |

`__acrt_iob_func`/`_iob`: emitted `std_io`/`scheduler`/`std_async` reference
mingw's `__acrt_iob_func` wrapper because `stdout` expands to it. The current
no-CRT scratch shim provides it (`cross_nocrt.sh:151-155`), but the emitted
build tree does not carry that shim. T5.3 must put an equivalent in the
emitted runtime/support so an emitted `build_target.sh` is self-contained.

---

## 5. `emit_support.zig` ↔ `sf/src/include/*` mirror map

`sf/src/c89_emit.zig:784-849` (`emitSupportFiles`) writes the support files;
the byte content lives in `sf/src/emit_support.zig`. Exact map:

| `emit_support.zig` literal emitter (lines) | Emitted file | Canonical mirror | Conditional? |
|:--|:--|:--|:--|
| `emitZigCompatHSupport` (17-77) | `zig_compat.h` | `sf/src/include/zig_compat.h` | always |
| `emitZigRuntimeHSupport` (199-486) | `zig_runtime.h` | `sf/src/include/zig_runtime.h` | always (content depends on `safe_checks`) |
| `emitNetPreludeHSupport` (79-112) | `net_prelude.h` | `sf/src/include/net_prelude.h` | iff `std_net` reachable |
| `emitStdOsPreludeHSupport` (114-129) | `std_os_prelude.h` | `sf/src/include/std_os_prelude.h` | iff `std_os` reachable |
| `emitStdTimePreludeHSupport` (131-192) | `std_time_prelude.h` | `sf/src/include/std_time_prelude.h` | iff `std_time` reachable |
| `emitZigRuntimeCSupport` (488-677) | `zig_runtime.c` | `sf/src/include/zig_runtime.c` | always (content depends on `safe_checks`) |
| `emitZigPalCSupport` (679-1037) | `zig_pal.c` | `sf/src/include/zig_pal.c` | always |
| `emitCExitCSupport` (194-197) | `c_exit.c` | `sf/src/c_exit.c` | always |

Not in the mirror contract:
- `zig_special_types.h` is generated dynamically from the program's typedef
  set (`sf/src/main.zig:1489-1512`); the canonical
  `sf/src/include/zig_special_types.h` is only a stub and intentionally differs
  (observed `diff` exit 1).
- `sf/src/include/net_runtime.c`, `net_runtime.h`, `optstar_repro.h` are
  canonical-only; no emitter writes them (observed emitted tree contains none).

Contract:

```sh
$ bash scripts/check_emit_support.sh /tmp/z9play_m6/zig1_5_clean
[check] emitted zig_compat.h == /workspace/znineeight/sf/src/include/zig_compat.h
[check] emitted zig_runtime.h == /workspace/znineeight/sf/src/include/zig_runtime.h
[check] emitted zig_runtime.c == /workspace/znineeight/sf/src/include/zig_runtime.c
[check] emitted zig_pal.c == /workspace/znineeight/sf/src/include/zig_pal.c
[check] emitted c_exit.c == /workspace/znineeight/sf/src/c_exit.c
[check] net_prelude.h correctly absent (std_net not reachable)
[check] std_os_prelude.h correctly absent (std_os not used)
[check] emitted std_os_prelude.h == /workspace/znineeight/sf/src/include/std_os_prelude.h
[check] std_time_prelude.h correctly absent (std_time not used)
[check] emitted std_time_prelude.h == /workspace/znineeight/sf/src/include/std_time_prelude.h
[check] OK: 7/7 support files byte-identical to canonical (5 core + 2 conditional preludes)
```

Rule: the `emit_support.zig` literal is the source of truth; the
`sf/src/include/*` (and `sf/src/c_exit.c`) file is the canonical mirror that
`check_emit_support.sh` compares against. Both must be edited together
(plan T5.3), and the gate must stay green. Editing only one side breaks the
byte-equality contract even if a local build happens to work.

---

## 6. CLI-help delta

`printUsage()` (`sf/src/main.zig:2015-2030`) documents exactly five spellings:
`-mm<N>`, `-s<N>`, `-osl`, `-osw`, `--target` (observed by running the compiler
with no arguments, which prints the block above).

The parser (`sf/src/main.zig:1736-1814`) recognizes these additional options:

| Parsed option (aliases) | Parse site(s) | Documented? |
|:--|:--|:--|
| `--dump-c89` | 1736 | **no** |
| `--max-mem`, `-m` | 1738-1742 | **no** |
| `--max-errors`, `-e` | 1750-1754 | **no** |
| `--output-dir`, `-o` | 1755-1760 | **no** |
| `--quiet`, `-q` | 1761-1762 | **no** |
| `--test` | 1763-1764 | **no** |
| `--sanity-test` | 1765-1766 | **no** |
| `--warnings-as-errors`, `-W` | 1767-1768 | **no** |
| `--color` | 1769-1773 | **no** |
| `--error-format` | 1774-1778 | **no** |
| `--track-memory` | 1779-1780 | **no** |
| `--no-null-check` | 1781-1782 | **no** |
| `--no-lifetime-check` | 1783-1784 | **no** |
| `--no-leak-check` | 1785-1786 | **no** |
| `--warn-all` | 1787-1788 | **no** |
| `--warn-error` | 1789-1791 | **no** |
| `--markers` | 1792-1793 | **no** |
| `-I` | 1794-1799 | **no** |
| `--lib-dir` | 1794-1799 | **no** |
| `-ffast` | 1809-1811 | **no** |
| `-fsafe` | 1812-1814 | **no** |

**Verified exact count:** 21 grouped options / 26 distinct spellings are parsed
but undocumented (the five documented spellings are `-mm`, `-s`, `-osl`,
`-osw`, `--target`; 31 parsed spellings total − 5 = 26).

The brief/plan's "expected 12" (which then lists 15) does **not** match the
tree. In particular:
- `--dump-types` and `--dump-lir` are declared as constants
  (`sf/src/main.zig:1697-1698`) but are **never matched or read**; they are
  dead constants, not parsed flags. `cli.dump_types`/`cli.dump_lir` are only
  initialized (`:1671-1672`).
- `-t`, `-a`, `-y`, `-l` are also declared (`:1718-1721`) and never matched.
- The undocumented set above includes flags missing from the brief's list
  (`--max-mem/-m`, `--max-errors/-e`, `--quiet/-q`, `--test`, `--sanity-test`,
  `--warnings-as-errors/-W`, `--color`, `--error-format`, `--track-memory`).

T5.2's `--help` truth-up must therefore decide whether to implement/drop the
six dead constants before documenting them; silently listing
`--dump-types`/`--dump-lir` as working flags would be false.

---

## 7. Whitelist drafts (9x default, nt opt-in)

**The whitelist is the loadability gate.** Windows 9x resolves the complete
import table at load time; any missing DLL or named export fails the process
before `main`. Wine cannot prove Win98 loadability: Wine's KERNEL32 exports
modern APIs and its loader does not model Win9x. The gate must be the
mechanical per-DLL/per-import whitelist (plus a Win98 export reference), not a
Wine run.

Min-OS notation: `95` = Win95/98/Me export; `NT4` = NT 4.0 only in the 4.x
line, not 9x; `2000`/`XP` = not 9x. The export-study source is §4. For
WinMM/Winsock, `waveOut*` is documented as requiring Windows 95 or later
(Windows API guide/AllAPI) and Winsock 1.1 is the Win95 Winsock (Microsoft
`WSAStartup` remarks: "On Windows 95 … Windows Sockets version 1.1 is the
highest version … supported").

### 7.1 KERNEL32.dll (union: 45 imports; P=z9play, T=z9torr)

| Import | Used | Min OS | 9x | nt |
|:--|:--:|:--:|:--:|:--:|
| CloseHandle | P T | 95 | PASS | PASS |
| CreateFileA | P T | 95 | PASS | PASS |
| DeleteCriticalSection | P T | 95 | PASS | PASS |
| DeleteFileA | P T | 95 | PASS | PASS |
| EnterCriticalSection | P T | 95 | PASS | PASS |
| FillConsoleOutputCharacterA | P | 95 | PASS | PASS |
| FlushFileBuffers | P T | 95 | PASS | PASS |
| FreeLibrary | P T | 95 | PASS | PASS |
| GetConsoleCursorInfo | P | 95 | PASS | PASS |
| GetConsoleMode | P | 95 | PASS | PASS |
| GetConsoleScreenBufferInfo | P | 95 | PASS | PASS |
| GetCurrentDirectoryA | P T | 95 | PASS | PASS |
| GetCurrentProcess | P T | 95 | PASS | PASS |
| GetFileAttributesA | P T | 95 | PASS | PASS |
| **GetFileAttributesExA** | P T | **NT4** | **FAIL** | PASS (XP+) |
| **GetFileSizeEx** | P T | **2000/XP** | **FAIL** | PASS (XP+) |
| GetFileType | T | 95 | PASS | PASS |
| GetLastError | P T | 95 | PASS | PASS |
| GetModuleFileNameA | P T | 95 | PASS | PASS |
| GetModuleHandleA | P T | 95 | PASS | PASS |
| GetNumberOfConsoleInputEvents | P | 95 | PASS | PASS |
| GetProcAddress | P T | 95 | PASS | PASS |
| GetStartupInfoA | P T | 95 | PASS | PASS |
| GetStdHandle | P T | 95 | PASS | PASS |
| GetTickCount | P T | 95 | PASS | PASS |
| InitializeCriticalSection | P T | 95 | PASS | PASS |
| LeaveCriticalSection | P T | 95 | PASS | PASS |
| LoadLibraryA | P T | 95 | PASS | PASS |
| MoveFileA | P T | 95 | PASS | PASS |
| QueryPerformanceCounter | P T | 95 | PASS | PASS |
| QueryPerformanceFrequency | P T | 95 | PASS | PASS |
| ReadConsoleInputA | P | 95 | PASS | PASS |
| ReadFile | P T | 95 | PASS | PASS |
| SetConsoleCursorInfo | P | 95 | PASS | PASS |
| SetConsoleCursorPosition | P | 95 | PASS | PASS |
| SetConsoleMode | P | 95 | PASS | PASS |
| **SetFilePointerEx** | P T | **2000/XP** | **FAIL** | PASS (XP+) |
| SetUnhandledExceptionFilter | P T | 95 | PASS | PASS |
| Sleep | P T | 95 | PASS | PASS |
| TerminateProcess | P T | 95 | PASS | PASS |
| TlsGetValue | P T | 95 | PASS | PASS |
| VirtualProtect | P T | 95 | PASS | PASS |
| VirtualQuery | P T | 95 | PASS | PASS |
| WriteConsoleA | P T | 95 | PASS | PASS |
| WriteFile | P T | 95 | PASS | PASS |

9x verdict: **FAIL** (3 imports). After T5.3 replaces those three with
`GetFileSize`/`SetFilePointer`/`FindFirstFileA`, all 45 rows are PASS.
nt verdict: **PASS** for the proposed nt baseline (XP+); note the two `Ex`
APIs are 2000+/XP+, so a literal NT 4.0 target would fail them.

### 7.2 msvcrt.dll (28 imports; P T)

| Import | Min OS | 9x | nt |
|:--|:--:|:--:|:--:|
| `__getmainargs` | 95 (msvcrt) | **FAIL** | PASS |
| `__initenv` | 95 | **FAIL** | PASS |
| `__p__acmdln` | 95 | **FAIL** | PASS |
| `__p__commode` | 95 | **FAIL** | PASS |
| `__p__fmode` | 95 | **FAIL** | PASS |
| `__set_app_type` | 95 | **FAIL** | PASS |
| `__setusermatherr` | 95 | **FAIL** | PASS |
| `_amsg_exit` | 95 | **FAIL** | PASS |
| `_cexit` | 95 | **FAIL** | PASS |
| `_initterm` | 95 | **FAIL** | PASS |
| `_iob` | 95 | **FAIL** | PASS |
| `_onexit` | 95 | **FAIL** | PASS |
| `abort` | 95 | **FAIL** | PASS |
| `calloc` | 95 | **FAIL** | PASS |
| `exit` | 95 | **FAIL** | PASS |
| `fprintf` | 95 | **FAIL** | PASS |
| `free` | 95 | **FAIL** | PASS |
| `fwrite` | 95 | **FAIL** | PASS |
| `getchar` | 95 | **FAIL** | PASS |
| `getenv` | 95 | **FAIL** | PASS |
| `malloc` | 95 | **FAIL** | PASS |
| `memcpy` | 95 | **FAIL** | PASS |
| `putchar` | 95 | **FAIL** | PASS |
| `signal` | 95 | **FAIL** | PASS |
| `strlen` | 95 | **FAIL** | PASS |
| `strncmp` | 95 | **FAIL** | PASS |
| `vfprintf` | 95 | **FAIL** | PASS |
| `time` | 95 | **FAIL** | PASS |

9x verdict: **FAIL** for the whole DLL. This is a *profile policy* failure, not
an API-availability question: the plan's default 9x profile is no-CRT, so any
msvcrt import is disallowed. nt verdict: **PASS** (normal CRT link).

### 7.3 WINMM.DLL (6 imports; z9play)

| Import | Min OS | 9x | nt |
|:--|:--:|:--:|:--:|
| `waveOutClose` | 95 | PASS | PASS |
| `waveOutOpen` | 95 | PASS | PASS |
| `waveOutPrepareHeader` | 95 | PASS | PASS |
| `waveOutReset` | 95 | PASS | PASS |
| `waveOutUnprepareHeader` | 95 | PASS | PASS |
| `waveOutWrite` | 95 | PASS | PASS |

9x/nt verdict: **PASS**.

### 7.4 WSOCK32.DLL (20 imports; z9torr)

| Import | Min OS | 9x | nt |
|:--|:--:|:--:|:--:|
| `WSACleanup` | 95 (Winsock 1.1) | PASS | PASS |
| `WSAGetLastError` | 95 | PASS | PASS |
| `WSAStartup` | 95 | PASS | PASS |
| `accept` | 95 | PASS | PASS |
| `bind` | 95 | PASS | PASS |
| `closesocket` | 95 | PASS | PASS |
| `connect` | 95 | PASS | PASS |
| `gethostbyname` | 95 | PASS | PASS |
| `getsockopt` | 95 | PASS | PASS |
| `htonl` | 95 | PASS | PASS |
| `htons` | 95 | PASS | PASS |
| `ioctlsocket` | 95 | PASS | PASS |
| `listen` | 95 | PASS | PASS |
| `recv` | 95 | PASS | PASS |
| `recvfrom` | 95 | PASS | PASS |
| `select` | 95 | PASS | PASS |
| `send` | 95 | PASS | PASS |
| `sendto` | 95 | PASS | PASS |
| `setsockopt` | 95 | PASS | PASS |
| `socket` | 95 | PASS | PASS |

9x/nt verdict: **PASS**.

### 7.5 Profile verdicts (current binaries)

| Profile | z9play | z9torr | Why |
|:--|:--|:--|:--|
| `9x` (default) | **FAIL** | **FAIL** | 3 KERNEL32 XP+/NT4 imports + msvcrt (no-CRT policy) |
| `nt` (opt-in) | **PASS** | **PASS** | all current imports allowed on XP+ |

After T5.3: 9x z9play = KERNEL32 (all PASS) + WINMM + no msvcrt; 9x z9torr =
KERNEL32 (all PASS) + WSOCK32 + no msvcrt. The whitelist must be re-run on the
actual post-T5.3 binaries; this table is a draft.

---

## 8. Proposed `-osw [9x|nt]` CLI semantics

**Proposal:**

- Bare `-osw` keeps today's meaning — Windows target — and selects the
  **9x default profile**. `-osw 9x` is the explicit same thing.
- `-osw nt` selects the **NT opt-in profile**. It emits `-DZIG_WIN_NT` into the
  emitted build scripts. With no `ZIG_WIN_NT`, the C code takes the Win9x
  branch (`GetFileSize`, `SetFilePointer`, `FindFirstFileA`).
- The profile argument is consumed only when the next token is exactly `9x` or
  `nt`; any other token remains the input file, so `zig1 -osw app.zig` is
  unchanged and `zig1 -osw nt app.zig` works.
- `-osl` and `--target linux` set the Linux target; the profile is then
  irrelevant (ignored). `--target windows` is the long-form of bare `-osw`
  (9x default). Order follows the existing target-flag rule: the last target
  flag wins. No new `--target` values are added; `nt` is only an `-osw` argument.
- Emitted scripts:
  - **9x (default):** `build_target.sh` mingw branch adds `-DZIG_NO_CRT` and
    links `-nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32` plus
    `-lwinmm`/`-lwsock32` if the program reaches those surfaces.
    `build_target.bat`/`build_owc.bat` add the corresponding profile define
    (`/DZIG_NO_CRT`, `/dZIG_NO_CRT`); their native CRT links are not the
    committed no-CRT gate.
  - **nt:** `build_target.sh` adds `-DZIG_WIN_NT` (and does **not** define
    `ZIG_NO_CRT`); the normal mingw CRT link stays. The `.bat`/`.owc` scripts
    add `/DZIG_WIN_NT`/`/dZIG_WIN_NT`.
- The compiler's own `target_is_windows` remains true for both profiles; only
  the emitted C define / build-script link form changes. `@isWindows()` still
  folds to true in both.

Examples:

```sh
# 9x default (no-CRT; Win95/98/Me)
zig1 -osw -o /tmp/build9x examples/z98/z9play/main.zig
# same, explicit
zig1 -osw 9x -o /tmp/build9x examples/z98/z9play/main.zig
# NT/XP opt-in (ZIG_WIN_NT; normal CRT)
zig1 -osw nt -o /tmp/buildnt examples/z98/z9play/main.zig
# Linux is unchanged; profile is ignored
zig1 -osl -o /tmp/buildlin examples/z98/z9play/main.zig
zig1 --target windows -o /tmp/build9x examples/z98/z9play/main.zig  # 9x
```

Open point (recorded, not resolved here): the exact `nt` baseline. The plan
says "XP/NT layer"; this proposal treats `nt` as modern NT-family (Windows
2000/XP+), where the committed `GetFileSizeEx`/`SetFilePointerEx` work. A
literal NT 4.0 baseline would need the 9x replacements on the `nt` path too.

---

## 9. Inventory of what T5.2 / T5.3 must change (file:line)

### T5.2 — compiler plumbing

| File:line | Required change |
|:--|:--|
| `sf/src/main.zig:68-95` | Add `target_win_profile` (or equivalent) to `CompilerCli`. |
| `sf/src/main.zig:1727-1728` | `-osl`/`-osw` constants; add profile token handling. |
| `sf/src/main.zig:1800-1808` | Bare `-osw` = 9x; consume `9x`/`nt`; pass profile to emission. |
| `sf/src/main.zig:1645` | Pass the profile into `c89_mod.emitBuildScripts`. |
| `sf/src/main.zig:2015-2030` | `--help` truth-up: document all parsed flags (exact set §6) and the profile. |
| `sf/src/c89_emit.zig:8532-8563` | `emitBuildTargetSh`: profile define (`-DZIG_NO_CRT` or `-DZIG_WIN_NT`), no-CRT link form, libs. |
| `sf/src/c89_emit.zig:8564-8585` | `emitBuildTargetBat`: profile define. |
| `sf/src/c89_emit.zig:8586-8625` | `emitBuildOwcBat`: profile define. |
| `sf/src/c89_emit.zig:8626-8642` | `emitBuildScripts` signature/plumbing for the profile. |
| `sf/src/main.zig:1697-1698`, `1718-1721` | Dead `--dump-types`/`--dump-lir`/`-t`/`-a`/`-y`/`-l` constants: implement or remove before `--help` claims them. |

### T5.3 — semantics + no-CRT runtime

| File:line | Required change |
|:--|:--|
| `sf/src/std_file.zig:224-233` | `seekHandle` Win32: replace `SetFilePointerEx` with `pal_file_seek64`. |
| `sf/src/std_file.zig:237-245` | `sizeHandle` Win32: replace `GetFileSizeEx` with `pal_file_size`. |
| `sf/src/std_file.zig:319-331` | `mtime` Win32: replace `GetFileAttributesExA` with `pal_file_mtime` (`FindFirstFileA`). |
| `sf/src/std_file_pal.zig:26-28` | Remove/retain under `ZIG_WIN_NT`: `SetFilePointerEx`, `GetFileSizeEx`; add `extern "c"` helpers. |
| `sf/src/std_file_pal.zig:39` | Remove/retain under `ZIG_WIN_NT`: `GetFileAttributesExA`; add `pal_file_mtime`. |
| `sf/src/std_os.zig:66-84` | `env`: Win32 `GetEnvironmentVariableA` path (buffer ownership decision required). |
| `sf/src/std_os_pal.zig:23-24` | Replace/add `getenv` with the Win32 env extern/helper. |
| `sf/src/std_time.zig:116-118` | `wallClockUnix`: Win32 `GetSystemTimeAsFileTime` conversion. |
| `sf/src/std_time_pal.zig:50-51` | Remove CRT `time` from the no-CRT path; add the Win32 extern/helper. |
| `sf/src/std_os.zig:61-63`, `sf/src/c89_emit.zig:7721-7728` | `@exit` must route to `c_exit` (not direct CRT `exit`) under no-CRT. |
| `sf/src/c_exit.c:2` | `ZIG_NO_CRT` → `ExitProcess((UINT)code)` (or `TerminateProcess`). |
| `sf/src/emit_support.zig:194-197` | Mirror the `c_exit.c` change. |
| `sf/src/include/zig_pal.c:126-133` | `pal_abort` already Win32-safe; no change expected. |
| `sf/src/include/zig_pal.c` (near 241-320) | Add `pal_file_size`, `pal_file_seek64`, `pal_file_mtime`; `#ifdef ZIG_WIN_NT` modern calls vs Win95 defaults. |
| `sf/src/include/zig_pal.c:348-355` | `mainCRTStartup` stub exists; keep. |
| `sf/src/include/zig_runtime.c:17,23` | `strlen` use; provide no-CRT implementation/shim. |
| `sf/src/emit_support.zig:488-677` | Mirror `zig_runtime.c` changes (strlen/memcpy/strncmp). |
| `sf/src/emit_support.zig:679-1037` | Mirror `zig_pal.c` changes (file helpers, env/time helpers, shims). |
| `sf/src/emit_support.zig:1027` | `ZIG_NO_CRT` `mainCRTStartup` literal; keep in sync. |
| `sf/src/c89_emit.zig:5842-5866`, `7694-7707`, `7709-7719` | `fwrite`/`putchar`/`getchar` emission; the no-CRT shim must cover them (or the emitter must call a runtime wrapper). |
| `scripts/win32_cross/cross_nocrt.sh:125-156` | Reference shim only (scratch, not emitted). T5.3 must move/duplicate the runtime shims into emitted support so `build_target.sh` is self-contained. |
| `examples/z98/z9play/platform/console_win9x.zig:145`, `console_win9x_pal.zig:112` | `atexit` backstop: add a no-CRT shim/registry or rewrite. **Not in T5.3's stated list; required for 9x z9play.** |

---

## 10. Verification and gaps/concerns

### Re-verified materials

- Compiler md5 `2c48fa702393032c2b711a8d982bd388` (matches brief).
- z9play and z9torr both build as PE32 i386 with the current compiler; imports
  as listed.
- z9play `tier_win9x.sh` re-run: **14 passed, 0 failed, 0 skipped**,
  `TIER_WIN9X PASS`; imports `KERNEL32.dll msvcrt.dll WINMM.DLL`; `-osw
  --dump-c89` md5 `87856b43091e2bf5d992fc795d9764f2` (stable 2x); Wine WAV
  parity `max_delta=1 rms_milli=36`; console probe
  `entered=1,raw_changed=1,restored=1`.
- `check_emit_support.sh` green (7/7, output in §5).
- no-CRT reference harness builds `hello` as KERNEL32-only.

### Concerns / gaps (no guessing)

1. **CLI "12 undocumented flags" is stale.** The tree has 21 grouped / 26
   spelling-level parsed-but-undocumented flags, and `--dump-types`/
   `--dump-lir` are not parsed at all (§6). T5.2 must not document dead flags
   as functional.
2. **`atexit` no-CRT gap.** z9play's Win9x console backstop calls `atexit`
   (`console_win9x.zig:145`) and the CRT/libmingw32 pull it in. It is absent
   from T5.3's runtime list and unresolved under `-nostdlib`; the 9x z9play
   link will fail until handled.
3. **The no-CRT shim is harness-only.** `cross_nocrt.sh` generates
   `strlen`/`putchar`/`getchar`/`fwrite`/`__acrt_iob_func` in its scratch
   `$WORK`; the emitted tree carries no such shim. T5.3 must make the emitted
   runtime/scripts self-contained, and add `memcpy`/`strncmp` (the harness
   lacks them).
4. **`std_os.env` buffer semantics.** `GetEnvironmentVariableA` needs a
   caller-owned buffer; `std_os.env` has no arena and currently returns a
   pointer into the CRT environment block. T5.3 needs an explicit
   static/thread-local or allocation decision.
5. **`nt` baseline ambiguity.** The proposal treats `nt` as modern NT/XP+
   (where `GetFileSizeEx`/`SetFilePointerEx` pass). If literal NT 4.0 is
   intended, both `Ex` APIs fail and the 9x helpers must also be used on the
   `nt` paths.
6. **`FindFirstFileA` semantics.** Chosen for mtime because MinGW's own
   Win95 compatibility shim uses it and FILETIME fidelity is identical.
   Wildcard characters in a path and `MAX_PATH` are behavior differences from
   `GetFileAttributesExA`; z9torr uses concrete payload paths only.
7. **z9play's emitted `build_target.sh` has empty `LIBS`.** It will not link
   `waveOut*` without `-lwinmm`; the tier supplies `-lwinmm` manually. T5.2/T5.5
   should either add winmm to the emitted script (reachability-driven) or keep
   the harness as the documented build path.
8. **Wine is not a Win98 loader.** The whitelist/export study is the
   loadability gate; the Wine 14/14 tier proves runtime behavior of the WAV
   sink/console path on Wine, not Win98 import resolution.
9. **No real Win98 run** (unchanged from the manual-procedure task). The
   `GetFileSize`/`SetFilePointer`/`FindFirstFileA` helpers need the Wine↔Linux
   cross-probe and a real/manual Win98 confirmation at the T5.3 gate.

---

## 11. Gate command output (re-run, evidence)

```sh
$ ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/z9play_tier_t51 \
    sh examples/z98/z9play/tests/tier_win9x.sh
...
ok   - only expected DLL imports (KERNEL32.dll msvcrt.dll WINMM.DLL )
--dump-c89 (-osw) md5: 87856b43091e2bf5d992fc795d9764f2
ok   - Wine WAV parity max_delta=1 rms_milli=36 (<= 2 / 100)
ok   - raw-mode restore asserted under Wine (win9x_console_probe:entered=1,raw_changed=1,restored=1)
== tier_win9x summary: 14 passed, 0 failed, 0 skipped ==
TIER_WIN9X PASS
```

No source or doc file other than this report was modified. `git diff --check`
is clean for the report.
