# 10 — C Runtime Layer

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Header files | 3 | `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h` |
| C source files | 2 | `zig_runtime.c`, `zig_pal.c` |
| PAL functions | 9 | print_stderr/stdout, abort, i64/u64/f64_to_str, strlen, memcpy, reverse |
| Runtime print helpers | 11 | std_panic, std_print, std_print_len, std_print_i32, std_print_u32, std_print_i64, std_print_u64, std_print_f64, std_print_bool, std_print_char, std_print_str |
| Checked cast functions | 8 | i8/u8/i16/u16/i32/u32/i64/u64 |
| Backward compat aliases | 6 | __bootstrap_print/print_int/print_char/panic/write/sleep_ms |
| Legacy arena functions | 6 | arena_create, arena_alloc, arena_free, arena_reset, arena_destroy, arena_alloc_default |
| Type tables | 3 | Slice, Optional, ErrorUnion — emitted by zig1 codegen, not in runtime headers |

---

## Function Walkthrough

### `zig_compat.h` — C89 Type Definitions (`sf/src/include/zig_compat.h:1-38`)

| Decl | Line | Visibility | Purpose | Notes |
|------|------|-----------|---------|-------|
| `z64`/`zu64` typedefs | 6-14 | global | 64-bit integer platform abstraction | MSC → `__int64`, else → `long long` [inference] |
| `i8`..`u64` types | 17-27 | global | Fixed-width integer types | Guarded by `!__cplusplus` [inference] |
| `f32`/`f64` | 25-26 | global | Float types | Just `float`/`double` [inference] |
| `usize` | 27 | global | Pointer-sized unsigned | `unsigned int` [inference] |
| `bool`/`true`/`false` | 30-32 | global | Boolean type | C89 has no `_Bool`; typedef to `int` [inference] |

All typedefs at `sf/src/include/zig_compat.h`.

### `zig_runtime.h` — Header Declarations (`sf/src/include/zig_runtime.h:1-44`)

| Decl | Line | Visibility | Purpose | Notes |
|------|------|-----------|---------|-------|
| `pal_print_stderr` | 6 | extern | Raw stderr write | Takes `(const char*, unsigned int len)` [inference] |
| `pal_abort` | 7 | extern | Abort process | [inference] |
| `pal_i64_to_str` | 8 | extern | Int64 to decimal string | Returns length [inference] |
| `pal_u64_to_str` | 9 | extern | Uint64 to decimal string | [inference] |
| `pal_f64_to_str` | 10 | extern | Float64 to decimal string | [inference] |
| `__bootstrap_print` | 13 | decl | Legacy print | Delegates to std_print [inference] |
| `__bootstrap_print_int` | 14 | decl | Legacy int print | [inference] |
| `__bootstrap_print_char` | 15 | decl | Legacy char print | [inference] |
| `__bootstrap_panic` | 16 | decl | Legacy panic handler | Unused params suppressed [inference] |
| `__bootstrap_write` | 17 | decl | Legacy raw write | [inference] |
| `__bootstrap_sleep_ms` | 18 | decl | Legacy sleep | Busy-wait on non-Windows [inference] |
| `arena_alloc_default` | 21 | decl | Arena alloc entry point | Takes size in bytes [inference] |
| `zig_default_arena` | 22 | extern | Global arena pointer | [inference] |
| `std_panic` | 24 | decl | Print panic + abort | Used by zig1 emission [inference] |
| `std_print` / `std_print_len` | 25-26 | decl | Stdout string helpers | [inference] |
| `std_print_i32`..`std_print_f64` | 27-32 | decl | Typed print helpers | [inference] |
| `std_print_bool`/`std_print_char`/`std_print_str` | 33-34 | decl | Bool/char/slice print | [inference] |
| `std_checked_cast_*` | 35-42 | decl | Runtime checked numeric casts | Panics on overflow [inference] |

All declarations at `sf/src/include/zig_runtime.h`.

