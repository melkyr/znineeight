# 13 — Windows support: Win9x / NT profiles, no-CRT runtime, native build scripts [updated: 2026-10-18 — M6 T5.3 fix round 1, Amendment 6: OpenWatcom restored to the bootstrap `long long`/`LL`/`ULL` mapping; MSVC keeps `__int64`/`i64`/`ui64`] [updated: 2026-10-18 — M6 T5.3 (Win9x no-CRT runtime + portable 64-bit C + native scripts)]

> Covers: `sf/src/include/zig_compat.h`, `sf/src/include/zig_nocrt.c`,
> `sf/src/include/zig_runtime.[ch]`, `sf/src/include/zig_pal.c`,
> `sf/src/c_exit.c`, `sf/src/emit_support.zig`, `sf/src/c89_emit.zig`
> (`emitBuildTargetSh`, the four `.bat` emitters, alias emitters), and
> `scripts/win32_cross/check_win9x_imports.sh`.
>
> **Status: design-verified; hardware verification pending (operator, after the
> z9play milestone).** Wine/mingw probes are recorded; MSVC 6 and OpenWatcom
> commands, symbols, and import expectations are design-verified from vendor
> documentation and emitted-C analysis only (M6 Amendment 5 forbids native
> toolchain probes).

## 1. Profiles

`-osw` selects the Windows target. The default profile is **9x**; `nt` is an
explicit opt-in.

| Profile | CLI | Emitted C define | Link model |
|:--|:--|:--|:--|
| Win9x (default) | `-osw`, `-osw 9x` | `ZIG_NO_CRT` (mingw 9x `.sh`); native `_nocrt` scripts | no-CRT / OS-DLL-only |
| NT/XP | `-osw nt` | `ZIG_WIN_NT` | normal CRT (mingw) / static CRT alternates (native) |

`ZIG_WIN_NT` is a **profile** define, not a CRT define: in an `nt` dump every
emitted script carries it, including the `_nocrt` variants. `ZIG_NO_CRT` is
only added by the mingw 9x no-CRT recipe and by the native `_nocrt` scripts.

## 2. Profile × toolchain × CRT matrix

| Toolchain / script | 9x default | nt opt-in | Runtime imports |
|:--|:--|:--|:--|
| mingw `build_target.sh` | `-DZIG_NO_CRT`, `-nostdlib -e,_mainCRTStartup -lgcc -lkernel32 -lwinmm` (+`-lwsock32` when net) | `-DZIG_WIN_NT`, normal CRT, `-lwinmm` (+`-lwsock32`) | 9x: KERNEL32 (+WINMM/WSOCK32), **no msvcrt** |
| MSVC 6 `build_target_nocrt.bat` | `/DZIG_NO_CRT /Zl`, `/NODEFAULTLIB`, `/entry:_mainCRTStartup@0`, `libcmt.lib` helper members | `/DZIG_WIN_NT /DZIG_NO_CRT /Zl`, same no-CRT link | KERNEL32 (+WINMM/WSOCK32); no msvcrt |
| MSVC 6 `build_target_crt.bat` | static `/MT` CRT (`LIBCMT`), no `ZIG_NO_CRT` | `/DZIG_WIN_NT /MT` | KERNEL32 (+WINMM/WSOCK32); no msvcrt import; whitelist-pending |
| OpenWatcom `build_owc_nocrt.bat` | `/dZIG_NO_CRT /zl`, `option nodefaultlibs`, `option start=_mainCRTStartup`, `clib3r` helpers | `/dZIG_WIN_NT /dZIG_NO_CRT /zl`, same | KERNEL32 (+WINMM/WSOCK32); no runtime DLL |
| OpenWatcom `build_owc_crt.bat` | default static CLIB, no `ZIG_NO_CRT` | `/dZIG_WIN_NT`, default static CLIB | KERNEL32 (+WINMM/WSOCK32); whitelist-pending |
| any `-osl` | n/a (Linux) | n/a | host libc |

