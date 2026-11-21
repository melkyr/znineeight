# M6 Task T5.3a report — No-CRT runtime inventory + safe implementation design (REPORT ONLY)

**Status:** DONE_WITH_CONCERNS. The design is complete and safe for the committed
mingw `-osw` 9x gate; §13 records the two places where the plan/brief is
incomplete or internally conflicting and the safe resolution chosen.

**Scope:** report-only. Zero repo source edits. All probes/experiments are under
`/tmp`; the only file created in the repository by this task is this report.
`run.err`/`run.out`/`progress.md` were left untouched. No push.

**Authority:** `docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`
`### Amendment 3` → `#### Task T5.3a` (operator ruling 2026-10-18), extending
`#### Task T5.3`; brief
`.superpowers/sdd/2026-10-11-z9play-m6-win9x-plan/task-5.3a-brief.md`.
Evidence base: `task-5.1-report.md` (§3, §4, §5, §7, §9, §10) and
`task-5.2-report.md`.

**Base / toolchain (observed):**

```sh
$ git rev-parse HEAD
1eb990d2cb554cafdad63cbbbbe2e7bad137947c
$ git status --short
?? run.err
$ md5sum /tmp/t52/zig1_5_clean
983ff15c251ae37a1a6c7b7fe8b7212f  /tmp/t52/zig1_5_clean
$ i686-w64-mingw32-gcc --version | head -1
i686-w64-mingw32-gcc (GCC) 12-win32
$ i686-w64-mingw32-objdump --version | head -1
GNU objdump (GNU Binutils) 2.40
$ wine --version
wine-8.0 (Debian 8.0~repack-4)
```

The existing `/tmp/t52/zig1_5_clean` was used (the brief says rebuild to
`/tmp/t53a` only if absent). It is post-T5.2: it has `--help` and `-osw nt`:

```sh
$ /tmp/t52/zig1_5_clean --help 2>&1 | sed -n '7,8p'
  -osw [9x|nt]  compile target = windows (default 9x = Win9x; nt = NT/XP profile)
  --target <linux|windows>  long-form target alias for -osl/-osw (windows = 9x default)
$ /tmp/t52/zig1_5_clean -osw nt --dump-c89 --output-dir /tmp/t53a_ntcheck \
    examples/z98/hello/main.zig && grep -l ZIG_WIN_NT /tmp/t53a_ntcheck/build_target.sh
/tmp/t53a_ntcheck/build_target.sh
```

---

## 0. Executive summary (findings that drive T5.3)

1. The measured no-CRT unresolved set is exactly T5.1 §3.3 plus `__main` and
   **argc/argv startup**:
   `exit`, `atexit`, `__acrt_iob_func` (via `__imp____acrt_iob_func`),
   `fwrite`, `getchar`, `putchar`, `getenv`, `__time32` (via
   `__imp___time32`), `strlen`, `memcpy`, `strncmp`, `__main`.
