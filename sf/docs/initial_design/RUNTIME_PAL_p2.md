> **Disclaimer:** Z98 is an independent project and is not affiliated with the official Zig project.

# Z98 Runtime, PAL, and Cross-Build Architecture

**Version:** 1.0  
**Component:** Platform Abstraction Layer, Runtime Library, Compatibility Headers, Build System  
**Parent Document:** DESIGN.md v3.0  
**Supersedes:** Bootstrap `platform.hpp`/`platform.cpp`, `zig_runtime.h`/`zig_runtime.c`

---

## 1. Problem Statement

The Z98 project has three binaries that all need platform services:

| Binary | Written In | Compiled By | Runs On | Needs |
|---|---|---|---|---|
| `zig0` (bootstrap) | C++98 | MinGW/GCC on Linux | Linux (dev) + Win9x (target) | File I/O, memory, console |
| `zig1` (self-hosted) | Z98 → C89 | `zig0` first, then itself | Linux (dev) + Win9x (target) | Same as zig0 |
| User programs | Z98 → C89 | `zig1` | Win9x (primary) + Linux (dev) | Arena, print, panic, I/O |

All three share the same constraint: the generated C89 must compile with **zero C standard library dependency on Windows** (kernel32.dll only) while also building cleanly on Linux with standard libc for development.

The bootstrap solved this with a C++ `platform.hpp`/`platform.cpp` split by `#ifdef _WIN32`. The self-hosted compiler needs the same split, but in pure C89 since `zig1`'s output is C89.

---

## 2. Architecture: Three Layers

```
┌─────────────────────────────────────────────────┐
│  User Z98 Program  /  zig1 Compiler (C89 code)  │
├─────────────────────────────────────────────────┤
│              zig_runtime.h / .c                  │  Arena allocator, panic, checked
│              (links against PAL)                 │  conversions, print helpers
├─────────────────────────────────────────────────┤
│                zig_pal.h / .c                    │  OS-native file I/O, memory,
│           Win32: kernel32.dll ONLY               │  console, string ops
│           Linux: POSIX libc                      │  
├─────────────────────────────────────────────────┤
│                zig_compat.h                       │  Type defs, compiler detection,
│              (pure header, no code)              │  bool/true/false, __int64
└─────────────────────────────────────────────────┘
```

Every generated `.c` file includes `zig_compat.h` (types) and `zig_runtime.h` (runtime). The runtime internally includes `zig_pal.h`. User code never calls PAL functions directly — they go through the runtime or through `extern "c"` declarations in their Z98 source.

### 2.1 Why Three Layers (Not Two)

The bootstrap merged PAL and runtime into a tangled pair. This caused problems:
- `zig_runtime.h` had to include PAL types (`usize`) before it could define slices.
- The arena allocator was mixed with platform I/O code.
- Testing the arena on Linux required pulling in the Win32 PAL stubs.

The three-layer split means:
- `zig_compat.h` can be included by ANYTHING — it has zero dependencies.
- `zig_pal.c` can be tested independently with a trivial main().
- `zig_runtime.c` can be tested on any platform by swapping the PAL implementation.

---

## 3. Layer 1: `zig_compat.h` (Type Definitions)

This is a **pure header** with no code, no function declarations, no external dependencies. It defines the integer types, bool, and compiler-detection macros that every other file depends on.

```c
/* zig_compat.h — Z98 Type Compatibility Layer
 * Include this FIRST in every generated .c file.
 * No #include dependencies. No function declarations. Pure types.
 */
#ifndef ZIG_COMPAT_H
#define ZIG_COMPAT_H

/* ══════ Compiler Detection ══════ */

#if defined(_MSC_VER)
  #define ZIG_MSVC 1
  #define ZIG_WIN32 1
#elif defined(__WATCOMC__)
  #define ZIG_WATCOM 1
  #define ZIG_WIN32 1
#elif defined(__MINGW32__)
  #define ZIG_MINGW 1
  #define ZIG_WIN32 1
#elif defined(__GNUC__)
  #define ZIG_GCC 1
  #define ZIG_POSIX 1
#else
  #error "Unsupported compiler"
#endif

/* ══════ Integer Types ══════ */

#if defined(ZIG_MSVC) || defined(ZIG_WATCOM)
  /* MSVC 6.0 and OpenWatcom: no <stdint.h>, use __int64 */
  typedef signed char        i8;
  typedef unsigned char      u8;
  typedef short              i16;
  typedef unsigned short     u16;
  typedef int                i32;
  typedef unsigned int       u32;
  typedef __int64            i64;
  typedef unsigned __int64   u64;
#else
  /* GCC, MinGW: use stdint.h */
  #include <stddef.h>
  typedef signed char        i8;
  typedef unsigned char      u8;
  typedef short              i16;
  typedef unsigned short     u16;
  typedef int                i32;
  typedef unsigned int       u32;
  typedef long long          i64;
  typedef unsigned long long u64;
#endif

/* Platform-sized integers (32-bit target) */
typedef i32 isize;
typedef u32 usize;

/* Floating point */
typedef float  f32;
typedef double f64;

/* ══════ Boolean ══════ */

#if defined(ZIG_MSVC) || defined(ZIG_WATCOM)
  #ifndef __cplusplus
    typedef int bool;
    #define true  1
    #define false 0
  #endif
#endif

/* ══════ NULL ══════ */

#ifndef NULL
  #define NULL ((void*)0)
#endif

/* ══════ Size Constants ══════ */

/* Used by the compiler for @sizeOf emission */
#define ZIG_PTR_SIZE   4
#define ZIG_PTR_ALIGN  4
#define ZIG_BOOL_SIZE  4    /* C89 int */
#define ZIG_BOOL_ALIGN 4

/* ══════ Noreturn ══════ */

#if defined(ZIG_MSVC)
  #define ZIG_NORETURN __declspec(noreturn)
#elif defined(ZIG_GCC) || defined(ZIG_MINGW)
  #define ZIG_NORETURN __attribute__((noreturn))
#elif defined(ZIG_WATCOM)
  /* OpenWatcom has limited attribute support */
  #define ZIG_NORETURN
#else
  #define ZIG_NORETURN
#endif

/* ══════ Inline (C89 has none — use static) ══════ */

#define ZIG_INLINE static

/* ══════ Debug Break ══════ */

#if defined(ZIG_MSVC)
  #define ZIG_DEBUG_BREAK() __debugbreak()
#elif defined(ZIG_GCC) || defined(ZIG_MINGW)
  #define ZIG_DEBUG_BREAK() __builtin_trap()
#else
  #define ZIG_DEBUG_BREAK()
#endif

#endif /* ZIG_COMPAT_H */
```