### `zig_runtime.c` — Runtime Implementations (`sf/src/include/zig_runtime.c:1-113`)

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|
| `std_panic` | 14 | extern | Panic handler: prints "panic: " + msg + "\n" then calls `pal_abort` | zig1 emitted code, checked casts | `pal_print_stderr`, `strlen`, `pal_abort` | none | Fatal — no return. Uses `pal_print_stderr` not `pal_print_stdout`. [inference] |
| `std_print` | 22 | extern | Print null-terminated string to stdout | zig1 emitted `std.debug.print` | `pal_print_stdout`, `strlen` | none | Null-safety check. [inference] |
| `std_print_len` | 23 | extern | Print string with explicit length | zig1 emitted slice print | `pal_print_stdout` | none | Requires both ptr and len > 0. [inference] |
| `std_print_i32` | 25 | extern | Format i32 as decimal, print | zig1 emitted debug | `pal_i64_to_str`, `std_print` | local `char[16]` | Uses i64 conversion internally. [inference] |
| `std_print_u32` | 31 | extern | Format u32 as decimal, print | zig1 emitted debug | `pal_u64_to_str`, `std_print` | local `char[16]` | [inference] |
| `std_print_i64` | 37 | extern | Format i64 as decimal, print | zig1 emitted debug | `pal_i64_to_str`, `std_print` | local `char[24]` | [inference] |
| `std_print_u64` | 43 | extern | Format u64 as decimal, print | zig1 emitted debug | `pal_u64_to_str`, `std_print` | local `char[24]` | [inference] |
| `std_print_f64` | 49 | extern | Format f64 as decimal, print | zig1 emitted debug | `pal_f64_to_str`, `std_print` | local `char[32]` | [inference] |
| `std_print_bool` | 55 | extern | Print "true" or "false" | zig1 emitted debug | `std_print` | none | [inference] |
| `std_print_char` | 60 | extern | Print single char | zig1 emitted debug | `pal_print_stdout` | none | Cast to `char`. [inference] |
| `std_print_str` | 62 | extern | Print u8 slice | zig1 emitted `std.debug.print` for slices | `pal_print_stdout` | none | Casts `const unsigned char*` to `const char*`. [inference] |
| `__bootstrap_print` | 67 | extern | Legacy alias for `std_print` | Legacy C output from old zig0 emission | `std_print` | none | Thin wrapper. [inference] |
| `__bootstrap_print_int` | 68 | extern | Legacy alias for `std_print_i32` | Legacy C output | `std_print_i32` | none | [inference] |
| `__bootstrap_print_char` | 69 | extern | Legacy alias, casts int to u8 | Legacy C output | `std_print_char` | none | [inference] |
| `__bootstrap_panic` | 70 | extern | Legacy alias, discards file/line | Legacy C output | `std_panic` | none | `(void)` cast on unused params. [inference] |
| `__bootstrap_write` | 71 | extern | Legacy alias for `std_print_len` | Legacy C output | `std_print_len` | none | [inference] |
| `__bootstrap_sleep_ms` | 72 | extern | Busy-wait sleep | Legacy C output | none | none | Non-Windows busy-loop. [inference] |
| `std_checked_cast_i8` | 76 | extern | Bounds-check u64→i8 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 127. [inference] |
| `std_checked_cast_u8` | 81 | extern | Bounds-check u64→u8 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 255. [inference] |
| `std_checked_cast_i16` | 86 | extern | Bounds-check u64→i16 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 32767. [inference] |
| `std_checked_cast_u16` | 91 | extern | Bounds-check u64→u16 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 65535. [inference] |
| `std_checked_cast_i32` | 96 | extern | Bounds-check u64→i32 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 2147483647. [inference] |
| `std_checked_cast_u32` | 101 | extern | Bounds-check u64→u32 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 4294967295. [inference] |
| `std_checked_cast_i64` | 106 | extern | Bounds-check u64→i64 | zig1 emitted checked casts | `std_panic` | none | Panics if val > 9223372036854775807. [inference] |
| `std_checked_cast_u64` | 111 | extern | Identity pass-through | zig1 emitted checked casts | none | none | No-op — u64 fits in u64. [inference] |

### `zig_pal.c` — Platform Abstraction Layer (`sf/src/include/zig_pal.c:1-189`)

| Function | Line | Visibility | Purpose | Called By | Calls | Data Touched | Key Decisions |
|----------|------|-----------|---------|-----------|-------|-------------|---------------|
| `pal_strlen` | 22 | static (file) | String length — Win32 fallback, Unix wraps `strlen` | (none — unused) | (none) or `strlen` | none | Win32 avoids stdlib; Unix uses it. [inference] |
| `pal_memcpy` | 33 | static (file) | Memory copy — Win32 byte loop, Unix wraps `memcpy` | (none in current code) | (none) or `memcpy` | none | [inference] |
| `pal_reverse` | 44 | static (file) | In-place char buffer reversal | `pal_u64_to_str_buf` | none | local buf | Two-pointer swap. [inference] |
| `pal_u64_to_str_buf` | 57 | static (file) | Unsigned int to decimal string in buffer | `pal_u64_to_str`, `pal_i64_to_str` | `pal_reverse` | local buf | Reverse digit extraction. Handles zero. [inference] |
| `pal_print_stderr` | 76 | extern | Write `len` bytes to stderr (fd 2) | `std_panic`, diagnostics | `write` (Unix) or `WriteConsoleA`/`WriteFile` (Win32) | none | Win32: tries Console first, falls back to File. [inference] |
| `pal_print_stdout` | 91 | extern | Write `len` bytes to stdout (fd 1) | `std_print`, `std_print_len`, `std_print_char`, `std_print_str` | `write` (Unix) or `WriteConsoleA`/`WriteFile` (Win32) | none | Same dual-path as stderr. [inference] |
| `pal_abort` | 106 | extern | Abort process | `std_panic` | `abort()` (Unix) or `TerminateProcess` (Win32) | none | Win32 uses exit code 3. [inference] |
| `pal_i64_to_str` | 115 | extern | Signed 64-bit to decimal string | `std_print_i32`, `std_print_i64` | `pal_u64_to_str_buf` | local buf | Two's complement safe neg: `-(value+1)+1`. [inference] |
| `pal_u64_to_str` | 136 | extern | Unsigned 64-bit to decimal string | `std_print_u32`, `std_print_u64` | `pal_u64_to_str_buf` | local buf | Thin wrapper. [inference] |
| `pal_f64_to_str` | 141 | extern | Double to decimal string (6 fractional digits) | `std_print_f64` | `pal_i64_to_str` | local buf | Strips trailing zeros. Integer part via i64 conv, fraction via loop*10. [inference] |
| `mainCRTStartup` | 182 | Win32 only | CRT-less Win32 entry point | Win32 loader | `main`, `ExitProcess` | none | Only compiled with `ZIG_NO_CRT`. [inference] |

