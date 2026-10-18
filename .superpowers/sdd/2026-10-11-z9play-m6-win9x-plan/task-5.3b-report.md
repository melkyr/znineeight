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

---

## Fix round 1 (2026-10-18)

This section is appended per the review ruling. It supersedes the corresponding
claims above where explicitly noted. Still report-only: zero source edits, no
downloads/installs, no native-toolchain probes. All new claims remain
**design-verified; hardware verification pending** unless they are pure
file:line/vendor-document observations.

### R1-C1 — MSVC 6 `/Za` cannot compile the emitted C: portable 64-bit spelling layer

**Finding (critical; accepted).** The first report's `/Za` claim was incomplete:
it checked only `zig_compat.h`'s `__int64` mapping and missed that the rest of
the emitted C spells 64-bit types and constants with `long long` / `LL` / `ULL`.
Observed counts in the `/tmp/m6/zig1_5_clean` dumps:

- z9play: **1,553** lines containing `long long`/`unsigned long long`;
  z9torr: **2,289**; z9play: **58** lines with a `ULL`/`LL` literal suffix.
- `sf/src/emit_support.zig`: **87** lines; `sf/src/c89_emit.zig`: **20** lines.
- The emitted carrier typedefs are centralized in
  `zig_special_types.h:98,102` (`typedef long long zT_..._i64` /
  `typedef unsigned long long zT_..._u64`), and direct casts/literals appear in
  generated modules, e.g.
  `vorbis_info_B6B89893.c:57` (`(unsigned long long)`),
  `std_math_80387A0C.c:724,921,1041` (`4503599627370495ULL`,
  `18446744073709551615ULL`, ...), and
  `decode_512E9AC7.c:136,3178`.