---

## 4. Layer 2: `zig_pal.h` / `zig_pal.c` (Platform Abstraction Layer)

### 4.1 Design Principles

1. **On Win32**: Use ONLY `kernel32.dll` functions. No `msvcrt.dll`, no `user32.dll`. This means:
   - Memory: `HeapAlloc`/`HeapFree`/`HeapReAlloc` from `GetProcessHeap()`. `VirtualAlloc` for >4 MB.
   - File I/O: `CreateFileA`/`ReadFile`/`WriteFile`/`CloseHandle`/`GetFileSize`.
   - Console: `GetStdHandle`/`WriteConsoleA`/`WriteFile` (fallback for redirected output).
   - Debug: `OutputDebugStringA`.
   - Process: `GetModuleFileNameA`, `TerminateProcess`, `ExitProcess`.
   - Filesystem: `GetFileAttributesA`, `CreateDirectoryA`, `DeleteFileA`.
   - String functions: **ALL reimplemented** (strlen, memcpy, strcmp, etc.) — no CRT dependency.

2. **On Linux/POSIX**: Use standard libc (`malloc`/`free`, `open`/`read`/`write`/`close`, `strlen`/`memcpy`, etc.). This is the development environment, not the deployment target. Simplicity over purity.

3. **No variadic functions in the PAL interface** exposed to Z98 code. The bootstrap's `plat_printf_debug` and `plat_snprintf` use `va_list` which Z98 cannot call. Instead, the PAL provides fixed-signature print functions, and the compiler's `std.debug.print` decomposition (DESIGN.md Section 7.5) calls these.

4. **No `sprintf` / `snprintf` exposed to generated code**. Float-to-string conversion uses a custom implementation. Integer-to-string uses the bootstrap's proven `plat_i64_to_string` / `plat_u64_to_string` (pure arithmetic, no CRT).

### 4.2 `zig_pal.h` — Function Declarations

```c
/* zig_pal.h — Platform Abstraction Layer
 * Provides OS-native implementations for memory, I/O, strings.
 * Win32: kernel32.dll only. Linux: standard libc.
 */
#ifndef ZIG_PAL_H
#define ZIG_PAL_H

#include "zig_compat.h"

/* ══════ File Handle Type ══════ */

#if defined(ZIG_WIN32)
  /* HANDLE is void*. We avoid including windows.h in the header. */
  typedef void* PlatFile;
  #define PLAT_INVALID_FILE ((void*)(isize)-1)  /* INVALID_HANDLE_VALUE */
#else
  typedef int PlatFile;
  #define PLAT_INVALID_FILE (-1)
#endif

/* ══════ Memory ══════ */

void* pal_alloc(usize size);
void  pal_free(void* ptr);
void* pal_realloc(void* ptr, usize new_size);

/* ══════ File I/O ══════ */

PlatFile pal_file_open(const char* path, i32 write);
void     pal_file_write(PlatFile file, const void* data, usize size);
usize    pal_file_read(PlatFile file, void* buffer, usize size);
void     pal_file_close(PlatFile file);
i32      pal_file_exists(const char* path);
usize    pal_file_size(PlatFile file);

/* Convenience: read entire file into pal_alloc'd buffer. Caller must pal_free. */
i32 pal_file_read_all(const char* path, char** out_buffer, usize* out_size);

/* ══════ Console Output ══════ */

void pal_print_stdout(const char* msg, usize len);
void pal_print_stderr(const char* msg, usize len);

/* ══════ Filesystem ══════ */

i32  pal_mkdir(const char* path);
i32  pal_delete_file(const char* path);
void pal_get_exe_dir(char* buffer, usize size);

/* ══════ Process ══════ */

ZIG_NORETURN void pal_abort(void);
ZIG_NORETURN void pal_exit(i32 code);

/* ══════ String Operations (CRT-free on Win32) ══════ */

usize pal_strlen(const char* s);
void  pal_memcpy(void* dst, const void* src, usize n);
void  pal_memmove(void* dst, const void* src, usize n);
void  pal_memset(void* s, i32 c, usize n);
i32   pal_memcmp(const void* a, const void* b, usize n);
i32   pal_strcmp(const char* a, const char* b);
i32   pal_strncmp(const char* a, const char* b, usize n);
void  pal_strcpy(char* dst, const char* src);
void  pal_strncpy(char* dst, const char* src, usize n);
char* pal_strchr(const char* s, i32 c);
char* pal_strrchr(const char* s, i32 c);

/* ══════ Number-to-String (CRT-free) ══════ */

void pal_i64_to_str(i64 value, char* buf, usize buf_size);
void pal_u64_to_str(u64 value, char* buf, usize buf_size);
void pal_f64_to_str(f64 value, char* buf, usize buf_size);

/* ══════ String-to-Number (CRT-free) ══════ */

i64 pal_str_to_i64(const char* s, const char** end_ptr);
u64 pal_str_to_u64(const char* s, const char** end_ptr);

#endif /* ZIG_PAL_H */
```