### `zig_special_types.h` — Stub (`sf/src/include/zig_special_types.h:1-4`)

| Decl | Line | Notes |
|------|------|-------|
| `#include "zig_compat.h"` | 3 | Empty beyond include; reserved for future type tables [inference] |

### Legacy Arena Allocator (`src/runtime/zig_runtime.c` — linked separately)

| Function | Line | Visibility | Purpose | Called By | Calls | Key Decisions |
|----------|------|-----------|---------|-----------|-------|---------------|
| `arena_create` | 71 | extern | Create new arena with `initial_capacity` bytes | `arena_alloc` (lazy init), user code | `platform_alloc` | Default 16KB min. Linked-block list. [inference] |
| `arena_alloc` | 93 | extern | Allocate `size` bytes from arena | `arena_alloc_default`, user code | `platform_alloc` | 8-byte alignment. Lazy-init default arena if arg is NULL. Doubles block size on overflow. [inference] |
| `arena_free` | 158 | extern | No-op — individual arena allocations cannot be freed | User code | none | No-op. Use `arena_reset` or `arena_destroy` for bulk free. [inference] |
| `arena_alloc_default` | 154 | extern | Allocate from default arena (NULL arg shortcut) | zig1 emitted code | `arena_alloc(NULL, size)` | Lazily creates 1MB default arena on first call via `zig_default_arena` global. [inference] |
| `arena_reset` | 131 | extern | Reset all blocks to empty | User code | none | Walks block list, sets used=0 on each. Keeps blocks allocated. [inference] |
| `arena_destroy` | 142 | extern | Free all blocks + arena struct | User code | `platform_free` | Not called during normal operation. [inference] |
| `zig_default_arena` | 31 | global | Global arena pointer | `arena_alloc` lazy init | none | Initialized to NULL; created on first use. [inference] |

---

## Data Flow

```
zig1 emitted C89 code
  │
  ├─ std.debug.print(...) → std_print*(...) → pal_print_stdout → write(1,...)
  ├─ @panic(...) → std_panic(msg) → pal_print_stderr("panic: ...") → pal_abort → abort()
  ├─ @intCast(T, val) → std_checked_cast_T(val) → range check → return/panic
  ├─ arena alloc → arena_alloc_default(n) → arena_alloc(NULL, n) → platform_alloc → malloc/VirtualAlloc
  │                  └─ if NULL: lazy init zig_default_arena → arena_create(1MB)
  ├─ Slice type → struct { ptr; len; } (emitted by zig1 codegen)
  ├─ Optional type → struct { payload; has_value; } (emitted by zig1 codegen)
  └─ ErrorUnion type → struct { payload; error_code; } (emitted by zig1 codegen)
```

**C89 type chain:**
```
zig_compat.h → i8/u8/i16/u16/i32/u32/i64/u64/f32/f64/usize/bool
    └─ zig_runtime.h includes zig_compat.h, adds arena/panic/print/cast decls
    └─ zig_special_types.h includes zig_compat.h (stub)
```

**Build linking (from QUICK_REF):**
```
gcc -m32 -std=c89 ... /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

---

## Debugging

- **Link errors `undefined reference`** — missing `sf/src/include/zig_runtime.c` or `sf/src/include/zig_pal.c` in gcc link step. Both must be linked explicitly.
- **Assert/panic at runtime** — `std_panic` / `std_checked_cast_*` reachable. Check overflow values or add `pal_print_stderr` markers before the panic site.
- **`arena_alloc_default` not found** — this symbol is in the legacy `src/runtime/zig_runtime.c`, NOT in `sf/src/include/`. For sf-linked binaries, zig1 emits its own arena allocator; the legacy symbol is only for zig0-output programs.
- **Slice/Optional/ErrorUnion struct layout** — these are NOT in any header; zig1's C89 emission generates type-specific structs per module. Layout is: Slice = `{ ptr; len }`, Optional = `{ payload; has_value }`, ErrorUnion = `{ payload; error_code }`.
- **`__bootstrap_print_int` / `__bootstrap_sleep_ms`** — backward compat stubs. New code should use `std_print_*` / platform `sleep()`.
- **`pal_abort` vs `abort()`** — Win32: `TerminateProcess(GetCurrentProcess(), 3)`. Unix: `abort()`. Not recoverable.