Old names remain as **profile-correct aliases**: `build_target.bat` calls
`build_target_nocrt.bat` in a 9x dump and `build_target_crt.bat` in an nt dump;
`build_owc.bat` follows the matching OpenWatcom script. All `.bat` scripts are
`command.com`-safe (Win98 baseline): no `%~`/`%*`/`%~dp0`, no parenthesized
`if/else`, no `setlocal`, and no `^` continuations. Each is run from the
emitted output directory and takes one optional output path (`%1`).

## 3. Redistribution policy

The 9x default produces a **single drag-and-drop EXE** with no redistributable
runtime DLL. Only OS DLLs are allowed: `KERNEL32.DLL`, plus `WINMM.DLL` /
`WSOCK32.DLL` when the program reaches audio or Winsock (both ship with
Win95+). `msvcrt.dll` is a policy failure on the 9x default even though the DLL
exists on 9x, because the profile is no-CRT.

The static-CRT alternates are also single EXEs (no DLL dependency), but their
KERNEL32 imports may exceed the 9x whitelist. They are not claimed 9x-safe until
`check_win9x_imports.sh <exe> 9x` passes on real artifacts.

`check_win9x_imports.sh` is the loadability gate: Windows 9x resolves the whole
import table at load time, so a closed-world per-DLL/per-import whitelist is
required. Wine is not a Win98 loader.

## 4. No-CRT shim ownership

| Symbol(s) | Emitted owner | Guard |
|:--|:--|:--|
| `exit`, `atexit` registry, `c_exit` | `c_exit.c` | `_WIN32 && ZIG_NO_CRT` for `exit`/`atexit`; `c_exit` always |
| `mainCRTStartup`, `__main`, `GetCommandLineA` argv parser | `zig_pal.c` | `_WIN32 && ZIG_NO_CRT` |
| `pal_file_size`, `pal_file_seek64`, `pal_file_mtime`, `pal_getenv`, `pal_wallclock_unix` | `zig_pal.c` | `_WIN32` (file helpers split on `ZIG_WIN_NT`) |
| `strlen`, `memcpy`, `memset` (overlap-safe), `strncmp` | `zig_runtime.c` | `_WIN32 && ZIG_NO_CRT` |
| `__acrt_iob_func`, `fwrite`, `getchar`, `putchar`, `getc`, `putc`, `fgetc`, `fputc`, `_filbuf`, `_flsbuf`, `getenv`, `_time32`, `time` | `zig_nocrt.c` | `_WIN32 && ZIG_NO_CRT` |

`exit` runs the LIFO `atexit` registry (capacity 32) and then `ExitProcess`.
Normal return from `main` goes through `exit(main(argc, argv))`, so the
registry runs on both explicit `std.os.exit` and a normal return.
`TerminateProcess` / `pal_trap` / unhandled exceptions bypass the registry;
`leaveRaw` remains the explicit console restore and `atexit` is only the
backstop.

The startup parser copies `GetCommandLineA` into static storage and applies the
MSVCRT quoting/backslash rules into a second static buffer (`argc` capped at
256). `main` is called with two arguments even when a program emits
`int main(void)`; the extra arguments are ABI-compatible on cdecl and the
OpenWatcom register convention.

## 5. `_iob` / std streams per toolchain

| Toolchain | `<stdio.h>` stream expansion | Shim |
|:--|:--|:--|
| mingw (pinned) | `__acrt_iob_func(1/2)` | `__acrt_iob_func` + `__imp____acrt_iob_func` import pointer; **no `_iob`** |
| MSVC 6 | `_iob` / CRT stream macros | `FILE _iob[3]`, plus `fwrite`/`getc`/`putc`/`fgetc`/`fputc`/`_filbuf`/`_flsbuf` |
| OpenWatcom | `__iob` | `__w_FILE __iob[3]`, same function superset |