### 4.3 Key Implementation Notes

#### 4.3.1 Win32 Memory: `HeapAlloc` vs `VirtualAlloc`

```c
/* Win32 implementation */
#include <windows.h>

void* pal_alloc(usize size) {
    if (size == 0) return NULL;
    if (size > 4 * 1024 * 1024) {
        /* VirtualAlloc for large blocks — page-aligned, no heap fragmentation */
        return VirtualAlloc(NULL, size, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    }
    return HeapAlloc(GetProcessHeap(), 0, size);
}

void pal_free(void* ptr) {
    if (!ptr) return;
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(ptr, &mbi, sizeof(mbi)) && mbi.AllocationBase == ptr) {
        VirtualFree(ptr, 0, MEM_RELEASE);
    } else {
        HeapFree(GetProcessHeap(), 0, ptr);
    }
}
```

#### 4.3.2 Win32 Console: No `printf`, No `fputs`

```c
void pal_print_stdout(const char* msg, usize len) {
    HANDLE h;
    DWORD written;
    if (!msg || len == 0) return;
    h = GetStdHandle(STD_OUTPUT_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return;
    /* WriteConsoleA works for interactive console; WriteFile for redirected */
    if (!WriteConsoleA(h, msg, (DWORD)len, &written, NULL)) {
        WriteFile(h, msg, (DWORD)len, &written, NULL);
    }
}

void pal_print_stderr(const char* msg, usize len) {
    HANDLE h;
    DWORD written;
    if (!msg || len == 0) return;
    h = GetStdHandle(STD_ERROR_HANDLE);
    if (h == INVALID_HANDLE_VALUE || h == NULL) return;
    if (!WriteConsoleA(h, msg, (DWORD)len, &written, NULL)) {
        WriteFile(h, msg, (DWORD)len, &written, NULL);
    }
}
```

#### 4.3.3 Float-to-String: Custom `dtoa` (No CRT)

The bootstrap has a `TODO` for this. The self-hosted compiler needs it solved. We implement a minimal float formatter that handles the cases Z98 programs actually need: `std.debug.print("{}", .{float_val})`.

```c
void pal_f64_to_str(f64 value, char* buf, usize buf_size) {
    /* 
     * Strategy: Extract integer and fractional parts.
     * Print up to 6 decimal places (sufficient for Z98 use cases).
     * Handles: positive, negative, zero, large integers, small fractions.
     * Does NOT handle: NaN, Inf, subnormals, scientific notation.
     * These can be added after self-hosting.
     */
    i32 i;
    char* p = buf;
    char* end = buf + buf_size - 1;
    i64 int_part;
    f64 frac_part;
    i32 decimal_places = 6;
    
    if (buf_size < 2) { if (buf_size == 1) buf[0] = '\0'; return; }
    
    /* Handle negative */
    if (value < 0.0) {
        *p++ = '-';
        value = -value;
    }
    
    /* Split into integer and fractional parts */
    int_part = (i64)value;
    frac_part = value - (f64)int_part;
    
    /* Print integer part */
    {
        char tmp[24];
        pal_i64_to_str(int_part, tmp, sizeof(tmp));
        for (i = 0; tmp[i] && p < end; i++) *p++ = tmp[i];
    }
    
    /* Print decimal point and fractional part */
    if (p < end) *p++ = '.';
    for (i = 0; i < decimal_places && p < end; i++) {
        frac_part *= 10.0;
        {
            i32 digit = (i32)frac_part;
            *p++ = (char)('0' + digit);
            frac_part -= (f64)digit;
        }
    }
    
    /* Trim trailing zeros (keep at least one decimal) */
    while (p > buf + 2 && *(p-1) == '0' && *(p-2) != '.') p--;
    
    *p = '\0';
}
```

#### 4.3.4 Win32 String Functions: Reimplemented

These are direct ports from the bootstrap `platform.cpp` — pure C, no CRT dependency:

```c
usize pal_strlen(const char* s) {
    const char* p = s;
    while (*p) p++;
    return (usize)(p - s);
}

void pal_memcpy(void* dst, const void* src, usize n) {
    char* d = (char*)dst;
    const char* s = (const char*)src;
    while (n--) *d++ = *s++;
}

void pal_memmove(void* dst, const void* src, usize n) {
    char* d = (char*)dst;
    const char* s = (const char*)src;
    if (d < s) {
        while (n--) *d++ = *s++;
    } else {
        d += n; s += n;
        while (n--) *--d = *--s;
    }
}

i32 pal_strcmp(const char* a, const char* b) {
    while (*a && (*a == *b)) { a++; b++; }
    return *(const unsigned char*)a - *(const unsigned char*)b;
}

/* ... etc — same implementations as bootstrap platform.cpp */
```

#### 4.3.5 Linux Implementation: Thin libc Wrappers

