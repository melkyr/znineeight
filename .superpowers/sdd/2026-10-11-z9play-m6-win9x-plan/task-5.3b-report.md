# M6 Task T5.3b report — native-toolchain no-CRT design (REPORT ONLY)

**Status:** DONE_WITH_CONCERNS. The design is complete, but several claims are
necessarily *design-verified; hardware verification pending* because Amendment 5
forbids downloading/installing OpenWatcom and forbids MSVC/OWC runtime probes.
§7 states exactly what is not locally determinable and why it is not
design-blocking.

**Scope:** report-only. Zero repo source edits. The only file created in the
repository by this task is this report. `run.err`/`run.out`/`progress.md` were
left untouched. No push. No downloads, installs, or native-toolchain runs.

**Authority:** `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`
`### Amendment 4` / `### Amendment 5` → `#### Task T5.3b` (operator rulings
2026-10-18), brief
`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-5.3b-brief.md`.
Context: `task-5.1-report.md`, `task-5.3a-report.md`.

**Base / host evidence (observed):**

```text
$ git rev-parse HEAD
c76ca4307045fc2bc4b0927064c3e4282aefd2d8
$ git status --short
?? run.err
$ md5sum /tmp/m6/zig1_5_clean
983ff15c251ae37a1a6c7b7fe8b7212f  /tmp/m6/zig1_5_clean
$ i686-w64-mingw32-gcc --version | head -1
i686-w64-mingw32-gcc (GCC) 12-win32
$ wine --version
wine-8.0 (Debian 8.0~repack-4)
$ command -v cl wcc386 wlink
(no output: not installed)
```

`/tmp/m6/zig1_5_clean` is used only to dump emitted C for static analysis. No
emitted `.exe` was run by this task.

---

## 0. Executive summary / decisions

1. **Both native no-CRT variants use vendor static compiler-runtime helper
   objects, not hand-written C helpers.** The helper ABIs are not ordinary C
   calling conventions:
   - OpenWatcom's 64-bit helpers take arguments in `EDX:EAX`/`ECX:EBX` and return
     quotient **and** remainder registers (vendor source below); a C function
     cannot reproduce that ABI without assembly.
   - MSVC's combined div/rem helpers (`_alldvrm`/`_aulldvrm`) return two 64-bit
     results; `_ftol` is FPU-rounding-sensitive; `_chkstk` is a raw stack-probe
     routine.
   The safe design is therefore: **link the vendor static helper objects**
   (`libcmt.lib` for MSVC 6, `clib3r.lib` for OpenWatcom) with default-library
   searching disabled. The linker pulls only the helper members actually
   referenced. No `msvcrt.dll` import is created.
2. **Do not use `/Gs` to suppress `__chkstk`.** The emitted z9torr has stack
   frames far above 4 KiB (host `-fstack-usage` static analysis: `main`
   545,024 bytes, `addrSeen` 201,152, `schedulerInit` 136,080). Microsoft
   documents that the default `/Gs4096` stack probe exists for correct Windows
   stack growth and recommends not changing it. We keep the default and provide
   the probe via the vendor static runtime.
3. **Entry decoration differs per toolchain.** Use `__stdcall` for MSVC 6
   (`_mainCRTStartup@0`), `__cdecl` for OpenWatcom
   (`_mainCRTStartup`), and cdecl for mingw (`_mainCRTStartup`). The shared
   `zig_pal.c` startup gets a compiler-conditional calling convention.
4. **Out-of-scope-for-mingw finding: native `<stdio.h>` macro-expands
   `stdout`/`stderr`/`getchar`/`putchar` onto `_iob`/`__iob` and
   `getc`/`putc` (and likely `_filbuf`/`_flsbuf`).** T5.3a's `_iob` omission is
   correct for the pinned mingw headers only. The native no-CRT shim must
   define `_iob`/`__iob` and the underlying stream functions for MSVC/OWC.
   §3.1 gives the exact toolchain split; this is an addition, not a
   contradiction of the T5.3a ruling.
5. **OpenWatcom's emitted stack size must be raised.** The current
   `build_owc.bat` uses `option stack=65536`; z9torr's 545 KiB frame cannot fit.
   The new scripts use `option stack=1048576` and the WinNT commit default is
   `min(64K, stack)` per OpenWatcom's *COMMIT* documentation, so this does not
   commit 1 MiB at startup.
6. **Old `build_target.bat` / `build_owc.bat` names stay as aliases.** The
   repository's manuals reference them in many places. In a 9x dump they call
   the `_nocrt` script; in an nt dump they call the `_crt` script. No old name is
   removed and no reference dangles.
7. **Static-CRT alternates are separate scripts** (`build_target_crt.bat`,
   `build_owc_crt.bat`). They link the vendor static CRT, produce a single EXE,
   and import only OS DLLs; they are marked hardware-unverified and must still
   pass the Win9x import whitelist before being called 9x-safe.

---

## 1. MSVC 6.0 no-CRT design

### 1.1 Compile command

Exact compiler flags (one `cl` invocation per `.c` file):

```bat
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_NO_CRT /Zl /I .
cl %CFLAGS% <module>.c
...
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
```

Rationale / citations:

- `/Zl` — “Omits the default C runtime library name from the .obj file.” and
  “If you use this option you must provide the required components in some other
  way.” (Microsoft Learn, `/Zl`, https://learn.microsoft.com/en-us/cpp/build/reference/zl-omit-default-library-name?view=msvc-170).
- `/Za` — “When both C compilation and the /Za option are specified, the C
  compiler conforms strictly to the C89/C90 standard.” (Microsoft Learn, `/Za`,
  https://learn.microsoft.com/en-us/cpp/build/reference/za-ze-disable-language-extensions?view=msvc-170).
- `__int64` remains valid under `/Za`: “For compatibility with previous
  versions, `_int8`, `_int16`, `_int32`, and `_int64` are synonyms for
  `__int8`, `__int16`, `__int32`, and `__int64` unless compiler option `/Za`
  ... is specified.” Only the single-underscore synonyms are removed
  (Microsoft Learn, `__int64`,
  https://learn.microsoft.com/en-us/cpp/cpp/int8-int16-int32-int64?view=msvc-170).
  `sf/src/include/zig_compat.h` uses `__int64`/`unsigned __int64`, not
  `_int64`, so `/Za` is compatible.
- `/DZIG_WIN32` is the existing emitted target define; `/DZIG_NO_CRT` selects
  the T5.3 shim set and the no-CRT startup.
- `/I .` keeps the emitted tree self-contained.

### 1.2 Link command

Exact link invocation (the `<obj>` list is all reachable module `.obj` files plus
the four support objects; `winmm.lib` is always present because z9play's
`audio_win9x` references `waveOut*`; `wsock32.lib` is emitted only when
`net_emitted`):

```bat
link /NODEFAULTLIB /subsystem:console,4.0 /STACK:2097152 ^
     /entry:_mainCRTStartup@0 ^
     <module>.obj ... zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj ^
     kernel32.lib winmm.lib [wsock32.lib] libcmt.lib /out:%OUT%
```

- `/NODEFAULTLIB` — “removes all libraries not explicitly specified on the
  linker command-line. This also includes `#pragma`, `cl.exe` command-line
  switches, libs referenced by other libs, and so on.” (Microsoft Learn,
  `/NODEFAULTLIB`,
  https://learn.microsoft.com/en-us/cpp/build/reference/nodefaultlib-ignore-libraries?view=msvc-170).
  This is why `wsock32.lib` must be listed explicitly when `net_prelude.h` has a
  `#pragma comment(lib,"wsock32.lib")`.
- `/entry:_mainCRTStartup@0` — MSVC C `__stdcall` functions are decorated with a
  leading underscore and `@<bytes>`; the startup is declared `__stdcall` so its
  symbol is exactly `_mainCRTStartup@0` (Microsoft Learn, *Decorated names*,
  https://learn.microsoft.com/en-us/cpp/build/reference/decorated-names?view=msvc-170).
  The `/ENTRY` option “specifies an entry point function as the starting address
  for an .exe file or DLL” and the function “must be defined to use the
  `__stdcall` calling convention” (Microsoft Learn, `/ENTRY`,
  https://learn.microsoft.com/en-us/cpp/build/reference/entry-entry-point-symbol?view=msvc-170).
  The startup never returns; it calls `exit(main(...))`.
- `/subsystem:console,4.0` — console image with the Win9x-era subsystem version.
  Microsoft documents `/SUBSYSTEM` as selecting the Win32 character-mode
  subsystem and allowing `major[.minor]`
  (https://learn.microsoft.com/en-us/cpp/build/reference/subsystem-specify-subsystem?view=msvc-170).
- `/STACK:2097152` — explicit 2 MiB reserve; Microsoft documents the x86 default
  as 1 MB (https://learn.microsoft.com/en-us/cpp/build/reference/stack-stack-allocations?view=msvc-170).
  2 MiB is chosen because the host static analysis measures z9torr's largest
  frame at 545 KiB and a deeper call chain must still fit. The default commit
  remains 4 KiB.
- `kernel32.lib` is the only OS import library always required. `winmm.lib`
  and `wsock32.lib` are import libraries for OS DLLs; unused members do not
  create imports.
- `libcmt.lib` is the vendor static compiler-runtime helper library (§1.4).
  It is **not** the dynamic CRT and does not create an `msvcrt.dll` import.

`libcmt.lib` is listed explicitly after the objects. With `/NODEFAULTLIB`, the
linker searches only libraries named on the command line; it extracts only
members that resolve currently-undefined symbols. The vendor helper members
(`chkstk`, 64-bit arithmetic, `fltused`, `ftol`) are self-contained; the CRT
startup and stdio members are not pulled because our objects define
`mainCRTStartup`, `exit`, `atexit`, `fwrite`, and the other shim symbols.

### 1.3 Startup + `GetCommandLineA` argv parser (shared C)

Owner: `sf/src/include/zig_pal.c`, guarded `_WIN32 && ZIG_NO_CRT`; mirrored in
`sf/src/emit_support.zig`. Current stub:
`sf/src/include/zig_pal.c:349-355`, mirror `sf/src/emit_support.zig:1029-1036`.

Design:

```c
#if defined(_MSC_VER)
void __stdcall mainCRTStartup(void)
#else
void __cdecl mainCRTStartup(void)
#endif
{
    z98_parse_command_line();          /* fills g_argc/g_argv */
    exit(main(g_argc, g_argv));        /* normal return runs atexit */
}
```

- MSVC symbol: `_mainCRTStartup@0`; OWC `__cdecl` symbol:
  `_mainCRTStartup`; mingw: `_mainCRTStartup`.
- `main` is declared `int main(int argc, char** argv);` with the compiler's
  default calling convention. The emitted `main` is compiled by the same
  toolchain with the same default convention, so the declaration matches.
  (Under OpenWatcom the default is the register convention, not `__cdecl`; do
  **not** declare `main` `__cdecl`.)
- `exit`, not `ExitProcess`, is called on the normal-return path so the T5.3a
  `atexit` registry runs (T5.3a §2).
- `__main` is defined as an empty function under no-CRT for the GCC-emitted
  z9torr reference (`task-5.3a-report.md` §11.1); MSVC/OWC do not need it but the
  empty definition is harmless.

Parser design (C89, static storage, no allocation):

- `static char g_cmdline[32768];`
- `static char* g_argv[256];`
- `static int g_argc;`
- Copy `GetCommandLineA()` into `g_cmdline` (truncate at
  `sizeof(g_cmdline)-1`, always NUL-terminate).
- Apply the MSVCRT command-line rules: whitespace separates arguments; a
  double quote toggles quote mode; an even number of backslashes before a quote
  produces half as many backslashes and the quote is a delimiter-toggle; an odd
  number produces half as many backslashes and a literal quote; otherwise
  backslashes are literal. `argv[0]` is the first token (program path).
- Stop at `g_argc == 256`; excess tokens are ignored rather than overflowing.
- The array and buffer are process-lifetime static storage; single-threaded
  assumption, same as T5.3a's env/atexit designs.
- `GetCommandLineA` is already in the 9x KERNEL32 whitelist
  (`task-5.3a-report.md` §10.2) and was probed in T5.3a scaffold builds
  (§11.2); it is a Win95 export per T5.1 §4.

### 1.4 Runtime-helper set actually required by the emitted C

Static analysis of the `/tmp/m6/zig1_5_clean` dumps (no native compiler
involved) gives these classes. Representative emitted sites:

| C operation in emitted/support C | Evidence (file:line in dumped tree) | MSVC 6 helper family |
|:--|:--|:--|
| signed/unsigned 64-bit multiply | `zig_runtime.h:53,68` (`zig_wrap_mul_s/u`), `ogg_06518614.c:1709` (`last_granule * 1000`) | `_allmul` |
| signed 64-bit divide | `zig_runtime.h:103-107` (`maxs / b`, `mins / a`, ...) | `_alldiv` (and `_allrem`; combined `_alldvrm` possible) |
| unsigned 64-bit divide + remainder | `zig_pal.c:77-78` (`value % 10`, `value /= 10`), `ogg_06518614.c:1712` | `_aulldiv` + `_aullrem` (combined `_aulldvrm` possible) |
| 64-bit left shift | `zig_runtime.h:71,117` (`x << (b & 63ULL)`), `vorbis_info_B6B89893.c:69` | `_allshl` |
| signed 64-bit right shift | `zig_runtime.h:120` (`maxs >> b`, `mins >> b`) | `_allshr` |
| unsigned 64-bit right shift | `zig_runtime.h:113` (`zig_ovf_maxu(w) >> b`) | `_aullshr` |
| float/double -> 64-bit integer | `zig_pal.c:213` (`(i64)value`), `zig_pal.c:229` (`(u64)frac_part`) | `_ftol` (VC6; later toolsets may use `_ftol2`/unsigned variant) |
| integer -> float/double | `zig_pal.c:220,225,231` (`(f64)int_part`, `(f64)frac_int`) | x87 inline on MSVC 6 (expected); if VC6 emits a helper, `libcmt.lib` supplies it |
| floating point present in TU | `zig_pal.c:191-235`, `dsp_8A8E2260.c`, `decode_512E9AC7.c`, `codebook_E72485F5.c`, `std_math_80387A0C.c` | `_fltused` marker |
| stack probe for frames > 4 KiB | z9torr `main_B8D622A5.c:1138` (545,024 B), `scheduler_DC60A925.c:1122` (201,152 B), z9play `main_4D6BD2B8.c:1249` (10,048 B) | `__chkstk` (VC6 may spell it `_chkstk`) |

Vendor documentation:

- `_alldiv`: “Divides two **LONGLONG** integers. For example, to divide two
  int64 values the compiler might generate a call to \_alldiv Routine.”
  https://learn.microsoft.com/en-us/windows/win32/devnotes/-win32-alldiv
- `_aulldiv`: “Divides two **ULONGLONG** integers.”
  https://learn.microsoft.com/en-us/windows/win32/devnotes/-win32-aulldiv
- `_allmul`: “Multiplies two **LONGLONG** or **ULONGLONG** integers.”
  https://learn.microsoft.com/en-us/windows/win32/devnotes/-win32-allmul
- `__chkstk`: “For x86 compilers, \_\_chkstk Routine is called when the local
  variables exceed 4K bytes”. https://learn.microsoft.com/en-us/windows/win32/devnotes/-win32-__chkstk
- `_chkstk`: same rule, documented separately.
  https://learn.microsoft.com/en-us/windows/win32/devnotes/-win32-chkstk
- `_ftol`: “Suppresses the call of the helper function `_ftol` when a
  conversion from a floating-point type to an integral type is required.”
  https://learn.microsoft.com/en-us/cpp/build/reference/qifist-suppress-ftol?view=msvc-170
- `_filbuf`, `_flsbuf`, `_ftol`, `__chkstk`, `_chkstk`, `__iob_func` are listed
  as internal CRT functions:
  https://learn.microsoft.com/en-us/cpp/c-runtime-library/internal-crt-globals-and-functions?view=msvc-170

**Decision: select vendor static-lib objects.** Do not implement these in C.
Justification:

- `_alldvrm`/`_aulldvrm` (if emitted under optimization) return quotient in
  `EDX:EAX` and remainder in `ECX:EBX`; C cannot express that return ABI.
- `_ftol` must truncate according to the x87 control word; a C `(__int64)d`
  implementation recursively calls `_ftol`.
- `_chkstk` is a raw entry-point ABI routine (size in `EAX`), not a C call.
- `libcmt.lib` is the vendor's exact, matching toolset implementation. Linking
  only its helper members is safer than hand-rolling an ABI we cannot test.
- The resulting image is still a single EXE with no `msvcrt.dll` import.

`/Gs` is rejected: Microsoft says the default is `/Gs4096` and “We recommend that
you do not change the default value unless you know exactly why you have to
change it”; `/Gs0` “initiates stack probes for every function call that requires
storage for local variables.” Changing it to avoid `__chkstk` would silently
break stack growth on the 545 KiB z9torr frame. (Microsoft Learn, `/Gs`,
https://learn.microsoft.com/en-us/cpp/build/reference/gs-control-stack-checking-calls?view=msvc-170).

### 1.5 `/WX` + `/Za` interaction with shim headers

- `/Za` makes the compiler C89-strict and defines `__STDC__`; emitted C has no
  `//` line comments (the only grep matches are string literals containing
  `://` in the z9torr dump) and declarations are hoisted.
- `zig_compat.h` uses `__int64` (allowed under `/Za`; only `_int64` synonyms are
  disabled) and `Z98_ALIGN8` is empty on MSVC (`zig_compat.h:11-18`).
- The previously-probed shim design in T5.3a was compiled with `-std=c89 -Wall`
  and zero warnings (§11.1). MSVC `/W3 /WX` still must be verified on hardware:
  the native `zig_nocrt.c` adds `<stdio.h>`/`<windows.h>` and toolchain-specific
  `_iob` handling. The risk is warning C4100/C4244/C4013 in the shim, not the
  emitted modules. The shim must cast all Win32 handle/count types explicitly
  and `(void)` unused parameters/returns.
- Microsoft system headers under `/Za` are a real risk (they are not written to
  strict C89). The current `.bat` already compiles `zig_pal.c` with `/Za` and
  `<windows.h>`, so this is pre-existing, not new. If VC6 rejects a system
  header under `/Za`, the fallback is `/Ze` **only** for `zig_pal.c` and
  `zig_nocrt.c`; emitted modules stay `/Za`. This fallback must be recorded as
  hardware-verified before it is used. No such fallback is assumed by this
  design.

### 1.6 Static-CRT alternate (`build_target_crt.bat`)

Exact command:

```bat
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /MT /I .
cl %CFLAGS% <module>.c
...
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
link /subsystem:console,4.0 /STACK:2097152 ^
     <module>.obj ... zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj ^
     kernel32.lib winmm.lib [wsock32.lib] /out:%OUT%
```

- `/MT` “Use the multithread, static version of the runtime library. Defines
  `_MT`. The linker uses `LIBCMT.lib` to resolve runtime symbols.” (Microsoft
  Learn, `/MD, /MT, /LD`,
  https://learn.microsoft.com/en-us/cpp/build/reference/md-mt-ld-use-run-time-library?view=msvc-170).
- Microsoft's CRT-lib table says `libcmt.lib` “Statically links the native CRT
  startup into your code” and that with no runtime-library option the linker
  uses the statically linked CRT libraries (Microsoft Learn, *CRT library
  features*,
  https://learn.microsoft.com/en-us/cpp/c-runtime-library/crt-library-features?view=msvc-170).
- MSVC 6's historical `/ML` (single-threaded static CRT) and `/MT` are both
  static; the script chooses `/MT` explicitly because it is documented and
  remains available. `/MD` is the only option that imports `msvcrt.dll`; it is
  not used.
- No `/DZIG_NO_CRT`: the T5.3a C1 ruling remains in force — defining it while
  linking the CRT would collide with CRT `exit`/`atexit`/stdio definitions.
  `zig_nocrt.c` is compiled as an empty translation unit (dummy typedef).
- **Hardware-unverified.** The static CRT may import kernel32 functions outside
  the Win9x whitelist; it must still be run through
  `check_win9x_imports.sh` in 9x mode before being called 9x-safe.

---

## 2. OpenWatcom no-CRT design

### 2.1 `wcc386` command

Exact compile command (one invocation per `.c`; OpenWatcom accepts `/` options):

```bat
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. <module>.c
...
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_runtime.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_pal.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_nocrt.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. c_exit.c
```

- `/za` — disable language extensions; “disable/enable language extensions”
  (Open Watcom C/C++ Compiler Guide, `docs/doc/cg/cpopts.gml:405-409`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/cg/cpopts.gml).
- `/we` — “treat all warnings as errors” (`cpopts.gml:394-397`).
- `/bt=nt` — build target Windows NT/Windows 95; OpenWatcom documents
  “build target for operating system <os>” and the NT default for
  NT/Win95 hosts (`cpopts.gml:131-135`, `1415-1450`).
- `/zl` — “remove default library information” (`cpopts.gml:602-605`).
- `/sg` — “generate calls to grow the stack”; “It requests the code generator
  to emit a run-time call at the start of any function that has more than 4K
  bytes of automatic variables ... The stack-growing run-time routine is called
  `__GRO`” (`cpopts.gml:142-155`, `1669-1697`).
- `/i=.` — emitted-tree include root.
- No `-br`: OpenWatcom's `br` option “causes the compiler to emit into the
  object file references to the run-time DLL library name(s)”
  (`cpopts.gml:1377-1392`). Its absence is what keeps the default runtime
  static. The no-CRT script additionally passes `option nodefaultlibs` to the
  linker.

### 2.2 `wlink` command

Exact link command:

```bat
wlink system nt op q opt stack=1048576 ^
      option nodefaultlibs ^
      option start=_mainCRTStartup ^
      file <module>.obj,...,zig_runtime.obj,zig_pal.obj,zig_nocrt.obj,c_exit.obj ^
      library kernel32,clib3r,winmm[,wsock32] ^
      name %OUT%
```

- `system nt` — OpenWatcom's documented “32-bit x86 Windows NT Character-Mode
  Executable Files” system (`docs/doc/lg/tutmain.gml:621-629`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/lg/tutmain.gml).
  The current emitted `system console` is not the documented system name; T5.3
  must switch to `system nt`.
- `option nodefaultlibs` — “The NODEFAULTLIBS option instructs the linker to
  ignore default libraries. That is, only libraries appearing in a LIBRARY
  directive are searched.” (`docs/doc/lg/opnodefa.gml`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/lg/opnodefa.gml).
  This is the exact `option nodefaultlibs` requested by the plan.
- `option start=_mainCRTStartup` — “specifies the name of the procedure where
  execution begins” (`docs/doc/lg/opstart.gml`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/lg/opstart.gml).
  `mainCRTStartup` is declared `__cdecl`; OpenWatcom documents “All symbols are
  preceded by an underscore character” for `__cdecl`
  (`docs/doc/cg/cpwcc.gml:1505-1512`), hence the leading underscore.
- `option stack=1048576` — “The STACK option can be used to increase the size
  of the stack” (`docs/doc/lg/opstack.gml`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/lg/opstack.gml).
  The current 65536 cannot hold z9torr's 545 KiB frame. OpenWatcom's `COMMIT`
  documentation says the default committed stack is “the smaller of 64K or the
  size specified by the STACK option”
  (`docs/doc/lg/ldcommit.gml`), so 1 MiB reserve does not commit 1 MiB.
- `library kernel32,clib3r,winmm[,wsock32]` — `LIBRARY` is searched only for
  unresolved symbols after object processing
  (`docs/doc/lg/ldlibrar.gml`). `clib3r.lib` is the vendor static WinNT 386
  runtime library assembled from `cgsupp`, `intel`, `startup`, etc.
  (`bld/clib/library/winnt.386/libs.mif`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/bld/clib/library/winnt.386/libs.mif).
  It supplies the helper members in §2.4; only referenced members are pulled.
- `op q` keeps the existing quiet/optimized link behavior; `opt stack` is the
  OpenWatcom short form.

### 2.3 Startup / entry / stack

Same shared `mainCRTStartup` + `GetCommandLineA` parser as §1.3, but under
OpenWatcom the function is `__cdecl`, so its symbol is `_mainCRTStartup` and
`option start=_mainCRTStartup` matches. The startup calls
`exit(main(g_argc, g_argv))`.

`main` remains the default OpenWatcom 32-bit **register** calling convention.
Do not mark it `__cdecl`: the emitted `main` is compiled with the default
register convention, and OpenWatcom documents the default 32-bit method as
register argument passing with underscore-suffixed global function names
(`cpopts.gml:4770-4807`). The startup's prototype uses the default convention,
so the call matches.

Stack: `option stack=1048576` as above. This is a T5.3 correction to the old
`build_owc.bat` 64 KiB value; it is required for z9torr regardless of CRT mode.

### 2.4 64-bit/stack helper set and provision

OpenWatcom's 64-bit helpers are **register-based**, not C-callable:

| Helper | Vendor source evidence | ABI / use |
|:--|:--|:--|
| `__I8M`, `__U8M` | `bld/clib/cgsupp/a/i8m386.asm:46-72` (`xdefp __I8M`, `__U8M`) | inputs `EDX:EAX`, `ECX:EBX`; product `EDX:EAX` |
| `__I8D`, `__U8D` | `bld/clib/cgsupp/a/i8d.asm:35-221` | input `EDX:EAX`, `ECX:EBX`; quotient `EDX:EAX`, remainder `ECX:EBX` |
| `__I8LS`, `__U8LS` | `bld/clib/cgsupp/a/i8ls086.asm:61-62` (also `i8rs386.asm:115-116`) | 64-bit left shift |
| `__I8RS`, `__U8RS` | `bld/clib/cgsupp/a/i8rs386.asm:71-92` | signed/unsigned 64-bit right shift |
| `__FDI8`, `__FDU8` | `bld/clib/cgsupp/a/fdi8386.asm:39-69` | double -> signed/unsigned 64-bit integer |
| `__I8FD`, `__U8FD` | `bld/clib/cgsupp/a/i8fd386.asm:45-98` | signed/unsigned 64-bit integer -> double |
| `__GRO` | `bld/clib/startup/a/stkwnt.asm:52-122` | stack growth, called for >4K frames under `/sg` |
| `__STK`, `__CHK`, `__alloca_probe` | `bld/clib/startup/a/stkwnt.asm:52-135` | stack-check family supplied by the same WinNT startup member |

Vendor source URLs (official Open Watcom V2 repository):
`https://github.com/open-watcom/open-watcom-v2/blob/master/bld/clib/cgsupp/a/i8m386.asm`,
`.../i8d.asm`, `.../i8ls086.asm`, `.../i8rs386.asm`, `.../fdi8386.asm`,
`.../i8fd386.asm`, `.../bld/clib/startup/a/stkwnt.asm`.

**Decision: select vendor static-lib objects (`clib3r.lib`).** Do not implement
these in C. The arguments are in registers and the divide helpers return two
results in four registers; a C function cannot match this ABI. `clib3r.lib`
contains the `cgsupp` and `startup` members (vendor `libs.mif` above), including
`stkwnt.obj` for `__GRO`. With `option nodefaultlibs`, only these unresolved
helper members are extracted; our shims define the libc symbols, so no CRT
startup/stdio member is pulled. No runtime DLL import is created.

`/sg` is used (unlike the old script) because z9torr's emitted frames exceed
4 KiB. Without `/sg`, a 545 KiB frame could cross the Win9x guard page without
touching it in order. OpenWatcom's own docs describe exactly this guard-page
problem and name `__GRO` as the remedy (`cpopts.gml:1669-1697`).

### 2.5 Static-runtime alternate (`build_owc_crt.bat`)

Exact command:

```bat
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. <module>.c
...
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_runtime.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_pal.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_nocrt.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. c_exit.c
wlink system nt op q opt stack=1048576 ^
      file <module>.obj,...,zig_runtime.obj,zig_pal.obj,zig_nocrt.obj,c_exit.obj ^
      library kernel32,winmm[,wsock32] ^
      name %OUT%
```

- No `/dZIG_NO_CRT`, no `/zl`, no `option nodefaultlibs`: the default static
  runtime is linked. OpenWatcom's `br` option is the opt-in for DLL runtime
  references (`cpopts.gml:1377-1392`); it is absent. The WinNT build system's
  libraries are static `clib3r.lib` (vendor `libs.mif`), so the expected result
  is a single EXE with no runtime DLL.
- **Hardware-unverified.** The static runtime may use KERNEL32 imports beyond
  the Win9x whitelist. It must pass `check_win9x_imports.sh` 9x mode before being
  called 9x-safe.

---

## 3. Shared design

### 3.1 `zig_nocrt.c` ownership and the native stdio split

T5.3a assigns `__acrt_iob_func`/`fwrite`/`getchar`/`putchar` to a new
`sf/src/include/zig_nocrt.c`. T5.3b extends that design for native headers:

| Toolchain | `<stdio.h>` `stdout`/`stderr` expansion | Stream symbols the shim must provide |
|:--|:--|:--|
| mingw (pinned) | `__acrt_iob_func(1/2)` | `__acrt_iob_func` + `__imp____acrt_iob_func` asm pointer; no `_iob` |
| MSVC 6 | VC6 `stdio.h` macro/array form (`_iob`, historically `getc`/`putc`/`_filbuf`/`_flsbuf`) | `FILE _iob[3]`, `fwrite`, `getchar`, `putchar`, `getc`, `putc`, `fgetc`, `fputc`, `_filbuf`, `_flsbuf` |
| OpenWatcom | vendor `stdio.mh:287-295` defines `stdout` as `&__iob[1]`; `stdio.mh:543-544` defines `getchar()`/`putchar()` via `getc`/`putc`; `stdio.mh:521-538` maps those to `fgetc`/`fputc` (or direct fields) | `__w_FILE __iob[3]`, `fwrite`, `getchar`, `putchar`, `getc`, `putc`, `fgetc`, `fputc`, `_filbuf`, `_flsbuf` |

Evidence for OpenWatcom: `bld/hdr/watcom/stdio.mh` lines 287-295 and 521-544,
https://github.com/open-watcom/open-watcom-v2/blob/master/bld/hdr/watcom/stdio.mh.
This is vendor source, not a probe. Windows headers/CRT internals list
`_filbuf`, `_flsbuf`, `__iob_func`, `_ftol`, `__chkstk` as internal CRT entries
(Microsoft Learn, *Internal CRT Globals and Functions*,
https://learn.microsoft.com/en-us/cpp/c-runtime-library/internal-crt-globals-and-functions?view=msvc-170).

Design rules:

- `zig_nocrt.c` includes `<stdio.h>`/`<windows.h>` under
  `_WIN32 && ZIG_NO_CRT`.
- After the includes, `#undef getchar`, `#undef putchar`, `#undef getc`, and
  `#undef putc` (one directive each) before defining the functions; otherwise
  the native function-like macros rewrite the definitions.
- MSVC: define `FILE _iob[3];` (static CRT header declaration is not
  `dllimport` because `/MD`/`_DLL` is not used). OWC: define
  `__w_FILE __iob[3];` (the header's own type, so the macro address arithmetic
  is exact). Both arrays are zero-initialized; native `getc`/`putc` macros then
  fall back to `fgetc`/`fputc` (or `_filbuf`/`_flsbuf`) instead of dereferencing
  an uninitialized buffer.
- mingw: keep T5.3a's `static FILE g_iob[3]`, `__acrt_iob_func`, and the
  `.data` import-pointer asm. Do **not** define `_iob` on mingw.
- `fwrite` selects `STD_ERROR_HANDLE` when `stream == stderr` (the macro resolves
  to the same `_iob`/`__iob`/`__acrt_iob_func(2)` object in the same TU) and
  `STD_OUTPUT_HANDLE` otherwise. It uses `WriteConsoleA` first, `WriteFile`
  fallback, no buffering (T5.3a §3.2).
- `fgetc`/`getc`/`_filbuf`/`getchar` all read one byte from `STD_INPUT_HANDLE`
  via `ReadFile`; `fputc`/`putc`/`_flsbuf`/`putchar` write one byte to the
  selected output handle. Return conventions follow the C prototypes.
- Outside `_WIN32 && ZIG_NO_CRT`, the TU is a dummy typedef
  (`typedef int zig_nocrt_dummy;`) so MSVC `/W3 /WX` does not warn about an
  empty translation unit and OWC `/we` stays clean.
- The shim is single-threaded and unbuffered; documented in the Windows support
  doc.

This is the main T5.3b **scope addition** beyond T5.3a: T5.3a's shim set is
sufficient for mingw; native toolchains need the stream-macro layer above.

### 3.2 Header / prototype placement

Reuse T5.3a §1.2; the native additions need no new public header because the
stream functions are declared by each toolchain's own `<stdio.h>` and `_iob` is
declared there. The only new private declarations are:

- `zig_pal.c` no-CRT block: `int main(int argc, char** argv);`,
  `void exit(int);`, parser statics, `GetCommandLineA` (from `<windows.h>`).
- `zig_nocrt.c`: `_filbuf`/`_flsbuf` if the toolchain header does not declare
  them; definitions are compatible with the Microsoft CRT prototypes.
- No new prototype is added to `std_os_prelude.h`/`std_time_prelude.h` beyond
  T5.3a's `pal_*` additions.

### 3.3 Expected import tables per variant

Only OS DLLs; no `msvcrt.dll` in any no-CRT or static-CRT variant.

| Variant | hello | z9play | z9torr |
|:--|:--|:--|:--|
| mingw 9x no-CRT (`build_target.sh`) | KERNEL32 | KERNEL32 + WINMM | KERNEL32 + WSOCK32 |
| MSVC 6 no-CRT (`build_target_nocrt.bat`) | KERNEL32 | KERNEL32 + WINMM | KERNEL32 + WSOCK32 |
| OWC no-CRT (`build_owc_nocrt.bat`) | KERNEL32 | KERNEL32 + WINMM | KERNEL32 + WSOCK32 |
| MSVC 6 static CRT (`build_target_crt.bat`) | KERNEL32 | KERNEL32 + WINMM | KERNEL32 + WSOCK32 (subject to whitelist) |
| OWC static runtime (`build_owc_crt.bat`) | KERNEL32 | KERNEL32 + WINMM | KERNEL32 + WSOCK32 (subject to whitelist) |

The helper libraries are static; they do not add DLL names. The KERNEL32
function set for the mingw 9x artifacts is the T5.3a §10.2 whitelist; native
no-CRT artifacts must be checked with the same `check_win9x_imports.sh` and must
not import `GetFileAttributesExA`, `GetFileSizeEx`, or `SetFilePointerEx`
(T5.3a §10.2). Static-CRT alternates may pull additional KERNEL32 imports; they
are not claimed 9x-safe until the whitelist passes.

### 3.4 Exact script contents

Notation used below (the emitter substitutes these; they are the only
program-specific parts):

- `@MODC@` = one `cl %CFLAGS% <module>.c` line per reachable module.
- `@MODOBJ@` = space-separated `<module>.obj` list.
- `@MODOWC@` = one `wcc386 <flags> <module>.c` line per reachable module.
- `@MODOWCOBJ@` = comma-separated `<module>.obj` list.
- `@WSOCK_DEP@` = `wsock32.lib` (MSVC) only when `net_emitted`.
- `@WSOCK_LIB@` = `,wsock32` (OpenWatcom) only when `net_emitted`.

#### `build_target_nocrt.bat`

```bat
@echo off
REM build_target_nocrt.bat - generated by zig1 (MSVC cl, Win9x no-CRT DEFAULT)
REM REDISTRIBUTION: single EXE, no msvcrt.dll dependency. Imports only
REM KERNEL32 (+WINMM/WSOCK32 when used), which are OS DLLs on Win95+.
REM Status: design-verified; hardware verification pending.
REM usage: build_target_nocrt.bat [OUT]
REM WARNING POLICY: CFLAGS below includes /WX (all warnings are errors).
REM If a warning you believe is harmless appears, remove /WX to see it; hard
REM errors still mean the emitted C is invalid for MSVC: report it.
setlocal
if "%~1"=="" (set OUT=prog.exe) else (set OUT=%~1)
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_NO_CRT /Zl /I .
echo Compiling...
@MODC@
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
echo Linking...
link /NODEFAULTLIB /subsystem:console,4.0 /STACK:2097152 /entry:_mainCRTStartup@0 ^
     @MODOBJ@ zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj ^
     kernel32.lib winmm.lib @WSOCK_DEP@ libcmt.lib /out:%OUT%
echo Built: %OUT%
```

#### `build_target_crt.bat`

```bat
@echo off
REM build_target_crt.bat - generated by zig1 (MSVC cl, static-CRT ALTERNATE)
REM REDISTRIBUTION: single EXE, no DLL dependency (static /MT CRT).
REM Imports only KERNEL32 (+WINMM/WSOCK32 when used); no msvcrt.dll.
REM Status: design-verified; hardware verification pending.
REM usage: build_target_crt.bat [OUT]
setlocal
if "%~1"=="" (set OUT=prog.exe) else (set OUT=%~1)
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /MT /I .
echo Compiling...
@MODC@
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
echo Linking...
link /subsystem:console,4.0 /STACK:2097152 ^
     @MODOBJ@ zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj ^
     kernel32.lib winmm.lib @WSOCK_DEP@ /out:%OUT%
echo Built: %OUT%
```

#### `build_owc_nocrt.bat`

```bat
@echo off
REM build_owc_nocrt.bat - generated by zig1 (OpenWatcom, Win9x no-CRT DEFAULT)
REM REDISTRIBUTION: single EXE, no msvcrt.dll (or other runtime DLL)
REM dependency. Imports only KERNEL32 (+WINMM/WSOCK32 when used).
REM Status: design-verified; hardware verification pending.
REM usage: build_owc_nocrt.bat [OUT]
REM WARNING POLICY: /we makes every warning an error. Remove /we only to see
REM a warning; hard errors mean the emitted C is invalid for OpenWatcom.
setlocal
if "%~1"=="" (set OUT=prog.exe) else (set OUT=%~1)
echo Compiling...
@MODOWC@
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_runtime.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_pal.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_nocrt.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. c_exit.c
echo Linking...
wlink system nt op q opt stack=1048576 option nodefaultlibs ^
      option start=_mainCRTStartup ^
      file @MODOWCOBJ@,zig_runtime.obj,zig_pal.obj,zig_nocrt.obj,c_exit.obj ^
      library kernel32,clib3r,winmm@WSOCK_LIB@ ^
      name %OUT%
echo Built: %OUT%
```

#### `build_owc_crt.bat`

```bat
@echo off
REM build_owc_crt.bat - generated by zig1 (OpenWatcom, static-runtime ALTERNATE)
REM REDISTRIBUTION: single EXE, no runtime DLL dependency (static clib).
REM Imports only KERNEL32 (+WINMM/WSOCK32 when used).
REM Status: design-verified; hardware verification pending.
REM usage: build_owc_crt.bat [OUT]
setlocal
if "%~1"=="" (set OUT=prog.exe) else (set OUT=%~1)
echo Compiling...
@MODOWC@
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_runtime.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_pal.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. zig_nocrt.c
wcc386 /za /we /dZIG_WIN32 /bt=nt /sg /i=. c_exit.c
echo Linking...
wlink system nt op q opt stack=1048576 ^
      file @MODOWCOBJ@,zig_runtime.obj,zig_pal.obj,zig_nocrt.obj,c_exit.obj ^
      library kernel32,winmm@WSOCK_LIB@ ^
      name %OUT%
echo Built: %OUT%
```

#### `build_target.sh` header/comment update

Only the header/profile comment changes; the mingw branch already becomes the
T5.3a no-CRT recipe. Exact replacement header and branch:

```sh
#!/bin/sh
chmod +x "$0" 2>/dev/null || true
# build_target.sh - generated by zig1
# usage: sh build_target.sh [TARGET] [OUT]
#   TARGET: linux (default) or mingw
#   OUT:    output binary (default: prog on linux, prog.exe on mingw)
# REDISTRIBUTION: on mingw this is the Win9x DEFAULT no-CRT build: a single EXE
#   importing only KERNEL32 (+WINMM/WSOCK32 when used), no msvcrt.dll.
#   A CRT-linked NT build is emitted by the compiler's `-osw nt` profile (this
#   script then carries -DZIG_WIN_NT and does not use -nostdlib).
# Status: design-verified; hardware verification pending.
# WARNING POLICY: this script does NOT enable warnings-as-errors (no -Werror here),
# so compiler warnings are non-fatal and the build still produces the binary.
# If the build stops with a hard error, the emitted C is invalid for this toolchain:
# please report it as a bug (include the failing compiler output above).
# If you add -Werror yourself, drop it to see the warning without failing.
```

9x mingw branch (exact):

```sh
  mingw)
    CC=i686-w64-mingw32-gcc
    CFLAGS="-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -DZIG_NO_CRT -I ."
    LDFLAGS="-m32 -nostdlib -Wl,-e,_mainCRTStartup"
    LIBS="-lgcc -lkernel32 -lwinmm"
    # append -lwsock32 iff net_emitted
    [ -n "$OUT" ] || OUT=prog.exe
    ;;
```

nt mingw branch (exact):

```sh
  mingw)
    CC=i686-w64-mingw32-gcc
    CFLAGS="-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -DZIG_WIN_NT -I ."
    LDFLAGS="-m32"
    LIBS="-lwinmm"
    # append -lwsock32 iff net_emitted
    [ -n "$OUT" ] || OUT=prog.exe
    ;;
```

Both branches also compile and link `zig_nocrt.c`/`zig_nocrt.o` in the support
object set, in the same fixpoint order as the T5.3a §8.1 recipe.

### 3.5 Old-name disposition

**Keep as profile-correct aliases; do not remove.**

`build_target.bat` (9x dump):

```bat
@echo off
REM Compatibility alias. 9x default is build_target_nocrt.bat (no-CRT).
call "%~dp0build_target_nocrt.bat" %*
```

`build_target.bat` (nt dump): same alias to `build_target_crt.bat`.
`build_owc.bat` (9x): alias to `build_owc_nocrt.bat`.
`build_owc.bat` (nt): alias to `build_owc_crt.bat`.

Why aliases, not removal:

- The manuals and design docs reference the old names extensively:
  `docs/design/C89_Codegen.md:604`, `docs/design/CompilationPipeline.md:83`,
  `docs/design/DESIGN.md:1111,1150`,
  `docs/reference/compilation_model.md:22`, and the generated manual HTML
  (`docs/sf/manuals/en/vol3-08-win9x.html`,
  `vol5-04-target-win9x.html`, `vol5-19-pack-for-diskette.html`).
  Removing them would leave dangling references.
- Aliasing old names to the profile's default keeps the documented "Win9x
  build" path no-CRT, matching the operator goal. The `_crt` scripts remain the
  explicit alternates.
- The manual snapshots quote the pre-T5.3 script bodies. They are stale text,
  not dangling names. T5.3's Windows support doc must say the manual snapshots
  show the pre-T5.3 recipe; updating the manuals is optional follow-up unless
  the operator requires a manual truth-up in this milestone.

---

## 4. Verification strategy (Amendment 5)

### 4.1 Host capability and prohibited actions

Observed: `i686-w64-mingw32-gcc` 12-win32 and `wine` 8.0 are installed; `cl`,
`wcc386`, and `wlink` are not. Per Amendment 5:

- No OpenWatcom download/install.
- No MSVC/OWC compile/link under Wine.
- No native-toolchain runtime probes.
- No claim of native runtime verification; every native claim is
  **design-verified; hardware verification pending**.

### 4.2 Evidence actually used

| Claim class | Evidence |
|:--|:--|
| Emitted-C operation sites | `/tmp/m6/zig1_5_clean` md5 above; dumps into `/tmp/t53b_dump/{z9play,z9torr,hello,z9play_nt}` (fresh, pre-created output dirs); `grep`/`sed` line evidence in this report. |
| Stack frame sizes | `i686-w64-mingw32-gcc -m32 -std=c89 -O0 -DZIG_NO_CRT -fstack-usage` on every emitted `.c` in `/tmp/t53b_su` (z9play) and `/tmp/t53b_su_torr` (z9torr). No link, no run. This is a host cross-compiler static analysis, not a native-toolchain probe. |
| MSVC flags/helpers | Microsoft Learn pages quoted in §1 (URLs inline), plus the MSVC internal-CRT list. |
| OWC flags/helpers | Official Open Watcom V2 docs (`docs/doc/cg/cpopts.gml`, `docs/doc/lg/*.gml`) and official V2 source (`bld/clib/cgsupp/a/*.asm`, `bld/clib/startup/a/stkwnt.asm`, `bld/hdr/watcom/stdio.mh`, `bld/clib/library/winnt.386/libs.mif`) quoted in §2-§3. |
| Import-table expectations | T5.1 §1.3/§1.4, T5.3a §10.2, and the static-link/helper reasoning above; no native PE was produced. |

No emitted `.exe` was run by T5.3b. The T5.3a Wine probes are context only; they
do not verify MSVC/OWC.

### 4.3 What remains unverified (explicit)

1. MSVC 6 actually accepts `/Za` on `zig_pal.c`/`zig_nocrt.c` including
   `<windows.h>`/`<stdio.h>`; and `/W3 /WX` is clean.
2. Exact VC6 `<stdio.h>` macro expansion (`_iob` vs `__iob_func`, and whether
   `getc`/`putc` route through `_filbuf`/`_flsbuf`). The shim provides the
   superset in §3.1; hardware compile will tell which members are referenced.
3. Exact VC6 helper symbol spellings (`__chkstk` vs `_chkstk`,
   `_alldvrm`/`_aulldvrm` emission). Linking `libcmt.lib` lets the linker resolve
   whatever VC6 emits; no symbol is hand-coded.
4. `link /entry:_mainCRTStartup@0` acceptance. The decoration follows Microsoft's
   documented `__stdcall` rule; if VC6's linker expects the undecorated spelling,
   the fallback is `/entry:_mainCRTStartup` with a `__cdecl` startup (same
   never-returning function). This is a hardware-verification item, not a
   design fork.
5. OpenWatcom `/sg` actually emits `__GRO` calls for the large frames and
   `clib3r.lib` resolves them; `system nt` + `option start=_mainCRTStartup`
   resolves the `__cdecl` symbol.
6. Native import tables are KERNEL32 (+WINMM/WSOCK32) only. No native PE was
   produced; `objdump -p`/`dumpbin /imports` verification is operator-owned.
7. Win98/Me load/run, console behavior, audio, and network behavior. Hardware
   verification remains operator-owned and deferred until after the z9play
   milestone (Amendment 5).

---

## 5. File:line inventory of every T5.3 edit

Current line numbers are anchors; T5.3 will shift them.

### 5.1 Z98 sources

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/std_file.zig:94-104` | Remove Windows-only mtime/FILETIME constants; keep POSIX constants. |
| `sf/src/std_file.zig:223-234` | `seekHandle` Windows → `pal.pal_file_seek64`. |
| `sf/src/std_file.zig:236-245` | `sizeHandle` Windows → `pal.pal_file_size`. |
| `sf/src/std_file.zig:311-331` | `mtime` Windows → `pal.pal_file_mtime`; POSIX unchanged. |
| `sf/src/std_file_pal.zig:24-28` | Replace `SetFilePointerEx`/`GetFileSizeEx` stdcall externs with cdecl `pal_file_*`. |
| `sf/src/std_file_pal.zig:34-39` | Replace `GetFileAttributesExA` with cdecl `pal_file_mtime`. |
| `sf/src/std_os.zig:66-81` | Windows branch → `pal.pal_getenv`; POSIX unchanged. |
| `sf/src/std_os_pal.zig:23-24` | Keep POSIX `getenv`; add `pal_getenv` extern. |
| `sf/src/std_time.zig:115-118` | Windows branch → `pal.pal_wallclock_unix`; POSIX unchanged. |
| `sf/src/std_time_pal.zig:50-51` | Keep POSIX `time`; add `pal_wallclock_unix` extern. |

### 5.2 Emitted support canonical files

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/include/zig_pal.c:240-295` | Add `pal_file_size`/`pal_file_seek64`/`pal_file_mtime` after `pal_file_close`; `#ifdef ZIG_WIN_NT` modern vs default Win95. |
| `sf/src/include/zig_pal.c:297-346` | Add `pal_getenv` (static 32768 buffer) and `pal_wallclock_unix`. |
| `sf/src/include/zig_pal.c:349-355` | Replace stub with `__stdcall`/`__cdecl` conditional `mainCRTStartup`, `__main`, `GetCommandLineA` parser, `exit(main(argc, argv))`; add `<stdlib.h>` under no-CRT. |
| `sf/src/include/zig_runtime.c:1-24,186` | Append no-CRT `strlen`/`memcpy`/`strncmp` after line 186. |
| `sf/src/c_exit.c:1-2` | Replace with guarded `atexit` registry + `exit`→`ExitProcess`; `c_exit` calls `exit`. |
| `sf/src/include/std_os_prelude.h:8-14` | Add `_WIN32` prototypes for `pal_file_*`/`pal_getenv`. |
| `sf/src/include/std_time_prelude.h:10-27` | Add `_WIN32` prototype for `pal_wallclock_unix`. |
| **new** `sf/src/include/zig_nocrt.c` | New canonical shim: mingw `__acrt_iob_func` + import pointer; MSVC `FILE _iob[3]`; OWC `__w_FILE __iob[3]`; `fwrite`/`getchar`/`putchar`/`getc`/`putc`/`fgetc`/`fputc`/`_filbuf`/`_flsbuf`; `getenv`/`_time32`/`time` wrappers; dummy typedef off no-CRT. |

### 5.3 Emitter / build scripts / gates / docs

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/emit_support.zig:114-129` | Mirror `std_os_prelude.h` prototypes. |
| `sf/src/emit_support.zig:131-192` | Mirror `std_time_prelude.h` prototype. |
| `sf/src/emit_support.zig:194-197` | Mirror new `c_exit.c` block. |
| `sf/src/emit_support.zig` insert after 197 | New `emitZigNocrtCSupport` literal for `zig_nocrt.c` (§3.1). |
| `sf/src/emit_support.zig:488-677` | Mirror `zig_runtime.c` string shims. |
| `sf/src/emit_support.zig:679-1037` | Mirror all `zig_pal.c` additions; replace `mainCRTStartup` literal at `1029-1036`. |
| `sf/src/c89_emit.zig:789-854` | `emitSupportFiles` writes `zig_nocrt.c` (new fd/writer block). |
| `sf/src/c89_emit.zig:8537-8574` | `emitBuildTargetSh`: 9x no-CRT CFLAGS/LDFLAGS/LIBS + `zig_nocrt`; nt `-DZIG_WIN_NT`; winmm/wsock32; header update (§3.4). |
| `sf/src/c89_emit.zig:8576-8603` | Replace `emitBuildTargetBat` with `emitBuildTargetNocrtBat` + `emitBuildTargetCrtBat` + alias writer (§3.4, §3.5). |
| `sf/src/c89_emit.zig:8605-8654` | Replace `emitBuildOwcBat` with `emitBuildOwcNocrtBat` + `emitBuildOwcCrtBat` + alias writer; `system nt`, `option nodefaultlibs`, `option start`, `option stack`. |
| `sf/src/c89_emit.zig:8656-8675` | `emitBuildScripts`: emit the four scripts + two aliases for `-osw`; keep `build_target.sh`. |
| `scripts/check_emit_support.sh:55-59` | Add `check zig_nocrt.c "$ROOT/sf/src/include/zig_nocrt.c"`. |
| `scripts/check_emit_support.sh:135` | Update count to `8/8` (6 core + 2 conditional preludes). |
| **new** `scripts/win32_cross/check_win9x_imports.sh` | Whitelist gate (§T5.3a §10); native artifacts included. |
| `scripts/win32_cross/cross_nocrt.sh:125-156` | Include `c_exit.o` and emitted `zig_nocrt` shims; stop duplicating scratch definitions. |
| `scripts/win32_cross/cross_nocrt.sh:164-174` | Link `c_exit.o`; no scratch shim duplication. |
| **new** `sf/docs/tech_docs/13_windows_support.md` | Profile × toolchain × CRT matrix, `_iob` per-toolchain rationale, env lifetime, redistribution policy, "design-verified; hardware verification pending". |
| `sf/docs/tech_docs/INDEX.md:1680` (after `12_async_coroutines.md` row) | Add `13_windows_support.md` row. |
| `docs/design/C89_Codegen.md:604` | Truth-up old script description (or rely on alias; see §3.5). |
| `docs/design/CompilationPipeline.md:83` | Truth-up generated script list. |
| `docs/design/DESIGN.md:1111,1150` | Truth-up script description. |
| `docs/reference/compilation_model.md:22` | Truth-up script description. |
| Manual HTML snapshots (`docs/sf/manuals/en/vol3-08-win9x.html`, `vol5-04-target-win9x.html`, `vol5-19-pack-for-diskette.html`) | Stale quoted bodies; optional truth-up, not required for name validity because aliases remain. |

**Intentionally unchanged:** `sf/src/c89_emit.zig:5849` (`fwrite` emission),
`:7701` (`putchar`), `:7717-7723` (`getchar`), `:7726-7733` (`exit`); the shims
satisfy those symbols. `sf/src/std_os.zig:61-63` (`@exit`) is unchanged.
`examples/z98/z9play/platform/console_win9x.zig:144-146` and
`console_win9x_pal.zig:112` are unchanged; the no-CRT `atexit` satisfies them.
`sf/src/include/zig_pal.c:126-133` (`pal_abort`) is already Win9x-safe.

---

## 6. Risk list

| # | Risk | Impact | Mitigation / status |
|:--|:--|:--|:--|
| 1 | Native toolchains not installed; no native compile/link/run | scripts/helpers unproven on MSVC/OWC | Amendment 5; report marks every native claim design-verified/hardware-pending. |
| 2 | `libcmt.lib`/`clib3r.lib` explicit link may pull an unexpected CRT/libc member | duplicate symbols or extra imports | `option nodefaultlibs`/`/NODEFAULTLIB`; shims define all libc names; operator reviews link map + import table before hardware sign-off. |
| 3 | VC6 `<stdio.h>` macro expansion differs from the assumed `_iob`/`_filbuf`/`_flsbuf` form | unresolved `_iob`/`_filbuf`/`_flsbuf` or bad stderr routing | shim provides the superset (`_iob`, `__iob`, `getc`, `putc`, `fgetc`, `fputc`, `getchar`, `putchar`, `_filbuf`, `_flsbuf`); hardware compile confirms. |
| 4 | `__iob`/`_iob` array type/size mismatch | wrong `stderr` identity, out-of-bounds macro access | define with the toolchain header's own `FILE`/`__w_FILE` type and `[3]`, zero-initialized; macros fall back to functions. |
| 5 | `/Za` rejects a VC6 system header | no-CRT/crt MSVC build fails | pre-existing risk; fallback `/Ze` for `zig_pal.c`/`zig_nocrt.c` only, hardware-verified before use. |
| 6 | `/W3 /WX` or OWC `/we` warning in shim | build fails | T5.3a shim was `-Wall` clean; native additions cast all Win32/stdio types and `(void)` unused values; hardware compile pending. |
| 7 | z9torr 545 KiB frame exceeds stack | Win9x stack overflow | MSVC `/STACK:2097152`; OWC `option stack=1048576`; `/sg` + `__GRO`; hardware verification pending. |
| 8 | OWC `system console` in old script is not the documented system name | link failure | T5.3 switches to `system nt`; old name alias points to the new script. |
| 9 | MSVC `/entry` decoration mismatch | LNK1561/LNK2001 | `__stdcall` + `/entry:_mainCRTStartup@0` follows Microsoft decoration docs; fallback documented in §4.3. |
| 10 | Static-CRT alternates import non-9x KERNEL32 APIs | not loadable on Win98/Me | not claimed 9x-safe until `check_win9x_imports.sh` passes; new Windows doc states this. |
| 11 | `fwrite` unbuffered / stderr routing | different from CRT buffering; wrong stream | T5.3a §3.2 unbuffered design; native `stream == stderr` test; documented. |
| 12 | `_iob` omission ruling misread as global | native link misses `_iob` | §3.1 scopes the ruling to mingw; Windows support doc makes the per-toolchain table visible. |
| 13 | Old manual script snapshots stale | operator confusion | old names remain aliases; new Windows doc states snapshots are pre-T5.3; manual truth-up optional. |
| 14 | `libcmt.lib`/`clib3r.lib` are static CRT/runtime code, not literally "no CRT" | review objection | they are vendor *compiler helper* objects; no runtime DLL/startup/stdio is pulled; import table is the acceptance test. Static-CRT alternates are separate. |
| 15 | MSVC 6 `/MT` static CRT uses `_MT`; emitted code assumptions | behavioral difference vs `/ML` | emitted code is single-threaded and does not use CRT state; `/MT` chosen for documentation/determinism; hardware pending. |
| 16 | OpenWatcom `/za` + `long long` in `zig_compat.h:20-22` | pre-existing risk; `/za` could reject the extension | same combination is already in the old `.owc`; if rejected, use the documented `/ze` (extensions enabled) for the support TUs only, or keep `/za` and verify on hardware. |

---

## 7. Concerns / not-locally-determinable (no invention)

### 7.1 Native stdio macro layer is a T5.3a scope gap (resolved by design)

"I found the intention is that T5.3a's `_iob`-omission ruling covers all
 toolchains, but this is impossible given that the native MSVC 6/OpenWatcom
 `<stdio.h>` headers macro-expand `stdout`/`stderr`/`getchar`/`putchar` onto
 `_iob`/`__iob` and `getc`/`putc` (and likely `_filbuf`/`_flsbuf`)." The ruling's
own wording is scoped to “the pinned toolchain” (mingw), and T5.3b resolves the
native case by defining the native stream array/functions in `zig_nocrt.c` while
keeping the mingw `__acrt_iob_func` path. This is an addition, not a STOP.

### 7.2 Exact VC6 header expansion / helper spelling is not locally observable

Without VC6 (`cl` absent; Amendment 5 forbids obtaining it), the exact
`stdio.h` macro bodies and the exact helper spelling (`__chkstk` vs `_chkstk`,
`_alldvrm` vs separate `_alldiv`/`_allrem`) cannot be observed. This is stated
explicitly rather than invented. The design is safe because:

- the shim provides every candidate stream symbol;
- the linker, not this report, selects the vendor helper objects;
- the import-table gate and hardware build are the acceptance tests.

### 7.3 Static-CRT alternates are not 9x-verified

They are single-EXE/no-DLL by construction, but their KERNEL32 imports may exceed
the Win9x whitelist. They must pass the same gate before being called 9x-safe.
This is a concern, not a blocker: the operator's 9x **default** is the no-CRT
script.

### 7.4 Old-name aliases preserve names but not manual text

The old names remain valid, so no doc reference dangles. The manual HTML pages
quote pre-T5.3 script text; they are historically stale. T5.3's new
`13_windows_support.md` is the truth-up; editing every manual snapshot is
optional unless the operator requires it in this milestone.

---

## 8. Reproducibility summary

All analysis artifacts are under `/tmp`:

- `/tmp/t53b_dump/{z9play,z9torr,hello,z9play_nt}` — `/tmp/m6/zig1_5_clean`
  dumps (fresh output dirs). No repo source was modified.
- `/tmp/t53b_su`, `/tmp/t53b_su_torr` — host `-fstack-usage` compilations of
  every emitted `.c` for frame-size evidence. No link, no run.
- `/tmp/t53b_su_err_*` — per-TU stderr from those compilations (only used to
  confirm compile success).

No `cl`, `wcc386`, `wlink`, OpenWatcom install, Wine native-toolchain run, or
download was performed. No repo source file was modified by this task; the only
repository file created is this report.