`long long` is not a VC6 C type; VC6 supports `__int64`/`unsigned __int64`
(Microsoft Learn, `__int64`,
https://learn.microsoft.com/en-us/cpp/cpp/int8-int16-int32-int64?view=msvc-170).
The project's own MSVC-first literal convention is `i64`/`ui64`
(`docs/reference/c89_emission.md:45`; `docs/design/Bootstrap_type_system_and_semantics.md:856-860`).
Therefore the first report's `/Za` design is **not implementable as written**.
This is fixed by a spelling layer, not by dropping MSVC 6.

**Decision: portable spelling layer; keep MSVC 6 supported. No STOP.**

#### R1-C1.1 `zig_compat.h` (canonical and `emit_support.zig` mirror)

Add literal macros next to the existing `z64`/`zu64` typedefs and make OWC use
the same 64-bit base type as MSVC:

```c
#ifdef _MSC_VER
    typedef __int64 z64 Z98_ALIGN8;
    typedef unsigned __int64 zu64 Z98_ALIGN8;
    #define Z98_I64_C(n) n##i64
    #define Z98_U64_C(n) n##ui64
#elif defined(__WATCOMC__)
    typedef __int64 z64 Z98_ALIGN8;
    typedef unsigned __int64 zu64 Z98_ALIGN8;
    #define Z98_I64_C(n) n##i64
    #define Z98_U64_C(n) n##ui64
#else
    typedef long long z64 Z98_ALIGN8;
    typedef unsigned long long zu64 Z98_ALIGN8;
    #define Z98_I64_C(n) n##LL
    #define Z98_U64_C(n) n##ULL
#endif

#define Z98_I64_MAX Z98_I64_C(9223372036854775807)
#define Z98_I64_MIN (-Z98_I64_MAX - Z98_I64_C(1))
#define Z98_U64_MAX (~Z98_U64_C(0))
```

OpenWatcom documents `__int64`, `i64`, and `ui64` as supported
(`docs/doc/cg/cpwcc.gml:2062-2120`,
https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/cg/cpwcc.gml);
MSVC 6's `__int64` is vendor-documented above. The `i64`/`ui64` suffix on VC6 is
the project's documented MSVC-first convention and is hardware-pending here; if
VC6 `/Za` rejects the suffix, the fallback is the hi/lo constructor form in
R1-C1.5 (no STOP).

**Also fix the OWC fixed-width typedef gap.** `zig_compat.h:29` currently says
`#if !defined(__cplusplus) && !defined(__WATCOMC__)`, so OpenWatcom never gets
`i8`/`i16`/`i32`/`i64`/`u8`/`u16`/`u32`/`u64`/`usize`. OpenWatcom's vendor docs
list `__int8`/`__int16`/`__int32`/`__int64`, not `i64`/`u64` type names
(`cpwcc.gml:2027-2085`), so those generated identifiers are otherwise undefined
under OWC. T5.3 must remove the `!defined(__WATCOMC__)` exclusion (or add an OWC
arm with `typedef z64 i64; typedef zu64 u64;` etc.):

```c
#if !defined(__cplusplus)
    typedef signed char i8;
    typedef short i16;
    typedef int i32;
    typedef z64 i64;
    /* ... u8/u16/u32/zu64/u64/usize unchanged ... */
#endif
```

This is required for **every** emitted TU, not just `zig_compat.h` users, because
`i64`/`u64` appear in generated module signatures, `zig_pal.c`, and
`std_*_prelude.h`.

#### R1-C1.2 `zig_runtime.h` / `zig_runtime.c` and their `emit_support.zig` literals

Mechanical, exhaustive replacements in the canonical files and the literal:

- `long long` → `z64`; `unsigned long long` → `zu64`.
- `ULL`/`LL` suffixes → macro-wrapped constants:
  `1ULL` → `Z98_U64_C(1)`, `63ULL` → `Z98_U64_C(63)`,
  `~0ULL` → `Z98_U64_MAX`,
  `9223372036854775807LL` → `Z98_I64_MAX`,
  `-9223372036854775807LL - 1LL` → `Z98_I64_MIN`.
- `9223372036854775807ULL` in `std_checked_cast_i64`
  (`zig_runtime.c:39-41`; `emit_support.zig:556-558`) → `Z98_I64_MAX`.

Affected anchors (current canonical / literal):

| File:line (current) | Change |
|:--|:--|
| `sf/src/include/zig_compat.h:18-41` | New `z64`/`zu64` branches + literal macros + OWC typedef arm (R1-C1.1). |
| `sf/src/emit_support.zig:17-77` | Mirror of the same `zig_compat.h` changes. |
| `sf/src/include/zig_runtime.h:9-10` | `pal_i64_to_str`/`pal_u64_to_str` prototypes → `z64`/`zu64`. |
| `sf/src/include/zig_runtime.h:21-130` | All `long long`/`unsigned long long`, `ULL`/`LL`, `~0ULL`, `Z98_I64_MIN` sites → `z64`/`zu64`/macros. |
| `sf/src/include/zig_runtime.h:147-164` | Public `std_print_*`/`std_checked_cast_*` prototypes → `z64`/`zu64`. |
| `sf/src/include/zig_runtime.h:258-278` | `zig_cast_checked_s/u` → `z64`/`zu64`. |
| `sf/src/emit_support.zig:199-486` | Mirror of all the above `zig_runtime.h` changes. |
| `sf/src/include/zig_runtime.c:6-12` | PAL prototypes → `z64`/`zu64`. |
| `sf/src/include/zig_runtime.c:38-68` | `std_checked_cast_i8..u64` definitions → `z64`/`zu64`; `9223372036854775807ULL` → `Z98_I64_MAX`; `return (long long)val` → `(z64)val`. |
| `sf/src/emit_support.zig:488-677` | Mirror of all the above `zig_runtime.c` changes. |
| `sf/src/include/zig_pal.c:66-235` | Already uses `i64`/`u64`; no `long long`. It becomes compilable under the OWC typedef arm (R1-C1.1). |
| `sf/src/include/zig_nocrt.c` (new) | Add `#include "zig_compat.h"`; the T5.3a local `extern long long pal_wallclock_unix(void);` becomes `extern z64 pal_wallclock_unix(void);`. |

#### R1-C1.3 `c89_emit.zig` — type and literal spelling sites

The emitter must never write `long long`, `unsigned long long`, `LL`, or `ULL`
again. Exact current sites:

| `sf/src/c89_emit.zig` line | Current spelling | Required spelling |
|:--|:--|:--|
| `1701` | `typedef long long ` (i64 carrier) | `typedef z64 ` |
| `1708` | `typedef unsigned long long ` (u64 carrier) | `typedef zu64 ` |
| `3852`, `3863` | `intLitSuffixNeg`/`intLitSuffixUns` appended to digits | `Z98_I64_C(<digits>)` / `Z98_U64_C(<digits>)` wrappers |
| `3971-3980` | suffix functions return `"ULL"` / `"LL"` | replaced by `writeU64Const` / `writeI64Const` wrapper emitters (or return prefix/suffix pair) |
| `4057`, `4076`, `4095`, `4188`, `4203` | suffix appended by saturation/mask writers | wrappers; buffer sizes increased (e.g. `[40]u8`) |
| `4306-4336` | `(long long)`, `(unsigned long long)`, `0ull` in checked-op strings | `z64`, `zu64`, `Z98_U64_C(0)` |
| `4989` | `static const unsigned long long ` | `static const zu64 ` |
| `4994` | appended `"ULL"` in enum value table | `Z98_U64_C(<digits>)` |
| `5024` | `unsigned long long x = (unsigned long long)v;` | `zu64 x = (zu64)v;` |
| `5331` | `((unsigned long long)(unsigned int)(` | `((zu64)(unsigned int)(` |
| `5379-5381` | `union { double f; unsigned long long u; }`, `unsigned long long zT_bits/zT_man` | `zu64` |
| `6227`, `6230`, `6246`, `6275`, `6279` | `emitCastToC(..., "long long"/"unsigned long long", ...)` | `"z64"`/`"zu64"` |
| `7540` | `"(unsigned long long)"` | `"(zu64)"` |

This covers generated module carriers (`zig_special_types.h:98,102`), direct
checked-op casts (`vorbis_info_B6B89893.c:57` etc.), and generated 64-bit
literals (`std_math_80387A0C.c:724,921,1041`; `decode_512E9AC7.c:136,3178`;
`floor_426BB7D9.c:1615,1629`; `main_4D6BD2B8.c:137`; `dsp_8A8E2260.c:19`).

Two spelling details are mandatory so the same emitted C keeps 32-bit literal
semantics:

- Preserve the existing 32-bit branches. `intLitSuffixUns` returns `""` for
  values `<= 2147483647` and `"u"` for `<= 4294967295`; only the `"ULL"` branch
  becomes `Z98_U64_C(<digits>)`. `intLitSuffixNeg` returns `""` for
  `<= 2147483647`; only its `"LL"` branch becomes `Z98_I64_C(<digits>)`.
  Do not wrap small constants — that would silently promote 32-bit arithmetic.
- Negative forms wrap the magnitude, then negate: `(-Z98_I64_C(<digits>))` or
  `Z98_I64_MIN`, never `Z98_I64_C(-<digits>)` (token pasting must see a
  positive digit token). `writeMinSignedIntLiteral` must use `Z98_I64_MIN` (or
  `(-Z98_I64_MAX - Z98_I64_C(1))`) for the `-2^63` case; it must not emit
  `Z98_I64_C(9223372036854775808)`, which is out of signed range.

`sf/src/include/std_time_prelude.h:48-56` and
`sf/src/emit_support.zig:179-187` are POSIX-only (`#ifndef _WIN32`), so they are
preprocessed out for MSVC/OWC. For uniformity and to prevent future leakage,
T5.3 may change them to `z64`/`Z98_I64_C` as well; this is not required for the
Windows compile path but is listed for completeness.

#### R1-C1.4 Same emitted C on all three toolchains

After the spelling layer, every emitted TU uses only the shared tokens:

| Emitted token | mingw (GCC) | MSVC 6 | OpenWatcom |
|:--|:--|:--|:--|
| `z64` | `long long` | `__int64` | `__int64` |
| `zu64` | `unsigned long long` | `unsigned __int64` | `unsigned __int64` |
| `Z98_I64_C(n)` | `n##LL` | `n##i64` | `n##i64` |
| `Z98_U64_C(n)` | `n##ULL` | `n##ui64` | `n##ui64` |
| `Z98_I64_MAX/MIN`, `Z98_U64_MAX` | macros above | macros above | macros above |

No `long long`/`LL`/`ULL` remains in Windows-compiled emitted C. `-std=c89` on
mingw still accepts `long long`/`LL`/`ULL` (the current recipe already uses
`-Wno-long-long`); VC6/OWC see only `__int64` and their documented
`i64`/`ui64` literal suffixes. `/Za` therefore no longer has a `long long`
obstacle. `__int64` remains valid under `/Za` on MSVC (Microsoft Learn,
`__int64`, URL above) and is the documented OpenWatcom 64-bit type
(`cpwcc.gml:2062-2085`).

#### R1-C1.5 Fallback if the VC6 `i64`/`ui64` suffix is rejected

If hardware testing shows VC6 `/Za` rejects `i64`/`ui64` (not expected; the
project's MSVC-first emitter already uses this convention), the literal macros
become 32-bit-half constructors with no 64-bit literal suffix:

```c
#define Z98_U64_C2(hi, lo) (((zu64)(unsigned long)(hi) << 16 << 16) | (zu64)(unsigned long)(lo))
#define Z98_U64_C(n) /* emitter emits Z98_U64_C2(0x........, 0x........) instead */
```

The emitter would then split each 64-bit constant into two 32-bit hex halves.
This is a fallback only; it is not the primary design. If neither form works,
the task must STOP-present MSVC 6 as unsupported. This report does not STOP:
the primary spelling layer is implementable and is in the T5.3 inventory.

### R1-H1 — OpenWatcom `/za` + `long long`: every TU, mapping decision

**Decision: map every TU to `__int64`/`i64`/`ui64`; do not use `/ze`.**
Coverage is not limited to `zig_compat.h`:

- `zig_compat.h`/`emit_support.zig:17-77`: the shared typedef/macro layer.
- `zig_runtime.h`/`zig_runtime.c`/`emit_support.zig:199-677`: all helper and
  cast definitions.
- Generated module carriers and checked-op casts: `c89_emit.zig` sites in
  R1-C1.3.
- `zig_pal.c`/`emit_support.zig:679-1037`: uses `i64`/`u64`; now defined for
  OWC by the R1-C1.1 typedef arm.
- `zig_nocrt.c` (new): include `zig_compat.h`; no `long long`.
- `std_time_prelude.h` POSIX-only block: either mapped for uniformity or
  excluded by `_WIN32`; not an MSVC/OWC TU.

Every emitted Windows TU includes `zig_compat.h` before using these tokens
(T5.3a §1.2), so `/za` applies uniformly. OpenWatcom documents `__int64` as a
supported 64-bit type and `i64`/`ui64` as its literal suffixes
(`cpwcc.gml:2062-2120`). The old `build_owc.bat`'s `/za` + `long long`
combination was therefore a latent failure, not a working baseline. If hardware
shows `/za` rejects `__int64` itself (not expected), the fallback is `/ze` for
all TUs; this would be recorded as a toolchain limitation, not silently mixed
per file. `/ze` is **not** part of the primary design.

### R1-M1 — `ZIG_WIN_NT` in the CRT alternates and aliases

The nt `_crt` templates in §3.4 omitted `ZIG_WIN_NT`. More generally,
`ZIG_WIN_NT` is a **profile** define, not a CRT define: in an nt dump every one
of the four emitted scripts must carry it, including `build_target_nocrt.bat`
and `build_owc_nocrt.bat`; in a 9x dump none of the four carries it. `_nocrt`
denotes “no CRT”, not “9x profile”. Corrected compile lines:

`build_target_crt.bat` (nt dump):

```bat
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_WIN_NT /MT /I .
```

`build_target_nocrt.bat` (nt dump):

```bat
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_WIN_NT /DZIG_NO_CRT /Zl /I .
```

`build_owc_crt.bat` (nt dump):

```bat
wcc386 /za /we /dZIG_WIN32 /dZIG_WIN_NT /bt=nt /sg /i=. <module>.c
```

`build_owc_nocrt.bat` (nt dump):

```bat
wcc386 /za /we /dZIG_WIN32 /dZIG_WIN_NT /dZIG_NO_CRT /bt=nt /zl /sg /i=. <module>.c
```

In a 9x dump the same lines omit `/DZIG_WIN_NT` / `/dZIG_WIN_NT`. Aliases are
emitted per profile: an nt `build_target.bat` calls `build_target_crt.bat %1`
(and the OWC alias calls `build_owc_crt.bat %1`), so the define is preserved;
a 9x alias calls the `_nocrt` script, which correctly lacks the define.
`build_target.sh`'s nt branch already carries `-DZIG_WIN_NT` (T5.3a §8.1).

### R1-M2 — OpenWatcom stack: 2 MiB

The first report's `option stack=1048576` is too tight against the measured
z9torr frames (545,024 B `main`, 201,152 B `addrSeen`, 136,080 B
`schedulerInit`) plus any call-chain depth. Corrected lines in
`build_owc_nocrt.bat` and `build_owc_crt.bat`:

```bat
wlink system nt op q opt stack=2097152 ...
```

MSVC already uses `/STACK:2097152`; the two natives now agree. This is a
2 MiB reserve; OpenWatcom's `COMMIT` documentation says the default committed
stack is the smaller of 64K or the specified stack
(`docs/doc/lg/ldcommit.gml`), so the initial commit remains bounded. The exact
worst call chain is not proven here; 2 MiB is the chosen design margin and is
hardware-verification pending.

### R1-L1 — Missed test/doc references and manual survey

Added references (old names are preserved as aliases, so these remain true; if
aliases were removed these would break):

| File:line | Reference / action |
|:--|:--|
| `examples/z98/z9torr/tests/tier4_wine.sh:89` | Loop checks the emit tree contains `build_target.bat` and `build_owc.bat`; the aliases keep this test passing. T5.3 should add the four new names to the same existence check (or keep the old-name check plus aliases). |
| `examples/z98/z9torr/demo/win9x_README.txt:56` | States the `-osw` tree carries `build_target.bat`/`build_owc.bat`; aliases keep it true. T5.3 should truth-up the redistribution sentence to name the `_nocrt` default. |
| `docs/sf/manuals/en/**` | Survey: **241 occurrences in 45 HTML files** reference `build_target.bat`/`build_owc.bat` (plus the `docs/sf/manuals/dist/en/` mirror). Old-name aliases prevent dangling references; the quoted script bodies are pre-T5.3 text and are stale, not broken. Representative files: `vol1-03-your-machine.html`, `vol1-04-installing.html`, `vol1-05-first-program.html`, `vol3-08-win9x.html`, `vol5-04-target-win9x.html`, `vol5-19-pack-for-diskette.html`. |
| `docs/sf/manuals/src/build_owc.bat` | Manual source helper, not emitted output; no old-name breakage. |
| `docs/sf/AI_TASKS_sf.md:485,834`; `docs/sf/Design_p2.md:1835`; `docs/sf/RUNTIME_PAL_p2.md:975-1035`; `docs/reference/compilation_model.md:22`; `docs/design/C89_Codegen.md:604`; `docs/design/CompilationPipeline.md:83`; `docs/design/DESIGN.md:1111,1150` | Doc truth-up candidates for the new names/default; aliases keep names valid. |

### R1-L2 — Citation corrections

| Earlier claim | Correction |
|:--|:--|
| `ogg_06518614.c:1709` as the `last_granule * 1000` multiply | The multiply is `ogg_06518614.c:1705`; `:1709` is `zT_11 = (zT_79FAE712_u64)sample_rate;`. The unsigned divide is `:1712`. |
| `zig_runtime.h:120` as signed 64-bit right shift | Signed right shift is `zig_runtime.h:118` (`maxs >> b`, `mins >> b`); `:120` is `if (a == 0ULL || b == 0ULL)`. |
| `zig_runtime.h:113` as unsigned 64-bit right shift | Unsigned right shift is `zig_runtime.h:123` (`zig_ovf_maxu(w) >> b`); `:113` is the signed-shift function signature. |
| `zig_runtime.h:71,117` as 64-bit left shift | Left shifts are `zig_runtime.h:57` (`zig_wrap_shl_s`) and `:72` (`zig_wrap_shl_u`); `:117` is `if (b >= (long long)w)`. |
| OWC `__I8LS`/`__U8LS` source `i8ls086.asm` | For 32-bit x86, use `bld/clib/cgsupp/a/i8rs386.asm:71-116`, which defines `__U8RS`, `__I8RS`, `__U8LS`, and `__I8LS`. `i8ls086.asm` is the 16-bit source and is not the 32-bit Win32 helper. |

These corrections do not change the helper-provision decision (vendor
`clib3r.lib`) or any script command.

### R1-L3 — `main` declaration wording

Corrected wording: the startup declares `int main(int argc, char** argv);` and
calls it with two arguments. Emitted `main` forms differ:

- `hello` emits `int main(void)` (T5.3a §11.2 context; emitted `main_*.c`).
- z9play/z9torr emit `int main(int argc, char** argv)` (T5.3a §11.2 cites
  `main_4D6BD2B8.c:4649`, `main_B8D622A5.c:3934`).

The startup call is **ABI-compatible** on the three target conventions, not a C
prototype match: cdecl callers clean extra arguments; OpenWatcom's default
register convention passes/ignores extra register arguments; the callee never
returns through the entry point (it calls `exit`). This is an emitted-ABI
contract, not a claim of strict C89 prototype correctness. T5.3 should document
it in `13_windows_support.md`; if strict prototype correctness is required, the
alternative is an emitted per-program entry wrapper, which is out of scope here.
Hardware verification pending.

### R1-L4 — command.com-compatible batch scripts (Win98 baseline)

The §3.4 templates used `%~1`, `%~dp0`, `%*`, parenthesized `if ... else`, and
`^` line continuations. Those are cmd.exe features, not a safe Win98
`command.com` baseline (Win98 ships `command.com`; `cmd.exe` is an NT tool).
Replacement rules for all four `.bat` scripts and the two aliases:

1. No `%~` modifiers, no `%*`, no `%~dp0`, no parenthesized `if/else`.
2. No `setlocal`/`endlocal` (removed to avoid any command.com variance).
3. No `^` continuation; each `link`/`wlink` command is one long line.
4. Output argument handling (exact replacement for the `%~1` line):

```bat
set OUT=prog.exe
if not "%1"=="" goto z98_have_out
goto z98_out_ready
:z98_have_out
set OUT=%1
:z98_out_ready
```

`set OUT=%1` deliberately preserves quotes if the caller passed a quoted path;
the `link ... /out:%OUT%` expansion then yields `/out:"path with spaces"`.
Unquoted paths with spaces are not supported by `command.com`; document “quote
the output path (or use an 8.3 path)”. The default `prog.exe` has no spaces.

5. Alias replacement (no `%~dp0`; run from the emitted output directory, the
   same rule the generated scripts already state):

```bat
@echo off
REM Compatibility alias; 9x default is build_target_nocrt.bat.
REM Run from the emitted output directory.
call build_target_nocrt.bat %1
```

For an nt dump the same alias calls `build_target_crt.bat %1`; for OpenWatcom
the corresponding `_owc` script. `call` is a `command.com` batch feature, and
`%1` (not `%*`) is used because the scripts take one output argument.

6. Single-line link examples (replace the `^`-continued lines in §3.4):

```bat
link /NODEFAULTLIB /subsystem:console,4.0 /STACK:2097152 /entry:_mainCRTStartup@0 main_4D6BD2B8.obj ... zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj kernel32.lib winmm.lib wsock32.lib libcmt.lib /out:%OUT%
```

```bat
wlink system nt op q opt stack=2097152 option nodefaultlibs option start=_mainCRTStartup file main_4D6BD2B8.obj,...,zig_runtime.obj,zig_pal.obj,zig_nocrt.obj,c_exit.obj library kernel32,clib3r,winmm,wsock32 name %OUT%
```

The module lists are still the emitter's `@MODOBJ@`/`@MODOWCOBJ@` substitutions;
the examples show z9play module names only for line shape. `wsock32` is present
only when `net_emitted`; `winmm` is always present. If the script is run from a
directory other than the emitted tree, `command.com` has no `%~dp0` equivalent;
the documented invocation is “from inside the emitted output directory”, which
is already how the current `.bat` scripts are described.

Exact command.com-compatible skeleton for `build_target_nocrt.bat` (the other
three scripts substitute their own compiler flags/link line; `_crt` nt adds
`/DZIG_WIN_NT`, OWC uses `wcc386`/`wlink`):

```bat
@echo off
REM build_target_nocrt.bat - generated by zig1 (MSVC cl, Win9x no-CRT DEFAULT)
REM REDISTRIBUTION: single EXE, no msvcrt.dll. Imports only OS DLLs.
REM Status: design-verified; hardware verification pending.
REM usage: build_target_nocrt.bat [OUT]   (run from the emitted output dir)
set OUT=prog.exe
if not "%1"=="" goto z98_have_out
goto z98_out_ready
:z98_have_out
set OUT=%1
:z98_out_ready
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_NO_CRT /Zl /I .
echo Compiling...
@MODC@
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
echo Linking...
link /NODEFAULTLIB /subsystem:console,4.0 /STACK:2097152 /entry:_mainCRTStartup@0 @MODOBJ@ zig_runtime.obj zig_pal.obj zig_nocrt.obj c_exit.obj kernel32.lib winmm.lib @WSOCK_DEP@ libcmt.lib /out:%OUT%
echo Built: %OUT%
```

### R1 inventory delta (add to §5)

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/include/zig_compat.h:18-41` | Add `Z98_I64_C`/`Z98_U64_C`/`Z98_I64_MAX/MIN`/`Z98_U64_MAX`; map OWC `z64`/`zu64` to `__int64`; remove OWC exclusion from fixed-width typedefs. |
| `sf/src/emit_support.zig:17-77` | Mirror the `zig_compat.h` layer. |
| `sf/src/include/zig_runtime.h:9-278` | Replace `long long`/`unsigned long long`/`LL`/`ULL`/`~0ULL` with `z64`/`zu64`/macros. |
| `sf/src/emit_support.zig:199-486` | Mirror `zig_runtime.h`. |
| `sf/src/include/zig_runtime.c:6-68` | Replace types/literals with `z64`/`zu64`/`Z98_I64_MAX`. |
| `sf/src/emit_support.zig:488-677` | Mirror `zig_runtime.c`. |
| `sf/src/c89_emit.zig:1701,1708` | Carrier typedefs use `z64`/`zu64`. |
| `sf/src/c89_emit.zig:3852,3863,3971-3980,4057,4076,4095,4188,4203` | Literal suffix emitters → macro-wrapped constants. |
| `sf/src/c89_emit.zig:4306-4336,4989,4994,5024,5331,5379-5381,6227,6230,6246,6275,6279,7540` | Direct `long long`/`unsigned long long`/`ULL`/`0ull` spellings → `z64`/`zu64`/macros. |
| `sf/src/include/std_time_prelude.h:48-56`; `sf/src/emit_support.zig:179-187` | POSIX-only `long long`/`LL`; map for uniformity or leave preprocessed out on Windows (recommended: map). |
| `sf/src/include/zig_nocrt.c` (new) | Include `zig_compat.h`; `pal_wallclock_unix` extern uses `z64`; no `long long`. |
| `examples/z98/z9torr/tests/tier4_wine.sh:89` | Add new script names (and keep old aliases) in the emitted-tree existence check. |
| `examples/z98/z9torr/demo/win9x_README.txt:56` | Truth-up redistribution wording; old names remain because of aliases. |
| `docs/sf/manuals/en/**` (45 files, 241 occurrences) | Optional/manual truth-up; aliases prevent dangling names. |
| `build_target_crt.bat` / `build_owc_crt.bat` templates | Add `/DZIG_WIN_NT` / `/dZIG_WIN_NT`. |
| `build_owc_nocrt.bat` / `build_owc_crt.bat` templates | `option stack=2097152`. |
| All four `.bat` templates + aliases | Replace cmd.exe syntax with the R1-L4 command.com block; single-line link commands. |

### R1 residual risks

| # | Risk | Impact | Mitigation / status |
|:--|:--|:--|:--|
| R1-1 | VC6 rejects `i64`/`ui64` under `/Za` | literal macros fail | hi/lo constructor fallback (R1-C1.5); if both fail, STOP-present MSVC 6. Hardware verification pending. |
| R1-2 | OWC `/za` rejects `__int64` | all TUs fail | vendor docs list `__int64` as a keyword; if hardware disproves, fallback is `/ze` for all TUs (documented, not silent). |
| R1-3 | OWC system headers define `i8`/`i64` etc. | duplicate typedefs when OWC exclusion is removed | hardware compile; if conflict, use `z98_`-prefixed carrier names in a follow-up STOP-present. |
| R1-4 | command.com quoting of `%1` / paths with spaces | wrong output path | documented: quote the path or use 8.3; default `prog.exe` is safe. |
| R1-5 | 2 MiB stack still insufficient for a deeper call chain | Win9x stack overflow | measured max frame 545 KiB; 2 MiB margin; hardware verification pending. |
| R1-6 | Literal macros in `static const`/constant expressions | compile-time rejection | C89 constant expressions permit casts/shifts and macro expansion; `i64`/`ui64` forms are primary; hi/lo fallback uses casts/shifts. Hardware compile pending. |
| R1-7 | Native stdio macro layer remains header-version-dependent | unresolved `_iob`/`_filbuf`/`_flsbuf` | R1-C1 superset shim + hardware compile; unchanged from §3.1. |
| R1-8 | Old-name aliases in command.com cannot locate sibling via `%~dp0` | alias fails outside output dir | documented “run from emitted output directory”; same rule as all generated `.bat` scripts. |

**Fix-round status: DONE_WITH_CONCERNS.** The critical `/Za`/`long long` blocker
is resolved by design (portable typedef + literal-macro layer, with a hi/lo
fallback), every affected site is in the T5.3 inventory, and the remaining
uncertainties are native-toolchain/hardware items explicitly deferred by
Amendment 5. No source files were edited; only this report was amended.

---

## Fix round 2 (2026-10-18)

This section is appended per the second review ruling. It supersedes the
C1.3/inventory and L4 portions of Fix round 1, and corrects the two minor
citations/counts below. Still report-only: zero source edits, no
downloads/installs, no native-toolchain probes. Native claims remain
**design-verified; hardware verification pending**.

### R2-C1 — Complete 64-bit spelling audit (the round-1 inventory was incomplete)

**Finding accepted.** Fix round 1's C1 design was correct but its site list was
not exhaustive. In particular it missed the 64-bit literals emitted inside
`emitFloatHexHelper` and one boundary literal:

| `sf/src/c89_emit.zig` line | Missed spelling | Context |
|:--|:--|:--|
| `4165` | `"0xFFFFFFFFFFFFFFFFull"` | `satMaxULitBound(64)` |
| `5387` | `0xFFFFFFFFFFFFFULL` | `emitFloatHexHelper` (`:5339`), `zT_man = zT_bits & ...` |
| `5395` | `0x10000000000000ULL` | `emitFloatHexHelper` (`:5339`), implicit-bit insert |
| `5397` | `0xFULL` | `emitFloatHexHelper` (`:5339`), nibble mask |
| `4997` | `"ULL"` append (not `:4994`, which is the `while` line) | enum value table |

All are now added to the C1.3 table and the R2 inventory delta. The earlier
`:4994` citation is corrected to `:4997`.

#### R2-C1.1 Audit command and result

The comprehensive audit used both a broad spelling grep and a fresh emitted-tree
grep (same `/tmp/m6/zig1_5_clean` dumps as T5.3b):

```sh
cd /workspace/znineeight
grep -nE 'long long|unsigned long long|0[xX][0-9A-Fa-f]+(ULL|LL|ull|ll)|[0-9]+(ULL|LL|ull|ll)\b|\bLL\b|\bULL\b' \
    sf/src/c89_emit.zig sf/src/emit_support.zig
grep -RInE 'long long|unsigned long long|0[xX][0-9A-Fa-f]+(ULL|LL|ull|ll)|[0-9]+(ULL|LL|ull|ll)\b' \
    /tmp/t53b_dump/z9play /tmp/t53b_dump/z9torr /tmp/t53b_dump/hello \
    --include='*.c' --include='*.h'
```

Result before the T5.3 fix:

- Emitter/support: **136 matching lines** across the two files. Two are not C
  spellings and are excluded from the edit list: `c89_emit.zig:4862` (comment)
  and `c89_emit.zig:6539` (`"LL:n"` marker). Of the remaining 134, three are
  the standalone suffix strings `3974` (`"ULL"`), `3979` (`"LL"`), and `4997`
  (`"ULL"`), and three (`4453`, `4467`, `4478`) write variables whose
  definitions are rewritten at `4317`/`4306`. The complete set is in
  R2-C1.2/R2-C1.3; no other site was found.
- Fresh emitted tree: **4,065 matching lines** — z9play 1,606, z9torr 2,355,
  hello 104. The audit was over all `.c/.h` files, not just `zig_runtime.h`.
- `sf/src/emit_support.zig` sites are enumerated in R2-C1.3; every one is inside
  the emitted `zig_compat.h`, `std_time_prelude.h`, `zig_runtime.h`, or
  `zig_runtime.c` literal.

After the T5.3 spelling layer the expected result is **zero** matches for
`long long`/`unsigned long long`/64-bit suffix in the Windows-compiled tree;
the audit command above is the mechanical acceptance check. (The POSIX-only
`std_time_prelude.h` block is excluded by `_WIN32`; if T5.3 maps it to `z64`,
the zero-match check also holds for the raw tree.)

#### R2-C1.2 Complete `c89_emit.zig` code-emitting site list

This is the comprehensive list from the audit (line numbers current). It
supersedes the partial C1.3 table.

| Line(s) | Spelling / use | Required action |
|:--|:--|:--|
| `1701`, `1708` | `typedef long long` / `typedef unsigned long long` carrier typedefs | `typedef z64` / `typedef zu64` |
| `3974`, `3979` | `"ULL"` / `"LL"` suffix returns | replace suffix-return design with `writeU64Const`/`writeI64Const` wrappers |
| `4165` | `"0xFFFFFFFFFFFFFFFFull"` (64-bit boundary) | `Z98_U64_MAX` or `Z98_U64_C(0xFFFFFFFFFFFFFFFF)` |
| `4306` | `(long long)` in checked-op expression | `(z64)` |
| `4317` | `0ull` + `(unsigned long long)` | `Z98_U64_C(0)` + `(zu64)` |
| `4318` | `(unsigned long long)(-(long long)` | `(zu64)(-(z64)` |
| `4323` | `0ull` + `(unsigned long long)` | `Z98_U64_C(0)` + `(zu64)` |
| `4336` | `(unsigned long long)` | `(zu64)` |
| `4453`, `4467`, `4478` | writes the `div0ull`/`eq0ll` variables | no independent literal; changes follow `4317`/`4306` |
| `4989` | `static const unsigned long long` | `static const zu64` |
| `4997` | appended `"ULL"` enum-value suffix | `Z98_U64_C(<digits>)` (corrected from `:4994`) |
| `5024` | `unsigned long long x = (unsigned long long)v;` | `zu64 x = (zu64)v;` |
| `5331` | `((unsigned long long)(unsigned int)(` | `((zu64)(unsigned int)(` |
| `5379`, `5380`, `5381` | float-hex union/fields `unsigned long long` | `zu64` |
| `5387` | `0xFFFFFFFFFFFFFULL` | `Z98_U64_C(0xFFFFFFFFFFFFF)` |
| `5395` | `0x10000000000000ULL` | `Z98_U64_C(0x10000000000000)` |
| `5397` | `0xFULL` | `Z98_U64_C(0xF)` |
| `6227`, `6230`, `6246`, `6275`, `6279` | `emitCastToC(..., "long long"/"unsigned long long", ...)` | `"z64"`/`"zu64"` |
| `7540` | `(unsigned long long)` | `(zu64)` |

The `4862` comment and `6539` marker are intentionally not code edits; the
marker `"LL:n"` is not a C literal.

#### R2-C1.3 Complete `emit_support.zig` site ranges

`emit_support.zig` is the source of truth for the emitted support files; the
audit found these line groups, all of which must be mirrored to
`z64`/`zu64`/`Z98_*_C`:

- `39,40,42,43` — `zig_compat.h` `z64`/`zu64` typedef branches.
- `179,183,187` — `std_time_prelude.h` POSIX-only `long long`/`LL` (preprocessed
  out on `_WIN32`; map for uniformity or leave with an explicit note).
- `208,209` — `zig_runtime.c` PAL prototypes.
- `221-330` — every `zig_ovf_*`, `zig_wrap_*`, `zig_overflow_flag_*` signature,
  local, cast, and `ULL`/`LL` literal.
- `348,349,356,357` — `std_print_*` prototypes.
- `358-365` — `std_checked_cast_*` prototypes.
- `460-480` — `zig_cast_checked_s/u` definitions and casts.
- `498,499` — `zig_runtime.c` PAL prototypes (duplicate literal block).
- `526-561` — `std_checked_cast_*` definitions and `ULL` literals.

The canonical mirrors are `sf/src/include/zig_compat.h`,
`sf/src/include/std_time_prelude.h`, `sf/src/include/zig_runtime.h`, and
`sf/src/include/zig_runtime.c`. The new `zig_nocrt.c` must include
`zig_compat.h` (its `pal_wallclock_unix` extern is `z64`, not `long long`).

#### R2-C1.4 `emitFloatHexHelper` (the missed file)

`emitFloatHexHelper` is the source of the missed `5387/5395/5397` literals. Its
64-bit branch (`sf/src/c89_emit.zig:5339-...`) must use `zu64` for the union and
fields and `Z98_U64_C(...)` for all three masks/bit constants. The 32-bit branch
(`float`/`unsigned int`) is unchanged. The emitted tree's
`z98_printFloatHex64` is part of every module that reaches float formatting;
missing these literals would fail VC6 `/Za` even if every other site were fixed.

#### R2-C1.5 Inventory delta added to the T5.3 plan

Add to the Fix-round-1 inventory delta:

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/c89_emit.zig:4165` | `satMaxULitBound(64)` boundary literal → `Z98_U64_MAX`. |
| `sf/src/c89_emit.zig:5387` | `emitFloatHexHelper` mantissa mask → `Z98_U64_C(0xFFFFFFFFFFFFF)`. |
| `sf/src/c89_emit.zig:5395` | `emitFloatHexHelper` implicit bit → `Z98_U64_C(0x10000000000000)`. |
| `sf/src/c89_emit.zig:5397` | `emitFloatHexHelper` nibble mask → `Z98_U64_C(0xF)`. |
| `sf/src/c89_emit.zig:4997` | Enum value-table `ULL` append (corrected cite). |
| `sf/src/c89_emit.zig:4453,4467,4478` | Confirm the variables they write were rewritten at `4317`/`4306`; no independent spelling. |
| `sf/src/emit_support.zig:39-561` (enumerated R2-C1.3) | All support-type/literal sites. |
| Fresh emitted tree audit | Acceptance: zero `long long`/`unsigned long long`/64-bit-suffix matches in Windows-compiled `.c/.h`; audit command R2-C1.1. |

### R2-L4 — command.com-safe link commands via response files

**Finding accepted.** The Fix-round-1 single-line `link`/`wlink` commands are
still too long for `command.com`'s ~127-character limit once the object list is
expanded (the fixed prefix alone measured 200-217 chars for the z9play/z9torr
shapes). A single-line command is therefore not a Win98 `command.com` design.

**Decision: response files.** Keep the R1-L4 argument/output-path handling
(`%1`, no `%~`, no `%*`, no parenthesized `else`, no `setlocal`), but move the
entire linker command into a response file created with short `echo` lines.
Each `echo` line is well under 127 chars; the executed command is only
`link @z98_link.rsp` / `wlink @z98_link.lnk`. No cmd.exe requirement is needed.

Vendor support:

- MSVC LINK: “`@response_file` — Specifies a linker response file. A text file
  that contains linker commands.”
  https://learn.microsoft.com/en-us/cpp/build/reference/at-specify-a-linker-response-file?view=msvc-170
- OpenWatcom `wlink`: “If the directives are contained within a file, the `@`
  character is used to reference that file. If no file extension is specified, a
  file extension of `lnk` is assumed.” (`docs/doc/lg/tutmain.gml:21-26`,
  https://github.com/open-watcom/open-watcom-v2/blob/master/docs/doc/lg/tutmain.gml).

#### R2-L4.1 MSVC response-file script block

Exact `build_target_nocrt.bat` (and `_crt` with its own flags/libs) block;
`@MODRSP@` is the emitter's one-line-per-module substitution
`echo <module>.obj >> z98_link.rsp`. Every generated line is short.

```bat
@echo off
REM build_target_nocrt.bat - generated by zig1 (MSVC cl, Win9x no-CRT DEFAULT)
REM REDISTRIBUTION: single EXE, no msvcrt.dll. Imports only OS DLLs.
REM Status: design-verified; hardware verification pending.
REM usage: build_target_nocrt.bat [OUT]   (run from the emitted output dir)
set OUT=prog.exe
if not "%1"=="" goto z98_have_out
goto z98_out_ready
:z98_have_out
set OUT=%1
:z98_out_ready
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32 /DZIG_NO_CRT /Zl /I .
echo Compiling...
@MODC@
cl %CFLAGS% zig_runtime.c
cl %CFLAGS% zig_pal.c
cl %CFLAGS% zig_nocrt.c
cl %CFLAGS% c_exit.c
echo Linking...
if exist z98_link.rsp del z98_link.rsp
echo /NODEFAULTLIB >> z98_link.rsp
echo /subsystem:console,4.0 >> z98_link.rsp
echo /STACK:2097152 >> z98_link.rsp
echo /entry:_mainCRTStartup@0 >> z98_link.rsp
@MODRSP@
echo zig_runtime.obj >> z98_link.rsp
echo zig_pal.obj >> z98_link.rsp
echo zig_nocrt.obj >> z98_link.rsp
echo c_exit.obj >> z98_link.rsp
echo kernel32.lib winmm.lib @WSOCK_DEP@ libcmt.lib >> z98_link.rsp
echo /out:%OUT% >> z98_link.rsp
link @z98_link.rsp
echo Built: %OUT%
```

For an nt dump the same script has `/DZIG_WIN_NT` in `CFLAGS`; for
`build_target_crt.bat`, replace `/DZIG_NO_CRT /Zl` with `/MT` and drop
`/NODEFAULTLIB` and `libcmt.lib` (the `/MT` default library supplies the static
CRT). The `@MODRSP@` module-object lines are identical. `@WSOCK_DEP@` expands
to `wsock32.lib` only when `net_emitted`.

#### R2-L4.2 OpenWatcom response-file script block

Exact `build_owc_nocrt.bat` (`_crt` differs only in no `/dZIG_NO_CRT`, no
`/zl`, and no `option nodefaultlibs`/`clib3r`; the response-file mechanism is
the same). `@MODOWCRSP@` is the emitter's one-line-per-module substitution
`echo file <module>.obj >> z98_link.lnk`.

```bat
@echo off
REM build_owc_nocrt.bat - generated by zig1 (OpenWatcom, Win9x no-CRT DEFAULT)
REM REDISTRIBUTION: single EXE, no runtime DLL dependency. Imports only OS DLLs.
REM Status: design-verified; hardware verification pending.
REM usage: build_owc_nocrt.bat [OUT]   (run from the emitted output dir)
set OUT=prog.exe
if not "%1"=="" goto z98_have_out
goto z98_out_ready
:z98_have_out
set OUT=%1
:z98_out_ready
echo Compiling...
@MODOWC@
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_runtime.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_pal.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. zig_nocrt.c
wcc386 /za /we /dZIG_WIN32 /dZIG_NO_CRT /bt=nt /zl /sg /i=. c_exit.c
echo Linking...
if exist z98_link.lnk del z98_link.lnk
echo system nt >> z98_link.lnk
echo option nodefaultlibs >> z98_link.lnk
echo option start=_mainCRTStartup >> z98_link.lnk
echo option stack=2097152 >> z98_link.lnk
@MODOWCRSP@
echo file zig_runtime.obj >> z98_link.lnk
echo file zig_pal.obj >> z98_link.lnk
echo file zig_nocrt.obj >> z98_link.lnk
echo file c_exit.obj >> z98_link.lnk
echo library kernel32,clib3r,winmm@WSOCK_LIB@ >> z98_link.lnk
echo name %OUT% >> z98_link.lnk
wlink @z98_link.lnk
echo Built: %OUT%
```

Multiple `FILE` directives are explicitly allowed by the vendor linker
(“More than one `FILE` directive may be used”, `docs/doc/lg/ldfile.gml`). This
keeps every `echo` line short. `@WSOCK_LIB@` expands to `,wsock32` only when
`net_emitted`.

#### R2-L4.3 command.com limits, quoting, and aliases

- The executed command line is `link @z98_link.rsp` or `wlink @z98_link.lnk`
  (well under 127 chars). The response-file contents are not subject to the
  command-line limit; each generating `echo` line is short because it carries
  one object/option.
- `%1` remains the only argument; no `%~`, `%*`, `%~dp0`, parenthesized `if`,
  `setlocal`, or `^` continuation. `call` remains the alias mechanism.
- `set OUT=%1` preserves quotes; `echo /out:%OUT% >> z98_link.rsp` writes the
  quoted output path. Paths with spaces must be quoted; the resulting response
  line must still fit command.com's line limit. Recommended: use an 8.3/no-space
  output path (default `prog.exe` is safe). This is the same documented
  constraint as R1-L4, now with only the output path on the response line.
- Alias `build_target.bat` (9x) runs `call build_target_nocrt.bat %1`; nt runs
  `call build_target_crt.bat %1`; `build_owc.bat` follows the matching OWC
  script. Run from the emitted output directory (no `%~dp0` in `command.com`).
- `echo` may leave a trailing space before `>>`; response-file parsers treat it
  as whitespace. Do not put a space between a filename and `>>` if a future
  parser is strict; either form is command.com-valid.

### R2 minor corrections

| Earlier text | Correction |
|:--|:--|
| “241 occurrences in 45 HTML files” (`docs/sf/manuals/en`) | Actual: **45 files / 129 occurrences** in `docs/sf/manuals/en`; **130 occurrences across all manuals** (including the `dist/en` mirror). The alias/no-dangling conclusion is unchanged. |
| `zig_runtime.h:120` as the `if (a == 0ULL || b == 0ULL)` line | The `if` is at `zig_runtime.h:121`; `:120` is the `zig_overflow_flag_shl_u` signature. |

### R2 residual risks

| # | Risk | Impact | Mitigation / status |
|:--|:--|:--|:--|
| R2-1 | A new/missed 64-bit spelling site | VC6 `/Za` fails again | R2-C1.1 audit command is the acceptance gate; zero matches before hardware sign-off. |
| R2-2 | `emitFloatHexHelper` literals are easy to miss | float-formatting modules fail VC6 | R2-C1.4 explicitly covers `5387/5395/5397`; audit includes them. |
| R2-3 | command.com response-file line limit for a very long output path | link fails | use quoted 8.3/no-space output path; default `prog.exe`; documented. |
| R2-4 | `echo` trailing spaces / redirect parsing | malformed response file | whitespace is legal in LINK/wlink response files; use `>>` with no ambiguity; hardware smoke pending. |
| R2-5 | `wlink` multiple `FILE` directives | link behavior | vendor docs explicitly allow multiple `FILE` directives (`ldfile.gml`); hardware pending. |
| R2-6 | `@MODRSP@`/`@MODOWCRSP@` emitter substitution must be one line per module | long line if merged | T5.3 emitter writes one `echo` line per module (short); audit by generated script length. |

**Fix-round-2 status: DONE_WITH_CONCERNS.** The missing 64-bit sites are now
enumerated with a reproducible audit, and the linker command is moved to
command.com-safe response files. Remaining concerns are hardware/native
verification items deferred by Amendment 5; no source edits were made.