```c
/* Linux — just delegate to libc */
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

void* pal_alloc(usize size) { return malloc(size); }
void  pal_free(void* ptr) { free(ptr); }
void* pal_realloc(void* ptr, usize new_size) { return realloc(ptr, new_size); }

usize pal_strlen(const char* s) { return strlen(s); }
void  pal_memcpy(void* d, const void* s, usize n) { memcpy(d, s, n); }
i32   pal_strcmp(const char* a, const char* b) { return strcmp(a, b); }
/* ... etc */

void pal_print_stdout(const char* msg, usize len) {
    write(STDOUT_FILENO, msg, len);
}

void pal_print_stderr(const char* msg, usize len) {
    write(STDERR_FILENO, msg, len);
}
```

### 4.4 What Changed from Bootstrap PAL

| Bootstrap (`plat_*`) | Self-Hosted (`pal_*`) | Change | Reason |
|---|---|---|---|
| `plat_printf_debug(fmt, ...)` | **Removed** | No variadic functions | Z98 cannot call variadic C functions |
| `plat_snprintf(buf, sz, fmt, ...)` | **Removed** | No variadic functions | Same; replaced by type-specific `pal_*_to_str` |
| `plat_print_info(msg)` | `pal_print_stdout(msg, len)` | Explicit length | Avoids hidden `strlen` call; matches Z98 slice semantics |
| `plat_print_error(msg)` | `pal_print_stderr(msg, len)` | Explicit length | Same |
| `plat_print_debug(msg)` | **Removed** | Debug print via runtime | `__bootstrap_print_*` in runtime handles this |
| `plat_write_str(msg)` | Merged into `pal_print_stderr` | Redundant | Was identical to `plat_print_error` |
| `plat_file_read(path, &buf, &sz)` | `pal_file_read_all(path, &buf, &sz)` | Renamed | Clearer intent |
| `plat_run_command(cmd, ...)` | **Removed** | Not needed | Compiler doesn't shell out |
| `plat_create_temp_file(...)` | **Removed** | Not needed | Compiler writes to `-o` directory |
| `plat_float_to_string` | `pal_f64_to_str` | Custom dtoa | Eliminates `sprintf` dependency |
| `bool` parameters | `i32` parameters | C89 compatibility | C89 has no `bool` in function signatures across TUs |

### 4.5 Linking Model

On Win32, `zig_pal.c` must NOT be compiled with any CRT linkage flags. The build scripts use:

```batch
REM MSVC 6.0 — no CRT
cl /c /Za /W3 /DZIG_WIN32 zig_pal.c
cl /c /Za /W3 /DZIG_WIN32 zig_runtime.c
cl /c /Za /W3 /DZIG_WIN32 main.c foo.c bar.c
link /subsystem:console /entry:mainCRTStartup kernel32.lib zig_pal.obj zig_runtime.obj main.obj foo.obj bar.obj /out:target.exe
```

```batch
REM OpenWatcom — no CRT
wcc386 /za /we /dZIG_WIN32 zig_pal.c
wcc386 /za /we /dZIG_WIN32 zig_runtime.c
wcc386 /za /we /dZIG_WIN32 main.c foo.c bar.c
wlink system nt file zig_pal,zig_runtime,main,foo,bar name target.exe library kernel32
```

```bash
# MinGW (Linux cross-compile to Win32)
i686-w64-mingw32-gcc -std=c89 -pedantic -Wall -DZIG_WIN32 -c zig_pal.c
i686-w64-mingw32-gcc -std=c89 -pedantic -Wall -DZIG_WIN32 -c zig_runtime.c
i686-w64-mingw32-gcc -std=c89 -pedantic -Wall -DZIG_WIN32 -c main.c foo.c bar.c
i686-w64-mingw32-gcc -o target.exe zig_pal.o zig_runtime.o main.o foo.o bar.o -lkernel32 -nostdlib
```

```bash
# Linux native (development)
gcc -std=c89 -pedantic -Wall -DZIG_POSIX -c zig_pal.c
gcc -std=c89 -pedantic -Wall -DZIG_POSIX -c zig_runtime.c
gcc -std=c89 -pedantic -Wall -DZIG_POSIX -c main.c foo.c bar.c
gcc -o target zig_pal.o zig_runtime.o main.o foo.o bar.o
```

---

## 5. Layer 3: `zig_runtime.h` / `zig_runtime.c`

The runtime provides services to generated Z98 programs. It depends on the PAL for OS access but adds Z98-specific functionality.

### 5.1 `zig_runtime.h`