2. **New finding (not in T5.3's list): the no-CRT entry cannot pass
   `argc`/`argv`.** `sf/src/include/zig_pal.c:348-355` declares `int main(void)`
   and calls `main()` with no arguments. z9play/z9torr emitted `main` take
   `(argc, argv)` (`main_4D6BD2B8.c:4649`, `main_B8D622A5.c:3934`); under the current no-CRT stub both crash
   under Wine before parsing their command line (§11.2). T5.3 must add a
   `GetCommandLineA` parser in `mainCRTStartup`.
3. **New finding: normal return from `main` bypasses `atexit`.** The current stub
   calls `ExitProcess(result)` directly. T5.3's stub must call
   `exit(main(argc, argv))` so the registry runs on both `std.os.exit` and a
   normal `return` (§2, §11.3).
4. **New finding: the emitted Windows `LIBS` is incomplete for the `nt`/CRT path
   too.** `-osw nt` z9play currently fails to link with six unresolved
   `waveOut*` imports (T5.1 §10 concern 7). T5.3 must add `-lwinmm` for Windows
   (unused import libs add no DLL import; §8, §11.4).
5. A scratch shim set implementing the design links hello, z9play, and z9torr
   with `-nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32` (+winmm/wsock32),
   imports only KERNEL32 (+WINMM or WSOCK32), and runs under Wine (§11).
6. The safe `.bat`/`.owc` decision is **CRT, no `ZIG_NO_CRT`** (§8, §13 C1):
   those scripts do not use the mingw no-CRT link, and defining the profile
   macro there would collide with the CRT's own `exit`/`atexit`/`strlen`/...
   The plan's "CRT path behavior unchanged" requires this.

---

## 1. Shim placement & ownership

### 1.1 Ownership table

All files below are emitted into the program's output directory. "Guard" is the
preprocessor condition around the definition.

| Symbol(s) | Owner | Guard | Why |
|:--|:--|:--|:--|
| `c_exit`, `exit`, `atexit` (+ registry) | `c_exit.c` | `_WIN32 && ZIG_NO_CRT` for `exit`/`atexit`; `c_exit` always | Process-exit path is one cohesive unit; `@exit` emits `exit` (`sf/src/c89_emit.zig:7726-7733`), so the no-CRT `exit` must exist. `c_exit` already owns termination. |
| `pal_file_size`, `pal_file_seek64`, `pal_file_mtime` | `zig_pal.c` | `_WIN32` (helper itself splits on `ZIG_WIN_NT`) | Plan-named PAL helpers; same file/surface as existing `pal_file_*` (`sf/src/include/zig_pal.c:240-295`). |
| `pal_getenv`, `pal_wallclock_unix` | `zig_pal.c` | `_WIN32` | Plan-named PAL replacements for `getenv`/`time`; static buffer ownership belongs to the PAL. |
| `mainCRTStartup`, `__main`, argc/argv parser | `zig_pal.c` | `_WIN32 && ZIG_NO_CRT` | Entry/startup support already lives there (`sf/src/include/zig_pal.c:348-355`). |
| `strlen`, `memcpy`, `strncmp` | `zig_runtime.c` | `_WIN32 && ZIG_NO_CRT` | Runtime library is the existing owner of `std_panic`/`std_print` string use (`sf/src/include/zig_runtime.c:14-24`). |
| `__acrt_iob_func`, `fwrite`, `getchar`, `putchar` | **new** `zig_nocrt.c` | `_WIN32 && ZIG_NO_CRT` | CRT-emulation layer; keeps stdio emulation out of PAL/runtime and makes the emitted tree self-contained. Also owns the no-CRT `getenv`/`_time32`/`time` wrappers over the PAL helpers. |
| `_iob` | not defined | n/a | Not referenced by emitted code (see §3.2); defining it would be dead. |
| `__imp____acrt_iob_func`, `__imp___time32` import pointers | `zig_nocrt.c` | `_WIN32 && ZIG_NO_CRT` | mingw headers declare these as `dllimport`; the emitted objects reference the import pointer, not the function (§3.2, §5.1). |

`c_exit.c` remains tiny and unchanged on the CRT path; `zig_nocrt.c` is an empty
translation unit outside `_WIN32 && ZIG_NO_CRT` (one dummy typedef), so Linux and
nt builds compile it harmlessly.

### 1.2 Header/prototype placement (C89, `-Wall`, no implicit declarations)

| Prototype | Header | Notes |
|:--|:--|:--|
| `int pal_file_size(void* h, i64* out);` | `sf/src/include/std_os_prelude.h` under `_WIN32` | `std_file`/`std_file_pal` both `@cInclude("<std_os_prelude.h>")` (`sf/src/std_file.zig:21`, `sf/src/std_file_pal.zig:15`). |
| `int pal_file_seek64(void* h, i64 d, i64* np, u32 method);` | `std_os_prelude.h` under `_WIN32` | same. |
| `int pal_file_mtime(const char* path, i64* out);` | `std_os_prelude.h` under `_WIN32` | same. |
| `const char* pal_getenv(const char* name);` | `std_os_prelude.h` under `_WIN32` | `std_os`/`std_os_pal` include it (`sf/src/std_os.zig:16`, `sf/src/std_os_pal.zig:12`). |
| `i64 pal_wallclock_unix(void);` | `sf/src/include/std_time_prelude.h` under `_WIN32` | `std_time`/`std_time_pal` include it (`sf/src/std_time.zig:19`, `sf/src/std_time_pal.zig:13`). |
| `extern const char* pal_getenv(const char*);` / `extern long long pal_wallclock_unix(void);` | local externs at the top of `zig_nocrt.c` | keeps the shim TU self-contained. |
| `int main(int argc, char** argv);` / `void exit(int);` | local in `zig_pal.c` under no-CRT | `exit` also comes from `<stdlib.h>`, included in the no-CRT block. |

Every prototype is placed after `zig_compat.h` (all emitted module headers
include it first), so `i64`/`u32` are defined. The new `zig_nocrt.c` definitions
are self-contained and were compiled with `-std=c89 -Wall` with zero warnings
(§11.1).

### 1.3 Duplicate-definition / symbol-clash analysis

The rule is: **every CRT-emulation/replacement definition (`exit`, `atexit`,
`__acrt_iob_func`, `fwrite`, `getchar`, `putchar`, `getenv`, `_time32`, `time`,
`strlen`, `memcpy`, `strncmp`, `__main`) is inside `#ifdef ZIG_NO_CRT`; only the
mingw 9x `.sh` build defines it.** The `pal_file_*`/`pal_getenv`/
`pal_wallclock_unix` helpers are ordinary `_WIN32` PAL functions (used by both
profiles) and have no CRT names, so they cannot collide.

| Build | `ZIG_NO_CRT`? | Link | Result |
|:--|:--|:--|:--|
| mingw `-osw` 9x (`build_target.sh`) | **yes** | `-nostdlib -Wl,-e,_mainCRTStartup -lgcc -lkernel32 ...` | No CRT objects/default libraries; shims are the only definitions. |
| mingw `-osw nt` | no | normal mingw CRT | Shims are preprocessed out; CRT `exit`/`atexit`/`fwrite`/`time`/`getenv` remain. Unchanged behavior. |
| Linux (`-osl`) | no | normal gcc | `zig_nocrt.c` is an empty TU; `zig_runtime.c`/`c_exit.c`/`zig_pal.c` no-CRT blocks are out. Unchanged behavior. |
| `.bat` (MSVC) 9x | **no** (safe decision, §13 C1) | CRT (`kernel32.lib` + default CRT libs) | CRT symbols used; Win95-safe `pal_file_*` helpers are selected by the *absence* of `ZIG_WIN_NT`. |
| `.owc` (OpenWatcom) 9x | **no** (§13 C1) | CRT (`wlink` default libs) | same. |
| `.bat`/`.owc` nt | no (plus `ZIG_WIN_NT`) | CRT | modern `pal_file_*` path; unchanged CRT behavior. |

Why not define `ZIG_NO_CRT` in `.bat`/`.owc` while still linking CRT: MSVC/
OpenWatcom startup pulls the CRT's `atexit` (from the startup object) and the
import libraries provide `exit`/`fwrite`/`strlen`/...; defining the shims would
produce `LNK2005`/duplicate-definition errors, and `c_exit` would switch to
`ExitProcess` while CRT startup still runs. That is exactly the "CRT path
behavior unchanged" the plan forbids. See §13 C1 for the STOP-present wording.

---

## 2. `atexit` (no-CRT registry)

### 2.1 Design

Owner: `sf/src/c_exit.c` (under `_WIN32 && ZIG_NO_CRT`), mirrored in
`sf/src/emit_support.zig:194-197`.

```c
#include <stdlib.h>
#if defined(_WIN32) && defined(ZIG_NO_CRT)
#include <windows.h>
#define ZIG_ATEXIT_MAX 32
typedef void (*zig_atexit_fn)(void);
static zig_atexit_fn g_atexit_fns[ZIG_ATEXIT_MAX];
static int g_atexit_count = 0;
static int g_exiting = 0;

int atexit(void (*func)(void)) {
    if (!func || g_exiting || g_atexit_count >= ZIG_ATEXIT_MAX) return -1;
    g_atexit_fns[g_atexit_count++] = func;
    return 0;
}

void exit(int code) {
    if (!g_exiting) {
        g_exiting = 1;
        while (g_atexit_count > 0) {
            zig_atexit_fn fn = g_atexit_fns[--g_atexit_count];
            fn();
        }
    }
    ExitProcess((UINT)code);
}
#endif
void c_exit(int code) { exit(code); }
```

- **Capacity:** 32 entries. z9play registers exactly one
  (`examples/z98/z9play/platform/console_win9x.zig:144-146`); 32 leaves room and
  matches common CRT practice.
- **Ordering:** LIFO (`--g_atexit_count`), per C `atexit`.
- **Registration signature/return:** `int atexit(void (*)(void))`; `0` success,
  `-1` on null/full/re-entrant-after-exit. The console backend already ignores
  the return (`_ = pal.atexit(...)`), so behavior is unchanged.
- **Invocation:** `exit(code)` runs the registry then `ExitProcess`; `c_exit`
  calls `exit`. Emitted `@exit` calls `exit` directly
  (`sf/src/c89_emit.zig:7726-7733`), so both paths are covered.
- **Normal `main` return:** `mainCRTStartup` must call `exit(main(argc, argv))`,
  not `ExitProcess` (§1.1, §11.3). This preserves the CRT-era contract that a
  normal return runs `atexit`.
- **Bypass disclosed:** `TerminateProcess` (used by `pal_abort`,
  `sf/src/include/zig_pal.c:126-133`), `pal_trap`'s `int3`
  (`sf/src/include/zig_pal.c:135-166`), unhandled exceptions, and console
  close/shutdown do **not** run the registry. These are termination paths, not
  `exit` paths; z9play's `leaveRaw` is still the explicit restore and
  `atexit` is only the backstop. Documented as a known limitation.
- **Re-entrancy:** a handler calling `exit` sees `g_exiting == 1` and proceeds
  straight to `ExitProcess`; remaining handlers do not run. C leaves
  handler-registration-during-exit undefined; this is the deterministic safe
  choice.
- **Single-threaded assumption:** no locking, no atomics. Z98's runtime and the
  z9play/z9torr schedulers are cooperative on one OS thread.

### 2.2 z9play backstop unchanged

`console_win9x.zig:144-146` still calls `pal.atexit(restoreAtExit)` exactly once
(`g_atexit_installed`); `console_win9x_pal.zig:112` still declares
`extern "c" fn atexit(func: fn () void) i32`. No example source change is
needed: the no-CRT `atexit` in `c_exit.c` satisfies the existing declaration.

---

## 3. std streams

### 3.1 `__acrt_iob_func` / `_iob`

Emitted `std_io`/`scheduler`/`std_async` use the mingw `<stdio.h>` macros
`stdout`/`stderr`, which expand to `__acrt_iob_func(1/2)`:

```sh
$ sed -n '127,129p' /usr/i686-w64-mingw32/include/stdio.h
#define stdin (__acrt_iob_func(0))
#define stdout (__acrt_iob_func(1))
#define stderr (__acrt_iob_func(2))
```

`__acrt_iob_func` is declared `_CRTIMP` (dllimport), so emitted objects reference
the **import pointer**:
`std_io_*.o: __imp____acrt_iob_func` (§11.1). The cross_nocrt reference shim uses
an assembly import pointer for exactly this reason
(`scripts/win32_cross/cross_nocrt.sh:151-155`).

Design in `zig_nocrt.c`:

```c
typedef struct _z98_FILE FILE;          /* opaque, never dereferenced */
static char g_iob[3];
FILE* __acrt_iob_func(unsigned idx) {
    if (idx > 2u) return (FILE*)0;
    return (FILE*)&g_iob[idx];
}
__asm__(".section .data,\"w\"");
__asm__(".globl __imp____acrt_iob_func");
__asm__("__imp____acrt_iob_func:");
__asm__(".long ___acrt_iob_func");
```

`_iob` is **not** defined: the pinned mingw toolchain reaches the array only
through `__acrt_iob_func`, and `nm -u` shows only
`__imp____acrt_iob_func` — no `_iob` reference in any emitted object. The `_iob`
import in the current PE table comes from mingw's wrapper (T5.1 §3.2), not from
emitted code; under `-nostdlib` it disappears. If a future toolchain references
`_iob` directly, this decision must be re-probed.

### 3.2 `fwrite` / `getchar` / `putchar` parity

Design in `zig_nocrt.c` (`size_t` is `unsigned int` on i386; `FILE*` is the
opaque tag above):

```c
int fwrite(const void* p, unsigned int sz, unsigned int n, FILE* stream) {
    unsigned int total = sz * n, off = 0;
    HANDLE h;
    if (total == 0) return 0;                 /* no null check: avoids -Wnonnull-compare */
    h = GetStdHandle(stream == __acrt_iob_func(2u)
                        ? STD_ERROR_HANDLE : STD_OUTPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return 0;
    while (off < total) {
        DWORD chunk = (DWORD)(total - off), wrote = 0;
        if (!WriteConsoleA(h, (const char*)p + off, chunk, &wrote, NULL)) {
            if (!WriteFile(h, (const char*)p + off, chunk, &wrote, NULL)) return 0;
        }
        if (wrote == 0) return 0;
        off += (unsigned int)wrote;
    }
    return (int)n;
}
int getchar(void) { /* ReadFile(STD_INPUT_HANDLE, 1 byte) -> byte or -1 */ }
int putchar(int c) { /* one byte to STD_OUTPUT_HANDLE -> c or -1 */ }
```

- **Handles:** `STD_OUTPUT_HANDLE`, `STD_ERROR_HANDLE`, `STD_INPUT_HANDLE` via
  `GetStdHandle`, exactly like `pal_print_stdout/stderr`
  (`sf/src/include/zig_pal.c:85-113`) and the cross_nocrt reference
  (`cross_nocrt.sh:131-150`).
- **Win9x console vs redirected:** `WriteConsoleA` first, `WriteFile` fallback
  on failure; this handles both the console and redirected handles. `getchar`
  uses `ReadFile` on the input handle (works for console and redirected input;
  the console backend used by z9play uses Win32 input APIs, not `getchar`).
- **Buffering:** none. `fwrite` writes the whole slice immediately; the emitted
  `std_io` passes complete slices. This matches the existing unbuffered
  `pal_print_*` behavior and avoids an `fflush` surface. It is a documented
  difference from CRT stdio buffering.
- **Return values:** `fwrite` returns `n` on complete success, `0` on failure
  (the emitted callers ignore it); `getchar` returns the byte or `-1`;
  `putchar` returns `(unsigned char)c` or `-1`.
- **`stream` selection:** `stderr` is `__acrt_iob_func(2)`; any other stream
  goes to stdout. Emitted code only uses 1/2.

---

## 4. `memcpy` / `strlen` / `strncmp`

Owner: `sf/src/include/zig_runtime.c` under `_WIN32 && ZIG_NO_CRT`, mirrored in
`sf/src/emit_support.zig:488-677`; `<string.h>` is already included at
`zig_runtime.c:3`, so the standard declarations are visible and the definitions
need no implicit declarations.

```c
size_t strlen(const char* s) { const char* p = s; while (*p) p++; return (size_t)(p - s); }

void* memcpy(void* dst, const void* src, size_t n) {
    unsigned char* d = (unsigned char*)dst;
    const unsigned char* s = (const unsigned char*)src;
    if (d < s) { while (n--) *d++ = *s++; }
    else { d += n; s += n; while (n--) *--d = *--s; }
    return dst;
}

int strncmp(const char* a, const char* b, size_t n) {
    while (n--) {
        unsigned char ca = (unsigned char)*a++, cb = (unsigned char)*b++;
        if (ca != cb) return (int)ca - (int)cb;
        if (ca == 0) return 0;
    }
    return 0;
}
```

- **Overlap policy:** the shim is memmove-compatible (direction-aware), stronger
  than C `memcpy`'s non-overlap contract, so a compiler-generated overlapping
  copy cannot corrupt data. Probe: overlapping copy + `strncmp` + `strlen` ->
  `STRINGS_OK` (§11.1).
- **Who needs them:** z9torr `main_*.o`/`scheduler_*.o` reference `memcpy`;
  `zig_runtime.c:17,23` (`std_panic`/`std_print`) reference `strlen`;
  `strncmp` is not referenced by z9play/z9torr but is required for general
  emitted code by T5.3 (T5.1 §4.8). No separate copy for `zig_runtime` is
  needed: the runtime defines `strlen` before/after use in the same TU and the
  header declaration makes the call valid.

---

## 5. time

### 5.1 Which symbol the emitted C actually calls (proved)

Emitted source calls `time(...)`:

```sh
$ grep -n "time(zT_0)" /tmp/t53a_z9play/std_time_31F0EC27.c
166:    zT_2 = time(zT_0);
```

But mingw's `<time.h>` defines `time` as a static inline wrapper over the
dllimport `_time32`:

```sh
$ sed -n '232p' /usr/i686-w64-mingw32/include/time.h
static __inline time_t __CRTDECL time(time_t *_Time) { return _time32(_Time); }
$ i686-w64-mingw32-nm -u /tmp/t53a_z9play/std_time_31F0EC27.o | grep -i time
         U __imp___time32
$ i686-w64-mingw32-objdump -dr /tmp/t53a_z9play/std_time_31F0EC27.o | grep -A2 __imp___time32
			e9a: dir32	__imp___time32
```

So the **link symbol is `__time32`** (C `_time32`, COFF `__time32`) via import
pointer `__imp___time32`, not a direct `time` call. T5.1's `__time32` note is
correct; this probe pins the exact COFF spelling.

### 5.2 No-CRT provider(s)

Primary provider for `std.time`: `pal_wallclock_unix` in `zig_pal.c`:

```c
i64 pal_wallclock_unix(void) {
    FILETIME ft;
    u64 ticks;
    GetSystemTimeAsFileTime(&ft);
    ticks = ((u64)ft.dwHighDateTime << 32) | (u64)ft.dwLowDateTime;
    return (i64)(ticks / 10000000ULL) - 11644473600LL;
}
```

- `GetSystemTimeAsFileTime` is a Win95 (3.51+) KERNEL32 export (T5.1 §4;
  whitelist row). It returns UTC.
- FILETIME epoch is 1601-01-01; Unix epoch is 11644473600 seconds later. Ticks
  per second are 10,000,000. `ticks` is built as unsigned 64-bit (high << 32 |
  low); division is unsigned 64-bit then converted to signed `i64`, so dates
  before 1970 yield a negative Unix value. Current dates are far below the i64
  limit.
- `std_time.zig:115-118` becomes: Windows → `pal.pal_wallclock_unix()`, else
  `pal.time(nullVoid())` (POSIX unchanged). `std_time_pal.zig:50-51` keeps
  `time` for POSIX and adds `pub extern "c" fn pal_wallclock_unix() i64;`.
- General emitted-code shim: `zig_nocrt.c` defines `_time32` and an alias
  `time`, both calling `pal_wallclock_unix`, plus the import pointer:

```c
long _time32(long* t) { long v = (long)pal_wallclock_unix(); if (t) *t = v; return v; }
long time(long* t) { return _time32(t); }
__asm__(".section .data,\"w\"");
__asm__(".globl __imp___time32");
__asm__("__imp___time32:");
__asm__(".long __time32");
```

The `time` alias is unused under the pinned mingw headers (the inline wrapper
wins) but covers a non-mingw direct `time` reference; defining it in a TU that
does not include `<time.h>` avoids any declaration conflict. `_time32` is
32-bit `time_t`; `_USE_64BIT_TIME_T` would reference `_time64` instead and is
not part of the emitted recipe.

Probe: `GetSystemTimeAsFileTime` conversion returned a positive Unix value
(`TIME_POS=1`) under Wine (§11.3).

---

## 6. env

### 6.1 Design

Owner: `pal_getenv` in `sf/src/include/zig_pal.c` under `_WIN32`; mirrored in
`emit_support.zig:679-1037`.

```c
const char* pal_getenv(const char* name) {
    static char g_env_buf[32768];
    DWORD n;
    if (!name) return 0;
    SetLastError(0);
    n = GetEnvironmentVariableA(name, g_env_buf, (DWORD)sizeof g_env_buf);
    if (n == 0) {
        if (GetLastError() == ERROR_ENVVAR_NOT_FOUND) return 0;
        return g_env_buf;                 /* existing but empty value */
    }
    if (n >= (DWORD)sizeof g_env_buf) return 0;  /* truncated: treat as unset */
    return g_env_buf;
}
```

- **Size:** 32768 bytes. Windows environment-variable values are limited to
  32767 characters plus NUL; this buffer covers the documented maximum. It is
  static BSS, not stack, so the returned pointer survives the call.
- **NUL handling:** `GetEnvironmentVariableA` writes a NUL when it fits; `n` is
  the length excluding NUL. `std_os.env` already scans to the NUL
  (`sf/src/std_os.zig:75-78`).
- **Not found:** `n == 0` and `GetLastError() == ERROR_ENVVAR_NOT_FOUND` →
  `NULL`; `std_os.env` returns `null`.
- **Empty value:** `n == 0` and no not-found error → pointer to `""`;
  `std_os.env` returns an empty slice, matching CRT `getenv` for `NAME=`.
- **Truncation:** if the required size is `>= sizeof g_env_buf`, return `NULL`
  rather than a silently truncated value.
- **Slice lifetime:** the returned slice points into the one static PAL buffer,
  so it is valid until the **next** `std.os.env`/`pal_getenv` call (or process
  exit). The current CRT path returns a pointer into the process environment
  block, valid for the process. This is the one contract narrowing; it is safe
  for the committed callers (immediate use in z9play/z9torr) under the
  single-threaded assumption, and is exactly the "static PAL buffer
  (single-threaded)" design in Amendment 3. Documented in §13 C3.
- **Single-threaded:** no locking; one static buffer.

### 6.2 Wiring

- `sf/src/std_os_pal.zig:23-24` keeps `getenv` for POSIX and adds
  `pub extern "c" fn pal_getenv(name: [*]const u8) ?[*]const u8;`.
- `sf/src/std_os.zig:66-81` branches: Windows → `pal.pal_getenv(...)`; else
  `pal.getenv(...)`. The name copy/`ENV_NAME_MAX` check is unchanged.
- `zig_nocrt.c` also defines a `getenv` wrapper for arbitrary emitted code:
  `char* getenv(const char* name) { return (char*)pal_getenv(name); }`.
  `std_os` itself no longer needs it, but the no-CRT link is then complete even
  if another module calls `getenv`.
- Prototype in `std_os_prelude.h` under `_WIN32` (§1.2).

Probe: `ENV=hello MISS=(null) TIME_POS=1` under Wine (§11.3).

---

## 7. `std_file` helpers

### 7.1 Exact signatures and wiring

`sf/src/include/zig_pal.c` under `_WIN32`:

```c
int pal_file_size(void* handle, i64* out);
int pal_file_seek64(void* handle, i64 distance, i64* new_pos, u32 method);
int pal_file_mtime(const char* path, i64* out);
```

Return `1` on success, `0` on failure (BOOL), matching the
`SetFilePointerEx`/`GetFileSizeEx`/`GetFileAttributesExA` BOOL contract. `i64`
is the existing `zig_compat.h` type. `method` is `SEEK_SET/_CUR/_END` (0/1/2).

`sf/src/std_file_pal.zig` removes the three Win32 stdcall externs
(`SetFilePointerEx` at `:26`, `GetFileSizeEx` at `:28`,
`GetFileAttributesExA` at `:39`) and adds:

```zig
pub extern "c" fn pal_file_size(h: *void, size_out: *i64) i32;
pub extern "c" fn pal_file_seek64(h: *void, distance: i64, new_pos: *i64, method: u32) i32;
pub extern "c" fn pal_file_mtime(path: [*]const u8, unix_seconds_out: *i64) i32;
```

**`extern "c"` is mandatory, not cosmetic.** The emitted call is a function
pointer cast; with `extern "stdcall"` the cast is `Z98_STDCALL` and calling a
cdecl C helper through it corrupts the i386 stack. Probe: after merely renaming
the calls in a scratch copy while leaving the stdcall typedefs, z9play/z9torr
crashed in Wine; after changing those three typedefs to cdecl (the effect of
`extern "c"`), both ran (§11.2). The C helpers are cdecl.

`sf/src/std_file.zig` changes:

- `seekHandle` (`:223-234`): `pal.pal_file_seek64(h, offset, &np, @intCast(u32, whence))`; return `np`.
- `sizeHandle` (`:236-245`): `pal.pal_file_size(h, &sz)`; return `sz`.
- `mtime` (`:311-331`): Windows → `pal.pal_file_mtime(path, &mt)`; return `mt`.
  POSIX `stat`/`leU32At` path unchanged.
- Remove the now-unused Windows constants `WIN_FILE_ATTR_BYTES`,
  `WIN_FT_LASTWRITE_OFF`, `GET_FILEEX_INFO_STANDARD`,
  `FILETIME_TICKS_PER_SEC`, `WINDOWS_EPOCH_DELTA_SECS`
  (`sf/src/std_file.zig:94-104`); `leU32At` and `STAT_MTIME_OFFSET` stay for
  POSIX.

Error semantics are unchanged: helper `0` maps to `error.SeekFailed` /
`error.SizeFailed` / `error.OpenFailed`, exactly as the current `== 0` checks.

### 7.2 Default Win95 path vs `#ifdef ZIG_WIN_NT`

`pal_file_size`:

```c
#ifdef ZIG_WIN_NT
    LARGE_INTEGER li;
    if (!GetFileSizeEx((HANDLE)handle, &li)) return 0;
    *out = (i64)li.QuadPart; return 1;
#else
    DWORD lo, hi;
    SetLastError(0);
    lo = GetFileSize((HANDLE)handle, &hi);
    if (lo == INVALID_FILE_SIZE && GetLastError() != ERROR_SUCCESS) return 0;
    *out = ((i64)hi << 32) | (i64)lo; return 1;
#endif
```

`GetFileSize` returns the low DWORD and writes the high DWORD; `INVALID_FILE_SIZE`
(0xFFFFFFFF) is also a legal size, so the `SetLastError(0)` +
`GetLastError() == ERROR_SUCCESS` disambiguation is required. This preserves the
`i64` contract and supports >4 GiB paths (Win98 FAT32 itself caps at 4 GiB, but
the API path is correct).

`pal_file_seek64`:

```c
#ifdef ZIG_WIN_NT
    LARGE_INTEGER d, np;
    d.QuadPart = distance;
    if (!SetFilePointerEx((HANDLE)handle, d, &np, (DWORD)method)) return 0;
    *new_pos = (i64)np.QuadPart; return 1;
#else
    LONG high = (LONG)((u64)distance >> 32);
    DWORD low = (DWORD)((u64)distance & 0xFFFFFFFFu);
    DWORD r;
    SetLastError(0);
    r = SetFilePointer((HANDLE)handle, (LONG)low, &high, (DWORD)method);
    if (r == INVALID_SET_FILE_POINTER && GetLastError() != ERROR_SUCCESS) return 0;
    *new_pos = ((i64)high << 32) | (i64)r; return 1;
#endif
```

The i64 distance is split into low/high DWORDs; the high DWORD is built from the
unsigned bit pattern and passed as signed `LONG`, which is the required
sign-extension for negative `FILE_CURRENT`/`FILE_END` offsets. The returned low
DWORD plus the out high DWORD are recombined. `INVALID_SET_FILE_POINTER` is
disambiguated with `SetLastError` exactly like `GetFileSize`.

`pal_file_mtime`:

```c
#ifdef ZIG_WIN_NT
    WIN32_FILE_ATTRIBUTE_DATA info;
    if (!GetFileAttributesExA(path, GetFileExInfoStandard, &info)) return 0;
    ticks = high<<32 | low from info.ftLastWriteTime;
#else
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(path, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    FindClose(h);
    ticks = high<<32 | low from fd.ftLastWriteTime;
#endif
    *out = (i64)(ticks / 10000000ULL) - 11644473600LL; return 1;
```

**Mtime source decision: `FindFirstFileA`, not `CreateFileA` + `GetFileTime`.**
Evidence:

- MinGW-w64's own Win95 compatibility shim implements `GetFileAttributesEx`
  with `FindFirstFile` and copies `WIN32_FIND_DATA` into
  `WIN32_FILE_ATTRIBUTE_DATA` one-for-one, including `ftLastWriteTime`
  (`/usr/i686-w64-mingw32/include/newapis.h:193-219`; observed with
  `sed -n '190,225p'`). This is the maintainers' documented recipe.
- Both structs hold `FILETIME` at the same offset: `dwFileAttributes` 0,
  `ftCreationTime` 4, `ftLastAccessTime` 12, `ftLastWriteTime` 20; the existing
  `WIN_FT_LASTWRITE_OFF = 20` is valid for either.
- Availability: `FindFirstFileA` and `GetFileTime` are both Win95 (3.51+);
  `GetFileAttributesExA` is NT 4.0 only (T5.1 §4, export study). The choice is
  semantic: `FindFirstFileA` needs no open handle/share mode, works for
  directories, and the mtime capability only needs the path. `CreateFileA` +
  `GetFileTime` fails on directories and locked files and costs a handle.
- Caveats documented: `FindFirstFileA` treats `*`/`?` as wildcards and is
  subject to `MAX_PATH`; z9torr passes concrete payload paths
  (`resume.zig:201,318` in T5.1 §4.3), so the committed use is safe. The helper
  comment must record the difference.

Probe (default Win95 path) under Wine: a scratch test wrote a file, then
`pal_file_size` → 3, `pal_file_seek64(1)` → 1, `pal_file_mtime` → positive Unix
seconds: `SIZE=3 POS=1 MTIME_POS=1`; the same test with `-DZIG_WIN_NT` also
passed (§11.3).

---

## 8. Build recipe

### 8.1 `build_target.sh` (mingw; the committed no-CRT gate)

9x (default, `win_profile == .win9x`):

```sh
CFLAGS="-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
 -Wno-implicit-function-declaration -DZIG_NO_CRT -I ."
LDFLAGS="-m32 -nostdlib -Wl,-e,_mainCRTStartup"
LIBS="-lgcc -lkernel32 -lwinmm"          # + -lwsock32 iff net_emitted
```

and compile/link `zig_nocrt.c`/`zig_nocrt.o` in addition to
`zig_runtime`/`zig_pal`/`c_exit`.

nt (`win_profile == .nt`):

```sh
CFLAGS="-m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign \
 -Wno-implicit-function-declaration -DZIG_WIN_NT -I ."
LDFLAGS="-m32"
LIBS="-lwinmm"                            # + -lwsock32 iff net_emitted
```

No `-nostdlib`, no `exit`/`mainCRTStartup` override; CRT startup handles
argc/argv and `exit`/`atexit`.

Linux branch: unchanged. `zig_nocrt.c` is emitted and compiled as an empty TU;
it is harmless. (If T5.3 prefers not to carry the empty object on Linux, the
emitter can gate the compile line by profile; the design does not require it.)

Rationale for `-lwinmm` unconditional on Windows: z9play's reachable
`audio_win9x` backend references `waveOut*`; the current emitted `LIBS=""` makes
`-osw nt` z9play fail to link (probe §11.4). An import library only pulls member
objects for still-undefined symbols, so adding `-lwinmm` to z9torr does not add a
WINMM import (probe: z9torr 9x imports only KERNEL32 + WSOCK32).

`-lwsock32` is the Winsock 1.1 import library and produces `WSOCK32.DLL`, which
is what z9torr actually imports (T5.1 §1.4: `WSOCK32.DLL`). It is **not**
`ws2_32`; keep the existing `net_emitted` gate and naming. For MSVC the existing
`wsock32.lib` and `net_prelude.h`'s `#pragma comment(lib, "wsock32.lib")` agree.

### 8.2 `build_target.bat` / `build_owc.bat`

- **9x:** keep the CRT build. Add `winmm.lib` (MSVC) / `library winmm`
  (OpenWatcom) and, if `net_emitted`, `wsock32.lib` / `library wsock32`. Add
  `zig_nocrt.c` to the compile list (empty TU) for file-set consistency. Do
  **not** add `/DZIG_NO_CRT` (§13 C1).
- **nt:** add `/DZIG_WIN_NT` / `/dZIG_WIN_NT` as today; same winmm/wsock32
  libs; normal CRT link.
- Their native CRT links are not the committed no-CRT gate and will import
  msvcrt; the 9x whitelist applies to the mingw `build_target.sh` artifacts.
  This is the T5.1 §8 proposal plus the safety correction in §13 C1.

### 8.3 Exact T5.3 changes (file:line)

`sf/src/c89_emit.zig`:

- `emitBuildTargetSh` `:8537-8574`: profile-dependent CFLAGS/LDFLAGS/LIBS;
  `-DZIG_NO_CRT` + `-nostdlib -Wl,-e,_mainCRTStartup` + `-lgcc -lkernel32` for
  9x; add `-lwinmm` (+wsock32); add `zig_nocrt.c`/`.o`.
- `emitBuildTargetBat` `:8576-8603`: add winmm.lib/wsock32.lib; add
  `zig_nocrt.c` compile/`.obj`; no `/DZIG_NO_CRT` for 9x.
- `emitBuildOwcBat` `:8605-8654`: add `library winmm`/`library wsock32`; add
  `zig_nocrt.c`; no `/dZIG_NO_CRT` for 9x.
- `emitBuildScripts` `:8656-8675`: unchanged signature/forwarding (already has
  `win_profile`).

---

## 9. `emit_support.zig` ↔ `sf/src/include/*` mirror map

The `emit_support.zig` literal is the source of truth; the canonical file is the
mirror compared byte-for-byte by `check_emit_support.sh` (T5.1 §5).

| `emit_support.zig` block (current lines) | Emitted file | Canonical mirror | Change |
|:--|:--|:--|:--|
| `emitStdOsPreludeHSupport` (114-129) | `std_os_prelude.h` | `sf/src/include/std_os_prelude.h` | add `pal_file_*` + `pal_getenv` prototypes under `_WIN32`. |
| `emitStdTimePreludeHSupport` (131-192) | `std_time_prelude.h` | `sf/src/include/std_time_prelude.h` | add `pal_wallclock_unix` prototype under `_WIN32`. |
| `emitCExitCSupport` (194-197) | `c_exit.c` | `sf/src/c_exit.c` | replace with guarded registry/`exit`/`c_exit` block (§2). |
| **new** `emitZigNocrtCSupport` (insert after 197) | `zig_nocrt.c` | **new** `sf/src/include/zig_nocrt.c` | streams, `getenv`/`time` wrappers, import pointers (§3-§6). |
| `emitZigRuntimeCSupport` (488-677) | `zig_runtime.c` | `sf/src/include/zig_runtime.c` | append no-CRT `strlen`/`memcpy`/`strncmp` (§4). |
| `emitZigPalCSupport` (679-1037) | `zig_pal.c` | `sf/src/include/zig_pal.c` | add `pal_file_*`/`pal_getenv`/`pal_wallclock_unix`/argv parser/`__main`; change `mainCRTStartup` literal at 1027-1034. |
| `emitZigCompatHSupport` (17-77) | `zig_compat.h` | `sf/src/include/zig_compat.h` | no change expected. |
| `emitZigRuntimeHSupport` (199-486) | `zig_runtime.h` | `sf/src/include/zig_runtime.h` | no change expected. |

`sf/src/c89_emit.zig:emitSupportFiles` (789-854): add the
`emitZigNocrtCSupport` call after `c_exit.c`.

`scripts/check_emit_support.sh`: add
`check zig_nocrt.c "$ROOT/sf/src/include/zig_nocrt.c"` to the core set (after
line 59) and change the final message (line 135) to **8/8 support files (6 core
+ 2 conditional preludes)**. No new fixture is needed because `zig_nocrt.c` is
always emitted.

---

## 10. Whitelist gate artifact

### 10.1 Script design

New file: `scripts/win32_cross/check_win9x_imports.sh`.

```
usage: check_win9x_imports.sh <exe> <9x|nt>
```

Inputs: one PE32 i386 exe (the artifact produced by the emitted
`build_target.sh mingw`), and the profile. It runs:

```sh
file "$EXE" | grep -q 'PE32 executable.*Intel 80386'
i686-w64-mingw32-objdump -p "$EXE"
```

extracts `DLL Name:` and the per-DLL import rows, normalizes DLL names to
uppercase, and compares against embedded tables. Output is per-DLL
`PASS`/`FAIL` plus the offending names; exit 0 only if all pass. Unknown DLLs
and unknown imports are failures (the gate is deliberately closed-world).

### 10.2 9x table (min-OS noted)

Policy: KERNEL32/WINMM/WSOCK32 only; **no msvcrt**. Names marked `95` are
Win95/98/Me exports; the three `Ex`/`ExA` names are excluded.

`KERNEL32.dll` (9x-allowed, all min 95):
`CloseHandle, CreateFileA, DeleteCriticalSection, DeleteFileA,
EnterCriticalSection, ExitProcess, FillConsoleOutputCharacterA, FindClose,
FindFirstFileA, FlushFileBuffers, FreeLibrary, GetCommandLineA,
GetConsoleCursorInfo, GetConsoleMode, GetConsoleScreenBufferInfo,
GetCurrentDirectoryA, GetCurrentProcess, GetEnvironmentVariableA,
GetFileAttributesA, GetFileSize, GetFileType, GetLastError, GetModuleFileNameA,
GetModuleHandleA, GetNumberOfConsoleInputEvents, GetProcAddress, GetStartupInfoA,
GetStdHandle, GetSystemTimeAsFileTime, GetTickCount, InitializeCriticalSection,
LeaveCriticalSection, LoadLibraryA, MoveFileA, QueryPerformanceCounter,
QueryPerformanceFrequency, ReadConsoleInputA, ReadFile, SetConsoleCursorInfo,
SetConsoleCursorPosition, SetConsoleMode, SetFilePointer, SetLastError,
SetUnhandledExceptionFilter, Sleep, TerminateProcess, TlsGetValue,
VirtualProtect, VirtualQuery, WriteConsoleA, WriteFile`.

Explicit 9x **FAIL** rows (must not appear): `GetFileAttributesExA` (NT 4.0),
`GetFileSizeEx` (2000/XP), `SetFilePointerEx` (2000/XP).

`WINMM.dll` (min 95): `waveOutClose, waveOutOpen, waveOutPrepareHeader,
waveOutReset, waveOutUnprepareHeader, waveOutWrite`.
`WSOCK32.dll` (min 95, Winsock 1.1): `WSACleanup, WSAGetLastError, WSAStartup,
accept, bind, closesocket, connect, gethostbyname, getsockopt, htonl, htons,
ioctlsocket, listen, recv, recvfrom, select, send, sendto, setsockopt, socket`.

`msvcrt.dll`: **FAIL for 9x by policy**, even though msvcrt exists on 9x. This
is the no-CRT policy, not an export-availability question (T5.1 §7.2).

### 10.3 nt table (min-OS noted)

KERNEL32 = the 9x list plus `GetFileAttributesExA` (NT4), `GetFileSizeEx`
(2000/XP), `SetFilePointerEx` (2000/XP). `msvcrt.dll` = the 28 names in
T5.1 §7.2 (all pass; CRT). WINMM/WSOCK32 as above. Unknown names fail.

### 10.4 Where it runs

- **T5.3:** on hello, z9play, z9torr built with the emitted 9x
  `build_target.sh` (not the CRT `cross_build_run.sh`), and optionally the nt
  builds to confirm the profile table.
- **T5.4:** z9torr default 9x.
- **T5.5:** z9play default 9x; integrate into `tier_win9x.sh` replacing the
  current DLL-only check (`examples/z98/z9play/tests/tier_win9x.sh:162-173`).
- **Do not** run the 9x profile on `cross_build_run.sh` outputs: that harness
  links the CRT (`scripts/win32_cross/cross_build_run.sh:104-107`) and is not a
  no-CRT artifact. T5.5 must either switch the tier to the emitted
  `build_target.sh` or add a no-CRT harness path.

The whitelist is the loadability gate because Windows 9x resolves the whole
import table at load time; Wine is not a Win98 loader (T5.1 §10 concern 8).

---

## 11. Probes, observed evidence, and residual risks

All probes use `/tmp` copies. No repo source was edited.

### 11.1 (a) Reproduce the current no-CRT unresolved symbols

Dump with the post-T5.2 compiler (fresh, pre-created output dirs):

```sh
$ /tmp/t52/zig1_5_clean -osw --dump-c89 --output-dir /tmp/t53a_z9play examples/z98/z9play/main.zig
$ echo $?
0
$ /tmp/t52/zig1_5_clean -osw --dump-c89 --output-dir /tmp/t53a_z9torr examples/z98/z9torr/main.zig
$ echo $?
0
$ /tmp/t52/zig1_5_clean -osw --dump-c89 --output-dir /tmp/t53a_hello examples/z98/hello/main.zig
$ echo $?
0
```

Compile every emitted `.c` with `-DZIG_NO_CRT` and list undefined symbols
(excluding `zF_*`/`zT_*` and libgcc helpers). Key rows:

```text
c_exit.o: _exit
std_io_*.o: __imp____acrt_iob_func, _fwrite, _getchar, _putchar
std_os_*.o: _exit, _getenv
std_time_*.o: __imp___time32
zig_runtime.o: _strlen
z9torr main_*.o: ___main, _memcpy
z9torr scheduler_*.o: __imp____acrt_iob_func, _fwrite, _memcpy
z9torr std_async_*.o: __imp____acrt_iob_func, _fwrite
console_win9x_*.o: _atexit
```

Link without the shim (z9play shown; z9torr is the same plus `memcpy`):

```text
ld: c_exit.o: undefined reference to `exit'
ld: console_win9x_*.o: undefined reference to `atexit'
ld: std_io_*.o: undefined reference to `putchar'
ld: std_io_*.o: undefined reference to `_imp____acrt_iob_func'
ld: std_io_*.o: undefined reference to `fwrite'
ld: std_io_*.o: undefined reference to `getchar'
ld: std_os_*.o: undefined reference to `exit'
ld: std_os_*.o: undefined reference to `getenv'
ld: std_time_*.o: undefined reference to `_imp___time32'
ld: zig_runtime.o: undefined reference to `strlen'
ld: libgcc.a(__main.o): undefined reference to `atexit'
link_rc=1
```

This matches T5.1 §3.3 and confirms `__main` is part of the required set even
though T5.1's summary did not list it.

### 11.2 (b) Compile/link with the designed shim set; discover the argv gap

A scratch `/tmp/t53a_shim/nocrt_shim.c` implemented `strlen`, `memcpy`,
`strncmp`, `__acrt_iob_func` + import pointer, `fwrite`, `getchar`, `putchar`,
`getenv`, `atexit`, `exit`, `_time32` + `time` + import pointer, and `__main`.
It compiled `-Wall` clean after removing the redundant null check in `fwrite`
(0 warnings). Link results:

```text
hello:  rc=0  imports: KERNEL32.dll
z9play: rc=0  imports: KERNEL32.dll WINMM.DLL
z9torr: rc=0  imports: KERNEL32.dll WSOCK32.DLL
```

The current trees still contain the three XP/NT4 `std_file` imports because
T5.3 has not replaced them yet. A `/tmp` simulation replaced the three calls
with the designed `pal_file_*` helpers (and made the three call typedefs cdecl,
the effect of `extern "c"`). Compile/link and imports:

```text
z9play_sim: rc=0  KERNEL32.dll WINMM.DLL
  KERNEL32: CloseHandle CreateFileA DeleteFileA ExitProcess
  FillConsoleOutputCharacterA FindClose FindFirstFileA FlushFileBuffers
  GetCommandLineA GetConsoleCursorInfo GetConsoleMode
  GetConsoleScreenBufferInfo GetCurrentDirectoryA GetCurrentProcess
  GetEnvironmentVariableA GetFileAttributesA GetFileSize GetLastError
  GetModuleFileNameA GetNumberOfConsoleInputEvents GetStdHandle
  GetSystemTimeAsFileTime GetTickCount MoveFileA QueryPerformanceCounter
  QueryPerformanceFrequency ReadConsoleInputA ReadFile SetConsoleCursorInfo
  SetConsoleCursorPosition SetConsoleMode SetFilePointer SetLastError Sleep
  TerminateProcess WriteConsoleA WriteFile

z9torr_sim: rc=0  KERNEL32.dll WSOCK32.DLL
  KERNEL32: ... (same 9x set) + GetFileType
```

No `msvcrt`, no `GetFileAttributesExA`, no `GetFileSizeEx`, no
`SetFilePointerEx`.

**Argv crash before the fix.** The same z9play/z9torr sim executables crashed
under Wine because the stock `mainCRTStartup` called `main()` with no arguments:

```text
$ wine /tmp/t53a_z9play_sim.exe --help
rc=5
Unhandled exception: page fault on read access to 0xa30fc0b6
0x00409f1f ... (inside argAt, before usage)
```

Evidence chain: `sf/src/include/zig_pal.c:348-355` (`int main(void); ... main()`)
vs emitted `main_4D6BD2B8.c:4649` / `main_B8D622A5.c:3934` (`int main(int argc, char** argv)`). Adding a
`GetCommandLineA` parser and calling `main(g_argc, g_argv)` fixed it:

```text
$ wine /tmp/t53a_z9play_sim.exe --help
rc=0
usage: z9play <file.ogg> ...
$ wine /tmp/t53a_z9torr_sim.exe --help
rc=0
usage: z9torr [--help] ...
```

The parser probe with quoted/space-separated arguments:

```text
$ wine /tmp/t53a_shim/argv_test.exe alpha "b c" 'd"e'
4:alpha,b c,d"e,
```

The side-effect-only call through the stdcall typedef (before changing the three
typedefs to cdecl) also crashed under Wine; after the cdecl change the sims ran.
This is why `extern "c"` on the new `std_file` helpers is mandatory (§7.1).

### 11.3 (c) Wine behavior probes

```text
$ wine /tmp/t53a_hello_shim.exe
Hello, world!                                  rc=0

$ T53A_ENV=hello wine /tmp/t53a_shim/shim_test.exe
hello
TIME_OK
MEMOK
21                                             rc=0 (LIFO atexit: h2 then h1)

$ printf 'Z' | wine /tmp/t53a_shim/getchar_test.exe
Z\n                                            rc=0

$ wine /tmp/t53a_shim/atexit_return_test.exe
AX                                             rc=0 (normal main return runs atexit)

$ wine /tmp/t53a_shim/string_test.exe
STRINGS_OK                                     rc=0 (overlap + strncmp + strlen)

$ wine /tmp/t53a_shim/file_helpers_test.exe
SIZE=3 POS=1 MTIME_POS=1                       rc=0 (default GetFileSize/SetFilePointer/FindFirstFileA)
$ wine /tmp/t53a_shim/file_helpers_test_nt.exe
SIZE=3 POS=1 MTIME_POS=1                       rc=0 (ZIG_WIN_NT path)

$ T53A_ENV=hello wine /tmp/t53a_shim/env_time_test.exe
ENV=hello MISS=(null) TIME_POS=1               rc=0
```

The stream test exercised redirected stdout (Wine output to a file), the
`WriteFile` fallback, `fwrite`/`putchar`/`getenv`/`time`/`memcpy`/`strlen`/
`atexit`/`exit`. `getchar` was exercised through a pipe. `WriteConsoleA` was
exercised by `hello`/`--help` when Wine attached a console.

### 11.4 (d) CRT builds unaffected

```sh
$ cd /tmp/t53a_ntcheck && sh build_target.sh mingw hello_nt.exe
Built: hello_nt.exe                            rc=0
$ i686-w64-mingw32-objdump -p hello_nt.exe | sed -n 's/^[[:space:]]*DLL Name:[[:space:]]*//p'
KERNEL32.dll
msvcrt.dll
$ wine hello_nt.exe
Hello, world!                                  rc=0
```

`-osw nt` z9play initially failed (T5.1 concern 7):

```text
ld: audio_win9x_*.o: undefined reference to `_imp__waveOutClose@4'
... six waveOut* references ...
build_rc=1
```

After adding `-lwinmm` to the scratch copy of the emitted `build_target.sh`:

```text
build_rc=0
imports: KERNEL32.dll msvcrt.dll WINMM.DLL
$ wine z9play_nt.exe --help
rc=0  usage: z9play ...
```

This confirms the `-lwinmm` addition in §8 is required for both profiles and
does not change the 9x import set when the symbol is unused (z9torr sim imports
only KERNEL32 + WSOCK32).

### 11.5 Residual risks (disclosed, not hand-waved)

| Risk | Impact | Mitigation / status |
|:--|:--|:--|
| `atexit` bypass via `TerminateProcess`/`pal_trap`/unhandled exception | registry not run on crash/termination | documented; `leaveRaw` remains the explicit restore; registry is a backstop only (§2). |
| `atexit` re-entry | handlers after a handler calls `exit` do not run | `g_exiting` guard; deterministic safe choice; C leaves this undefined. |
| Capacity 32 | registration fails after 32 | return `-1` (C contract); capacity documented. |
| argv parser fidelity | MSVCRT quoting/backslash rules, 32 KiB/256-arg limits | implement the MSVCRT algorithm; truncate over-long command lines; probe with spaces/quotes. |
| Single-threaded static buffers (env/argv/atexit) | data race if threads added | Z98 runtime is single-threaded; documented. |
| `std_os.env` lifetime narrowed to next call | caller must not hold the slice across `env()` | static PAL buffer per Amendment 3; committed callers use it immediately; §13 C3. |
| `fwrite` unbuffered | differs from CRT stdio buffering; no `fflush` | emitted `std_io` writes whole slices; matches existing unbuffered `pal_print_*`; no `fflush` reference measured. |
| `getchar` via `ReadFile` | console line-input semantics depend on mode; not the z9play console path | cross_nocrt reference uses the same; z9play uses the Win32 console backend. |
| `FindFirstFileA` wildcard/MAX_PATH | path semantics differ from `GetFileAttributesExA` | concrete paths only in committed z9torr use; helper comment documents caveat. |
| `_time32` 2038 | 32-bit `time_t` wraps | same as pinned 32-bit CRT; `_USE_64BIT_TIME_T` not part of the recipe. |
| Import-pointer asm (`__imp____acrt_iob_func`, `__imp___time32`) | GCC/mingw-specific | pinned toolchain is mingw-w64 GCC 12; re-probe on toolchain change; MSVC/OWC use CRT. |
| `.bat`/`.owc` remain CRT | not 9x-clean artifacts | safe decision; committed 9x gate is the mingw `.sh`; §13 C1. |
| Win9x-only verification | Wine 8 is not Win98; export tables are the loadability gate | mechanical whitelist + manual Win98 test remains for T5.3's gate (T5.1 §10 concern 9). |
| `cross_nocrt.sh` excludes `c_exit.o` and supplies a scratch shim | after T5.3 it would duplicate/miss `exit`/`atexit` | T5.3 must update the harness to include `c_exit` and the emitted `zig_nocrt` shims (or keep it hello-only); see §12. |
| No-CRT `mainCRTStartup` prototype `int main(int,char**)` vs a program's `int main(void)` | ABI-compatible cdecl extra args; no link conflict across TUs | documented; both emitted main forms are cdecl. |
| Empty `zig_nocrt.c` on Linux/nt | extra empty object | one dummy typedef; `-Wall` clean; harmless. |

---

## 12. File:line inventory of every T5.3 edit (no edits made now)

### 12.1 Z98 sources

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/std_file.zig:94-104` | Remove Windows-only mtime/FILETIME constants (keep POSIX `STAT_MTIME_OFFSET`). |
| `sf/src/std_file.zig:223-234` | `seekHandle` Windows → `pal.pal_file_seek64`. |
| `sf/src/std_file.zig:236-245` | `sizeHandle` Windows → `pal.pal_file_size`. |
| `sf/src/std_file.zig:311-331` | `mtime` Windows → `pal.pal_file_mtime`; POSIX unchanged. |
| `sf/src/std_file_pal.zig:24-28` | Remove `SetFilePointerEx`/`GetFileSizeEx` stdcall externs; add `pal_file_size`/`pal_file_seek64` cdecl externs. |
| `sf/src/std_file_pal.zig:34-39` | Remove `GetFileAttributesExA`; add `pal_file_mtime` cdecl extern. |
| `sf/src/std_os.zig:66-81` | Windows branch → `pal.pal_getenv`; POSIX `getenv` unchanged. |
| `sf/src/std_os_pal.zig:23-24` | Keep POSIX `getenv`; add `pal_getenv` extern. |
| `sf/src/std_time.zig:115-118` | Windows branch → `pal.pal_wallclock_unix`; POSIX `time` unchanged. |
| `sf/src/std_time_pal.zig:50-51` | Keep POSIX `time`; add `pal_wallclock_unix` extern. |

### 12.2 Emitted support canonical files

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/include/zig_pal.c:240-295` | Add `pal_file_size`/`pal_file_seek64`/`pal_file_mtime` after `pal_file_close`; `#ifdef ZIG_WIN_NT` modern vs default Win95. |
| `sf/src/include/zig_pal.c:297-346` | Add `pal_getenv` (static buffer) and `pal_wallclock_unix`; no break to existing dir/lib helpers. |
| `sf/src/include/zig_pal.c:348-355` | Replace the stub with `__main`, argc/argv parser via `GetCommandLineA`, and `exit(main(argc, argv))`; include `<stdlib.h>` under no-CRT. |
| `sf/src/include/zig_runtime.c:1-24` | Keep includes/uses; append no-CRT `strlen`/`memcpy`/`strncmp` at end (after 186). |
| `sf/src/c_exit.c:1-2` | Add guarded `atexit` registry + `exit`→`ExitProcess`; `c_exit` calls `exit` (CRT path unchanged). |
| `sf/src/include/std_os_prelude.h:8-14` | Add `_WIN32` prototypes for `pal_file_*` and `pal_getenv`. |
| `sf/src/include/std_time_prelude.h:10-27` | Add `_WIN32` prototype for `pal_wallclock_unix`. |
| **new** `sf/src/include/zig_nocrt.c` | New canonical shim: `__acrt_iob_func` + import pointer, `fwrite`/`getchar`/`putchar`, `getenv`, `_time32`/`time` + import pointer. |

### 12.3 Emitter / build scripts / gates

| File:line (current) | T5.3 edit |
|:--|:--|
| `sf/src/emit_support.zig:114-129` | Mirror the `std_os_prelude.h` prototype additions. |
| `sf/src/emit_support.zig:131-192` | Mirror the `std_time_prelude.h` prototype addition. |
| `sf/src/emit_support.zig:194-197` | Mirror the new `c_exit.c` block. |
| `sf/src/emit_support.zig` insert after 197 | New `emitZigNocrtCSupport` literal for `zig_nocrt.c`. |
| `sf/src/emit_support.zig:488-677` | Mirror the `zig_runtime.c` string shims. |
| `sf/src/emit_support.zig:679-1037` | Mirror all `zig_pal.c` additions; replace `mainCRTStartup` literal at 1027-1034. |
| `sf/src/c89_emit.zig:789-854` | `emitSupportFiles` writes `zig_nocrt.c`. |
| `sf/src/c89_emit.zig:8537-8574` | `emitBuildTargetSh`: 9x CFLAGS/LDFLAGS/LIBS + `zig_nocrt`; nt `-DZIG_WIN_NT`; winmm/wsock32. |
| `sf/src/c89_emit.zig:8576-8603` | `emitBuildTargetBat`: winmm/wsock32, `zig_nocrt`, no `ZIG_NO_CRT` on 9x. |
| `sf/src/c89_emit.zig:8605-8654` | `emitBuildOwcBat`: `library winmm`/`wsock32`, `zig_nocrt`, no `ZIG_NO_CRT` on 9x. |
| `sf/src/c89_emit.zig:8656-8675` | No signature change needed; profile already forwarded. |
| `scripts/check_emit_support.sh:55-59` | Add `zig_nocrt.c` byte-equality check. |
| `scripts/check_emit_support.sh:135` | Update count to 8/8 (6 core + 2 preludes). |
| **new** `scripts/win32_cross/check_win9x_imports.sh` | Whitelist gate (§10). |
| `scripts/win32_cross/cross_nocrt.sh:125-156` | Update the reference harness: include `c_exit.o` and the emitted `zig_nocrt` shims (or delete the duplicated scratch definitions). |
| `scripts/win32_cross/cross_nocrt.sh:164-174` | Stop excluding `c_exit.o`; link it. |
| `examples/z98/z9play/tests/tier_win9x.sh:162-173` | T5.5 integration: use `check_win9x_imports.sh` and the emitted 9x `build_target.sh` (not the CRT `cross_build_run.sh`). |

**Intentionally unchanged:** `sf/src/c89_emit.zig:5849` (`fwrite` emission),
`:7701` (`putchar`), `:7717-7723` (`getchar`), `:7726-7733` (`exit`) — the shims
satisfy those exact symbols. `sf/src/std_os.zig:61-63` (`@exit`) is unchanged;
`exit` is shimmed. `examples/z98/z9play/platform/console_win9x.zig:144-146` and
`console_win9x_pal.zig:112` are unchanged; the no-CRT `atexit` satisfies them.
`sf/src/include/zig_pal.c:126-133` (`pal_abort`) is already Win9x-safe.

---

## 13. Concerns / STOP-present notes

### C1 — `.bat`/`.owc` cannot safely add `ZIG_NO_CRT` (STOP-present on that wording)

`I found the intention is that the 9x default adds -DZIG_NO_CRT to build_target.bat/build_owc.bat as well, but this is impossible given that those scripts compile and link the native CRT: defining ZIG_NO_CRT would switch c_exit/exit to ExitProcess while the CRT startup still runs, and the shim definitions (atexit, exit, strlen, fwrite, ...) would collide with the CRT library's own definitions; the plan's "CRT path behavior unchanged" forbids it.`

Safe resolution used by this design: only the mingw `build_target.sh` 9x branch
gets `-DZIG_NO_CRT` and the `-nostdlib` link. `.bat`/`.owc` remain CRT (no
`ZIG_NO_CRT`) and still get the Win95-safe `pal_file_*` helpers because
`ZIG_WIN_NT` is absent. Their outputs are not 9x-no-CRT artifacts and must not
be fed to the 9x whitelist; the committed 9x gate is the mingw artifact.

### C2 — T5.3's original shim list omits the no-CRT startup `argc`/`argv`

The current no-CRT `mainCRTStartup` cannot pass arguments
(`sf/src/include/zig_pal.c:348-355`); z9play and z9torr crash under Wine before
parsing `--help` (§11.2). T5.3 must add the `GetCommandLineA` parser (and add
`GetCommandLineA` to the whitelist) even though it is not in the plan's bullet
list. This is implementable and safe; it is recorded as a scope addition, not a
reason to block the design.

### C3 — `std_os.env` slice lifetime

The static PAL buffer preserves the *shape* of the contract (a stable non-stack
pointer, single-threaded) but not the CRT's process-lifetime guarantee: the
slice is overwritten by the next `env()` call. The committed z9play/z9torr
callers use it immediately. If strict process-lifetime is required, the
alternative is `GetEnvironmentStringsA` + a cached block (not chosen because
Amendment 3 names `GetEnvironmentVariableA`).

### C4 — Win9x verification limit

Wine 8 is not a Win98 loader; the mechanical per-DLL whitelist plus T5.1's
export study is the loadability gate. The actual `GetFileSize`/`SetFilePointer`/
`FindFirstFileA`/console behavior still needs the T5.3 Wine↔Linux cross-probe and
a real/manual Win98 confirmation (T5.1 §10 concern 9).

---

## 14. Reproducibility summary

The probe artifacts are all under `/tmp`:

- `/tmp/t53a_z9play`, `/tmp/t53a_z9torr`, `/tmp/t53a_hello` — T5.2 dumps.
- `/tmp/t53a_shim/nocrt_shim.c` — complete scratch shim set (compiled
  `-Wall` clean after the null-check removal).
- `/tmp/t53a_z9play_sim`, `/tmp/t53a_z9torr_sim` — `/tmp` copies with the three
  `std_file` calls substituted by `pal_file_*` and cdecl call typedefs; include
  the scratch `pal_file_*`, `pal_getenv`, `pal_wallclock_unix`, and argv parser.
- `/tmp/t53a_ntcheck`, `/tmp/t53a_z9play_nt` — nt/CRT probes.
- `/tmp/t53a_shim/{shim_test,getchar_test,argv_test,atexit_return_test,string_test,file_helpers_test,file_helpers_test_nt,env_time_test}.c` —
  runtime probes.

No repository source file was modified by this task.