The `_iob` omission is **mingw-only**: emitted mingw objects reference only
`__imp____acrt_iob_func` (verified with `nm -u`); the `_iob` import in CRT
builds is mingw wrapper state and disappears under `-nostdlib`. Native MSVC/OWC
headers macro-expand streams onto `_iob`/`__iob`, so `zig_nocrt.c` defines the
native arrays from the toolchain's own header type. If a future mingw toolchain
starts referencing `_iob` directly, this decision must be re-probed.

`fwrite` is unbuffered (no `fflush` surface): it writes the complete slice to
`STD_ERROR_HANDLE` for the stderr stream and `STD_OUTPUT_HANDLE` otherwise,
trying `WriteConsoleA` then `WriteFile`. `getchar`/`getc`/`_filbuf` read one
byte from `STD_INPUT_HANDLE` via `ReadFile`.

## 6. Environment lifetime

`std.os.env` on Windows calls `pal_getenv`, which uses one static 32768-byte
buffer. The returned slice is valid until the **next** `env()` call (or process
exit), not for the process lifetime as the CRT environment block is. This is the
Amendment 3 narrowing; committed z9play/z9torr callers use the slice
immediately, and the Z98 runtime is single-threaded. A not-found variable or a
value requiring `>= 32768` bytes returns `null`; an existing empty value returns
an empty slice.

## 7. 64-bit C spelling layer

The emitted C is consumable by mingw GCC, MSVC 6 (`/Za`), and OpenWatcom
(`/za`) through `zig_compat.h`:

| Emitted token | mingw | MSVC 6 | OpenWatcom |
|:--|:--|:--|:--|
| `z64` / `zu64` | `long long` / `unsigned long long` | `__int64` / `unsigned __int64` | `long long` / `unsigned long long` |
| `Z98_I64_C(n)` / `Z98_U64_C(n)` | `n##LL` / `n##ULL` | `n##i64` / `n##ui64` | `n##LL` / `n##ULL` |
| `Z98_I64_MAX` / `Z98_I64_MIN` / `Z98_U64_MAX` | macros | macros | macros |

The emitter never writes `long long`, `unsigned long long`, `LL`, or `ULL`
outside the mapping branches of `zig_compat.h`. OpenWatcom uses the bootstrap
definition exactly (`long long` / `unsigned long long`; OpenWatcom's documented
C extension) with `LL`/`ULL` literals; MSVC 6 uses `__int64` /
`unsigned __int64` with its `i64`/`ui64` literal suffixes. The fixed-width
`i8`..`i64`/`u8`..`u64`/`usize` typedefs are emitted for OpenWatcom too (the
old `&& !defined(__WATCOMC__)` guard remains removed): emitted module
signatures, `zig_pal.c` and the `std_*_prelude.h` helpers spell those Z98 type
names, so OpenWatcom must receive the typedefs even though it does not need a
non-bootstrap 64-bit base type.

## 8. Verification status

- mingw 9x no-CRT: emitted hello/z9play/z9torr build as PE32 with only
  KERNEL32 (+WINMM/WSOCK32), pass the import whitelist, and run under Wine
  (startup/argv/stdio/time/env/file helpers; see the T5.3 report).
- NT mingw: emitted hello builds with the CRT link and runs under Wine.
- MSVC 6 / OpenWatcom: compile/link commands, entry decoration, response-file
  layout, helper-library choice, and import expectations are **design-verified;
  hardware verification pending**. No native compiler or `.exe` was run here
  (M6 Amendment 5).
- Win98/Me loadability: the import whitelist is the mechanical gate; real
  hardware confirmation is operator-owned after the z9play milestone.
- The manual HTML snapshots under `docs/sf/manuals/en/**` quote pre-T5.3 script
  bodies; the old script names still resolve through the aliases, so the
  references remain valid but the quoted text is stale.