```c
/* zig_runtime.h — Z98 Runtime Library
 * Provides: Arena allocator, panic handler, checked conversions,
 *           print helpers for std.debug.print decomposition.
 */
#ifndef ZIG_RUNTIME_H
#define ZIG_RUNTIME_H

#include "zig_compat.h"
#include "zig_pal.h"

/* ══════ Include generated special types AFTER basic types are defined ══════ */
/* This header is generated by the compiler and contains:
 * - Slice typedefs (Slice_u8, Slice_const_u8, Slice_i32, etc.)
 * - Optional typedefs (Opt_i32, Opt_ptr_Node, etc.)
 * - Error union typedefs (EU_i32, EU_void, etc.)
 * - Tagged union typedefs
 * - Static helper functions (__make_slice_*, etc.)
 */
#include "zig_special_types.h"

/* ══════ Arena Allocator ══════ */

typedef struct ArenaChunk {
    struct ArenaChunk* next;
    usize capacity;
    usize offset;
    /* Data follows immediately after this header */
} ArenaChunk;

typedef struct Arena {
    ArenaChunk* head;
    usize chunk_size;        /* default size for new chunks */
    usize total_allocated;   /* peak tracking */
    usize hard_limit;        /* 0 = no limit */
} Arena;

Arena*  arena_create(usize initial_capacity);
void*   arena_alloc(Arena* a, usize size);
void*   arena_alloc_aligned(Arena* a, usize size, usize alignment);
void    arena_reset(Arena* a);
void    arena_destroy(Arena* a);

/* Global default arena (initialized in main before user code) */
extern Arena* zig_default_arena;

/* ══════ Panic Handler ══════ */

ZIG_NORETURN void __bootstrap_panic(const char* msg);
ZIG_NORETURN void __bootstrap_panic_with_loc(const char* msg, const char* file, u32 line);

/* ══════ Checked Conversions ══════ */

/* Each function checks bounds and panics on overflow.
 * Naming: __bootstrap_<target>_from_<source> */

i8  __bootstrap_i8_from_i32(i32 value);
i8  __bootstrap_i8_from_i64(i64 value);
i16 __bootstrap_i16_from_i32(i32 value);
i16 __bootstrap_i16_from_i64(i64 value);
i32 __bootstrap_i32_from_i64(i64 value);
i32 __bootstrap_i32_from_usize(usize value);

u8  __bootstrap_u8_from_i32(i32 value);
u8  __bootstrap_u8_from_u32(u32 value);
u8  __bootstrap_u8_from_u64(u64 value);
u16 __bootstrap_u16_from_i32(i32 value);
u16 __bootstrap_u16_from_u32(u32 value);
u32 __bootstrap_u32_from_i32(i32 value);
u32 __bootstrap_u32_from_i64(i64 value);
u32 __bootstrap_u32_from_u64(u64 value);

usize __bootstrap_usize_from_i32(i32 value);
usize __bootstrap_usize_from_i64(i64 value);
isize __bootstrap_isize_from_usize(usize value);

/* ══════ Print Helpers (std.debug.print decomposition) ══════ */

/* These are called by the compiler's lowered print sequences.
 * All output goes to stderr (matching Zig's std.debug.print behavior). */

void __bootstrap_print(const char* s);
void __bootstrap_print_len(const char* s, usize len);
void __bootstrap_print_i32(i32 value);
void __bootstrap_print_u32(u32 value);
void __bootstrap_print_i64(i64 value);
void __bootstrap_print_u64(u64 value);
void __bootstrap_print_f64(f64 value);
void __bootstrap_print_bool(i32 value);
void __bootstrap_print_char(u8 value);
void __bootstrap_print_hex_u32(u32 value);
void __bootstrap_print_hex_u64(u64 value);
void __bootstrap_print_ptr(const void* value);

/* String print: takes a Slice_const_u8 (ptr + len) */
void __bootstrap_print_str(const u8* ptr, usize len);

/* Newline */
void __bootstrap_print_nl(void);

/* ══════ Bounds Checking ══════ */

void __bootstrap_bounds_check(usize index, usize length, const char* file, u32 line);

#endif /* ZIG_RUNTIME_H */
```

### 5.2 Key Runtime Implementation

#### Arena Allocator

```c
/* zig_runtime.c */
#include "zig_runtime.h"

Arena* zig_default_arena = NULL;

Arena* arena_create(usize initial_capacity) {
    Arena* a;
    ArenaChunk* chunk;
    
    a = (Arena*)pal_alloc(sizeof(Arena));
    if (!a) __bootstrap_panic("arena_create: out of memory");
    
    chunk = (ArenaChunk*)pal_alloc(sizeof(ArenaChunk) + initial_capacity);
    if (!chunk) { pal_free(a); __bootstrap_panic("arena_create: out of memory"); }
    
    chunk->next = NULL;
    chunk->capacity = initial_capacity;
    chunk->offset = 0;
    
    a->head = chunk;
    a->chunk_size = initial_capacity;
    a->total_allocated = sizeof(Arena) + sizeof(ArenaChunk) + initial_capacity;
    a->hard_limit = 0;
    
    return a;
}

void* arena_alloc_aligned(Arena* a, usize size, usize alignment) {
    ArenaChunk* chunk;
    usize aligned_offset;
    usize new_capacity;
    void* result;
    
    if (!a || size == 0) return NULL;
    
    chunk = a->head;
    
    /* Align the current offset */
    aligned_offset = (chunk->offset + alignment - 1) & ~(alignment - 1);
    
    if (aligned_offset + size <= chunk->capacity) {
        result = (char*)chunk + sizeof(ArenaChunk) + aligned_offset;
        chunk->offset = aligned_offset + size;
        return result;
    }
    
    /* Need a new chunk */
    new_capacity = a->chunk_size;
    if (size + alignment > new_capacity) new_capacity = size + alignment;
    
    /* Check hard limit */
    if (a->hard_limit > 0 && a->total_allocated + sizeof(ArenaChunk) + new_capacity > a->hard_limit) {
        __bootstrap_panic("arena: hard memory limit exceeded");
    }
    
    chunk = (ArenaChunk*)pal_alloc(sizeof(ArenaChunk) + new_capacity);
    if (!chunk) __bootstrap_panic("arena_alloc: out of memory");
    
    chunk->capacity = new_capacity;
    chunk->offset = 0;
    chunk->next = a->head;
    a->head = chunk;
    a->total_allocated += sizeof(ArenaChunk) + new_capacity;
    
    aligned_offset = (chunk->offset + alignment - 1) & ~(alignment - 1);
    result = (char*)chunk + sizeof(ArenaChunk) + aligned_offset;
    chunk->offset = aligned_offset + size;
    return result;
}

void* arena_alloc(Arena* a, usize size) {
    return arena_alloc_aligned(a, size, 8); /* 8-byte alignment default */
}
```

#### Print Helpers

```c
void __bootstrap_print(const char* s) {
    if (!s) return;
    pal_print_stderr(s, pal_strlen(s));
}

void __bootstrap_print_len(const char* s, usize len) {
    if (!s || len == 0) return;
    pal_print_stderr(s, len);
}

void __bootstrap_print_i32(i32 value) {
    char buf[16];
    pal_i64_to_str((i64)value, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_u32(u32 value) {
    char buf[16];
    pal_u64_to_str((u64)value, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_i64(i64 value) {
    char buf[24];
    pal_i64_to_str(value, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_f64(f64 value) {
    char buf[32];
    pal_f64_to_str(value, buf, sizeof(buf));
    __bootstrap_print(buf);
}

void __bootstrap_print_bool(i32 value) {
    if (value) __bootstrap_print("true");
    else __bootstrap_print("false");
}

void __bootstrap_print_char(u8 value) {
    char c = (char)value;
    pal_print_stderr(&c, 1);
}

void __bootstrap_print_hex_u32(u32 value) {
    char buf[12];
    i32 i;
    static const char hex[] = "0123456789abcdef";
    buf[0] = '0'; buf[1] = 'x';
    for (i = 7; i >= 0; i--) {
        buf[2 + (7 - i)] = hex[(value >> (i * 4)) & 0xF];
    }
    buf[10] = '\0';
    __bootstrap_print(buf);
}

void __bootstrap_print_str(const u8* ptr, usize len) {
    pal_print_stderr((const char*)ptr, len);
}

void __bootstrap_print_nl(void) {
    pal_print_stderr("\n", 1);
}
```

#### Panic Handler

```c
ZIG_NORETURN void __bootstrap_panic(const char* msg) {
    __bootstrap_print("panic: ");
    __bootstrap_print(msg);
    __bootstrap_print_nl();
    pal_abort();
}

ZIG_NORETURN void __bootstrap_panic_with_loc(const char* msg, const char* file, u32 line) {
    char line_buf[12];
    __bootstrap_print(file);
    __bootstrap_print(":");
    pal_u64_to_str((u64)line, line_buf, sizeof(line_buf));
    __bootstrap_print(line_buf);
    __bootstrap_print(": panic: ");
    __bootstrap_print(msg);
    __bootstrap_print_nl();
    pal_abort();
}
```

#### Checked Conversions (Example)

```c
u8 __bootstrap_u8_from_i32(i32 value) {
    if (value < 0 || value > 255) {
        __bootstrap_panic("@intCast: value out of range for u8");
    }
    return (u8)value;
}

i32 __bootstrap_i32_from_i64(i64 value) {
    /* Check: -2147483648 <= value <= 2147483647 */
    if (value < (i64)(-2147483647 - 1) || value > (i64)2147483647) {
        __bootstrap_panic("@intCast: value out of range for i32");
    }
    return (i32)value;
}

usize __bootstrap_usize_from_i32(i32 value) {
    if (value < 0) {
        __bootstrap_panic("@intCast: negative value for usize");
    }
    return (usize)value;
}
```

#### Bounds Checking

```c
void __bootstrap_bounds_check(usize index, usize length, const char* file, u32 line) {
    if (index >= length) {
        char idx_buf[12];
        char len_buf[12];
        pal_u64_to_str((u64)index, idx_buf, sizeof(idx_buf));
        pal_u64_to_str((u64)length, len_buf, sizeof(len_buf));
        __bootstrap_print(file);
        __bootstrap_print(":");
        {
            char line_buf[12];
            pal_u64_to_str((u64)line, line_buf, sizeof(line_buf));
            __bootstrap_print(line_buf);
        }
        __bootstrap_print(": index out of bounds: index ");
        __bootstrap_print(idx_buf);
        __bootstrap_print(", length ");
        __bootstrap_print(len_buf);
        __bootstrap_print_nl();
        pal_abort();
    }
}
```

---

## 6. Include Order in Generated Code

Every `.c` file generated by the compiler follows this exact include order:

```c
/* foo.c — generated by zig1 from foo.zig */
#include "zig_compat.h"          /* 1. Type definitions (no dependencies) */
#include "zig_pal.h"             /* 2. PAL declarations (depends on zig_compat.h) */
#include "zig_runtime.h"         /* 3. Runtime (depends on PAL + compat) */
                                 /*    zig_runtime.h includes zig_special_types.h */
#include "foo.h"                 /* 4. Module's own header */
#include "bar.h"                 /* 5. Imported module headers */

/* ... function implementations ... */
```

Each `.h` file has include guards and includes `zig_compat.h` for type safety:

```c
/* foo.h — generated by zig1 from foo.zig */
#ifndef ZIG_FOO_H
#define ZIG_FOO_H

#include "zig_compat.h"

/* Public type definitions */
/* Forward declarations */
/* Extern function prototypes */

#endif /* ZIG_FOO_H */
```

---

## 7. How `zig1` Calls the PAL

The self-hosted compiler (`zig1`) is written in Z98 and compiles to C89. Its Z98 source declares PAL functions as `extern`:

```zig
// In zig1's source: pal.zig (Z98 declarations matching zig_pal.h)
extern "c" fn pal_alloc(size: usize) ?*void;
extern "c" fn pal_free(ptr: *void) void;
extern "c" fn pal_realloc(ptr: *void, new_size: usize) ?*void;

extern "c" fn pal_file_open(path: [*]const u8, write: i32) i32;
extern "c" fn pal_file_write(file: i32, data: [*]const u8, size: usize) void;
extern "c" fn pal_file_read(file: i32, buffer: [*]u8, size: usize) usize;
extern "c" fn pal_file_close(file: i32) void;
extern "c" fn pal_file_exists(path: [*]const u8) i32;
extern "c" fn pal_file_read_all(path: [*]const u8, out_buf: *[*]u8, out_size: *usize) i32;

extern "c" fn pal_print_stdout(msg: [*]const u8, len: usize) void;
extern "c" fn pal_print_stderr(msg: [*]const u8, len: usize) void;

extern "c" fn pal_strlen(s: [*]const u8) usize;
extern "c" fn pal_memcpy(dst: [*]u8, src: [*]const u8, n: usize) void;
extern "c" fn pal_strcmp(a: [*]const u8, b: [*]const u8) i32;
// ... etc
```

When `zig0` compiles this to C89, it produces:

```c
/* pal.c — generated from pal.zig */
/* These are extern declarations — no function bodies generated */
extern void* pal_alloc(unsigned int size);
extern void pal_free(void* ptr);
/* ... etc */
```

The linker resolves these against `zig_pal.o` (compiled from `zig_pal.c`).

---

## 8. Build System Generation

The compiler emits build scripts alongside the generated C files. These scripts handle all three target toolchains.

### 8.1 `build_target.sh` (Linux native + MinGW cross-compile)

```bash
#!/bin/sh
# build_target.sh — generated by zig1
# Usage: sh build_target.sh [linux|mingw]

TARGET=${1:-linux}
CFLAGS="-std=c89 -pedantic -Wall -Werror"

case "$TARGET" in
    linux)
        CC=gcc
        PLATFORM_DEF="-DZIG_POSIX"
        LINK_FLAGS=""
        OUT=target
        ;;
    mingw)
        CC=i686-w64-mingw32-gcc
        PLATFORM_DEF="-DZIG_WIN32"
        LINK_FLAGS="-lkernel32 -nostdlib -Wl,--entry,_mainCRTStartup"
        OUT=target.exe
        ;;
    *)
        echo "Unknown target: $TARGET"; exit 1
        ;;
esac

echo "Building for $TARGET..."

# Compile PAL and runtime
$CC $CFLAGS $PLATFORM_DEF -c zig_pal.c -o zig_pal.o
$CC $CFLAGS $PLATFORM_DEF -c zig_runtime.c -o zig_runtime.o

# Compile generated modules
$CC $CFLAGS $PLATFORM_DEF -c main.c -o main.o
# ... one line per generated .c file ...

# Link
$CC -o $OUT zig_pal.o zig_runtime.o main.o $LINK_FLAGS

echo "Built: $OUT"
```

### 8.2 `build_target.bat` (MSVC 6.0)

```batch
@echo off
REM build_target.bat — generated by zig1

set CC=cl
set CFLAGS=/c /Za /W3 /WX /DZIG_WIN32
set LINK=link

echo Compiling...
%CC% %CFLAGS% zig_pal.c
%CC% %CFLAGS% zig_runtime.c
%CC% %CFLAGS% main.c
REM ... one line per generated .c file ...

echo Linking...
%LINK% /subsystem:console kernel32.lib zig_pal.obj zig_runtime.obj main.obj /out:target.exe

echo Built: target.exe
```

### 8.3 `build_owc.bat` (OpenWatcom)

```batch
@echo off
REM build_owc.bat — generated by zig1 for OpenWatcom

echo Compiling...
wcc386 /za /we /dZIG_WIN32 zig_pal.c
wcc386 /za /we /dZIG_WIN32 zig_runtime.c
wcc386 /za /we /dZIG_WIN32 main.c
REM ... one line per generated .c file ...

echo Linking...
wlink system nt file zig_pal,zig_runtime,main name target.exe library kernel32

echo Built: target.exe
```

---

## 9. Output Directory Structure

When the compiler runs `./zig1 main.zig -o output/`, the output directory contains:

```
output/
├── zig_compat.h           # Type definitions (static, same every build)
├── zig_pal.h              # PAL declarations (static, same every build)
├── zig_pal.c              # PAL implementation (static, platform-selected at compile time)
├── zig_runtime.h          # Runtime declarations (static)
├── zig_runtime.c          # Runtime implementation (static)
├── zig_special_types.h    # Generated: slice/optional/error-union/tagged-union typedefs
├── main.h                 # Generated: public symbols from main.zig
├── main.c                 # Generated: implementation from main.zig
├── foo.h                  # Generated: public symbols from foo.zig (if imported)
├── foo.c                  # Generated: implementation from foo.zig
├── build_target.sh        # Generated: Linux/MinGW build script
├── build_target.bat       # Generated: MSVC 6.0 build script
└── build_owc.bat          # Generated: OpenWatcom build script
```

The static files (`zig_compat.h`, `zig_pal.*`, `zig_runtime.*`) are copied verbatim from the compiler's `lib/` directory. The generated files are produced by the C89 emitter.

---

## 10. CRT Entry Point Considerations

### 10.1 Win32 Without CRT

When linking without CRT on Win32, the default entry point `main()` requires CRT initialization. Two options:

**Option A: Use `mainCRTStartup` stub (recommended for bootstrap)**
```c
/* Minimal CRT stub — compiled into every Win32 target */
/* Placed in zig_pal.c under #if defined(ZIG_WIN32) && defined(ZIG_NO_CRT) */

extern int main(void);

void __cdecl mainCRTStartup(void) {
    int result = main();
    ExitProcess((UINT)result);
}
```

**Option B: Use `/entry:main` (simpler but less portable)**

The generated build scripts use Option A by default: `zig_pal.c` includes the stub when `ZIG_NO_CRT` is defined.

### 10.2 Linux

No special entry point handling needed. Standard `main()` through libc.

### 10.3 Global Initialization

The generated `main()` function always begins with runtime initialization:

```c
int main(void) {
    /* Initialize default arena */
    zig_default_arena = arena_create(1024 * 1024); /* 1 MB default */
    
    /* Initialize global vars (Z98 workaround for aggregate constants) */
    initGlobals();
    
    /* Call user's main logic */
    zF_main();
    
    /* Cleanup */
    arena_destroy(zig_default_arena);
    return 0;
}
```

For programs returning `!void`:
```c
int main(void) {
    EU_void __result;
    zig_default_arena = arena_create(1024 * 1024);
    initGlobals();
    __result = zF_main();
    arena_destroy(zig_default_arena);
    if (__result.is_error) return 1;
    return 0;
}
```

---

## 11. Cross-Platform Testing Workflow

### 11.1 Development Cycle (Linux)

```
Developer Machine (Linux x86_64)
    │
    ├─ Build zig0 (C++98, GCC)
    │   └─ ./zig0 compiles zig1.zig → C89 files
    │
    ├─ Build zig1 (C89, GCC -std=c89, Linux native)
    │   └─ Test: zig1 runs on Linux, compiles test programs
    │
    ├─ Cross-compile test programs (MinGW)
    │   └─ i686-w64-mingw32-gcc -std=c89 → .exe files
    │
    └─ Transfer .exe to Win9x VM for testing
```

### 11.2 Verification on Win9x VM

```
Windows 98 VM
    │
    ├─ MSVC 6.0: cl /Za test.c zig_pal.c zig_runtime.c → test.exe ✓
    ├─ OpenWatcom: wcc386 /za test.c zig_pal.c zig_runtime.c → test.exe ✓
    ├─ MinGW cross-compiled: test.exe (from Linux) → runs correctly ✓
    │
    └─ Memory verification: peak usage < 16 MB ✓
```

### 11.3 CI Pipeline

```bash
#!/bin/sh
# ci.sh — full verification pipeline

# 1. Build zig1 on Linux
gcc -std=c89 -pedantic -Wall -DZIG_POSIX -c zig_pal.c
gcc -std=c89 -pedantic -Wall -DZIG_POSIX -c zig_runtime.c
# ... compile zig1's generated C files ...
gcc -o zig1 *.o

# 2. Compile reference programs with zig1
for prog in mandelbrot game_of_life mud eval; do
    ./zig1 tests/reference/$prog.zig -o /tmp/build_$prog/
    
    # 3a. Build and test on Linux
    cd /tmp/build_$prog
    sh build_target.sh linux
    ./target > /tmp/output_$prog.txt
    diff tests/expected/$prog.txt /tmp/output_$prog.txt
    
    # 3b. Cross-compile for Win32 (verify compilation only)
    sh build_target.sh mingw
    # Cannot run .exe on Linux, but compilation success proves C89 compliance
done

# 4. Self-hosting test
./zig1 lib/main.zig -o /tmp/stage1/
cd /tmp/stage1 && sh build_target.sh linux && cp target /tmp/zig2
/tmp/zig2 lib/main.zig -o /tmp/stage2/
cd /tmp/stage2 && sh build_target.sh linux && cp target /tmp/zig3
cmp /tmp/zig2 /tmp/zig3 && echo "PASS: self-hosting"
```

---

## 12. Extensibility

### 12.1 Adding a New PAL Platform

To support a new OS (e.g., DOS, OS/2):
1. Add a new `#elif defined(ZIG_DOS)` section in `zig_pal.c`.
2. Implement all `pal_*` functions using the OS's native API.
3. Add a new build script template (`build_dos.bat`).
4. No changes to `zig_runtime.*` or generated code.

### 12.2 Adding Socket Support

The MUD server uses extern C socket functions. To make these part of the PAL:
1. Add `pal_socket_*` functions to `zig_pal.h`.
2. Implement using `WinSock` (Win32) or POSIX sockets (Linux).
3. On Win32, link against `wsock32.lib` in addition to `kernel32.lib`.

### 12.3 Replacing `sprintf` Entirely

The current `pal_f64_to_str` handles basic cases. For full IEEE 754 compliance (NaN, Inf, scientific notation, arbitrary precision), implement Grisu2 or Ryu algorithm in pure C89. This is a post-self-hosting improvement.

### 12.4 Adding File Buffering

For compiler performance (many small writes), add a `BufferedWriter` in the runtime:

```c
typedef struct {
    PlatFile file;
    char buffer[4096];
    usize pos;
} BufferedWriter;

void bw_write(BufferedWriter* bw, const char* data, usize len);
void bw_flush(BufferedWriter* bw);
```

This is used by the C89 emitter and doesn't require PAL changes.
