# 10 — C Runtime Layer [updated: 2026-11-08 — Phase 3.5 Task 3 (D8): the `@stdoutWrite`/`@stderrWrite`/`@putChar`/`@getChar` builtins now lower to the PAL (`pal_print_stdout`/`pal_print_stderr`/new `pal_putchar`/new `pal_getchar`), so the stdout family is one unbuffered OS-native stack and no longer emits `<stdio.h>`/`fwrite`/`putchar`/`getchar`. The D8 section below now carries the post-fix C-runtime inventory and the reduction path toward a C-free backend.] [updated: 2026-10-28 — Phase 2.5 Task 9 (emission warning-clean at the origin): the `-fsafe` helpers (`zig_ovf_*`, `zig_wrap_*`, `zig_overflow_flag_*`, `zig_cast_checked_s/u`) and the `__bootstrap_*` casts are now **external definitions in `zig_runtime.c` + prototypes in `zig_runtime.h`** (no longer header statics) — one definition per program, link-level ABI; `zig_pal.c` gained a POSIX feature-selection preamble (`_DEFAULT_SOURCE` before libc headers) so `readlink`/`usleep` are declared under strict `-std=c89`. Runtime/support text has ONE hand-edited source, `sf/src/emit_support.zig`; `sf/src/include/*` + `sf/src/c_exit.c` are generated snapshots refreshed by `scripts/gen_emit_support.sh` and guarded by `scripts/check_emit_support.sh`. New gate `scripts/compiler/gate_warn_clean.sh` (gcc `-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long`, sole suppression) compiles the runtime TUs.] [updated: 2026-09-25 — Task 2 (z98-print-formatting): `pal_f64_to_str` (both lockstep copies) omits the `'.'`+fraction for an integral value (`7.0` → `7`); `std_fmt.zig`'s `printHexI32/I64` print `-` + hex magnitude for negative values (Zig oracle); the Q2 float residuals are unchanged.][updated: 2026-09-24 — Task 1 (z98-print-formatting): the `std_print_i32/u32/i64/u64/f64/bool/char/str/hex_*` formatting bodies were retired from `zig_runtime.c` (canonical) and `emit_support.zig` (emitted copy) and now live in the Z98 std module `sf/src/std_fmt.zig` (`std.fmt`), called through the same PAL primitives (`pal_print_stdout` + `pal_i64/u64/f64_to_str`). `std_print`/`std_print_len` remain the raw-bytes runtime helpers.] [updated: 2026-09-20 — refreshed against current source: `pal_trap`/trap handler, `pal_file_read`/`pal_dir_exists`/`pal_get_default_lib_path`, 15 print helpers incl. hex, 20 `__bootstrap_*` helpers, the `-fsafe` overflow/checked-cast/poison helpers, the three target-neutral preludes, `c_exit.c`, and the dead `extern_c_z98.zig`; emitted-support relationship now via `emit_support.zig`; line references and dated evidence removed]

> Covers: `sf/src/include/*`, `c_exit.c`, `extern_c.zig`, `extern_c_z98.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Header files | 8 | `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h`, `net_prelude.h`, `std_os_prelude.h`, `std_time_prelude.h`, `net_runtime.h` (legacy), `optstar_repro.h` (repro stub) |
| C source files | 3 | `zig_runtime.c`, `zig_pal.c`, `net_runtime.c` (legacy, unlinked) |
| PAL functions | 17 | `pal_print_stderr`/`stdout`, `pal_putchar`, `pal_getchar`, `pal_set_trap_handler`, `pal_abort`, `pal_trap`, `pal_i64/u64/f64_to_str`, `pal_file_open`/`read`/`write`/`close`, `pal_dir_exists`, `pal_get_default_lib_path`, `mainCRTStartup` (Win32 `ZIG_NO_CRT`), plus 4 file-static helpers |
| Runtime print helpers | 3 | `std_panic`, `std_print`, `std_print_len` — the typed `std_print_i32/u32/i64/u64/f64/bool/char/str/hex_*` formatting bodies moved to `sf/src/std_fmt.zig` (`std.fmt`) in Task 1, 2026-09-24 |
| Checked cast functions | 8 | `std_checked_cast_i8..u64` — **legacy, NOT emitted by zig1** (upper-bound-only) |
| `__bootstrap_<DST>_from_<SRC>` helpers | 20 | Retained `@intCast` range-check support: external defs in `zig_runtime.c` + prototypes in `zig_runtime.h`; panic `"integer cast overflow in @intCast"` on out-of-range. The emitter no longer selects them (see `08_c89_emission.md`) |
| `-fsafe` helpers | 28 | 25 wrap/overflow-flag helpers + 2 width/sign-aware `zig_cast_checked_s/u` + `zig_poison_fill`; external defs in `zig_runtime.c` (prototypes in the header), emitted only under `-fsafe` |
| Backward compat aliases | 0 | `__bootstrap_print*`/`write`/`sleep_ms`/`panic` REMOVED (F4, 2026-08-08) |
| Legacy arena functions | 6 | `arena_create`/`alloc`/`free`/`reset`/`destroy`/`alloc_default` in `src/runtime/zig_runtime.c` (outside `sf/src`) |
| Type tables | emitted | Slice/Optional/ErrorUnion structs emitted by zig1 codegen (see `08_c89_emission.md`); `zig_special_types.h` is an include stub |
| `extern_c*.zig` | 3 decls each | `write`, `__bootstrap_print`, `__bootstrap_print_int` |

---

## Function Walkthrough

### `zig_compat.h` — C89 Type Definitions

`zig_compat.h` is the base C89 compatibility layer. All typedefs are global.

| Decl | Visibility | Purpose | Notes |
|------|-----------|---------|-------|
| `z64`/`zu64` | global | 64-bit integer platform abstraction | `_MSC_VER` → `__int64`; otherwise `long long` |
| `i8`..`u64` | global | Fixed-width integer types | Guarded by `!defined(__cplusplus) && !defined(__WATCOMC__)`; `i64` = `z64`, `u64` = `zu64` |
| `f32`/`f64` | global | Float types | `float`/`double` |
| `usize` | global | 32-bit unsigned (`unsigned int`) — NOT pointer-sized | Z98 `usize` always compiles to 32-bit regardless of `-m32`/`-m64`, which is why the fd/handle ABI stays 32-bit everywhere |
| `bool`/`true`/`false` | global | Boolean type | C89 has no `_Bool`; `bool` is `int`, `true`=1, `false`=0 (outside the `__cplusplus` guard) |
| `NULL` | global | Null pointer macro | `((void*)0)` if not already defined |
| `Z98_STDCALL` | global | Calling-convention macro | Empty on non-Win32; `__stdcall` on MSVC/Watcom; `__attribute__((stdcall))` otherwise. Used by emitted `stdcall` externs and the `FS_...` fn-pointer typedefs (see `08_c89_emission.md`) |

All typedefs at `sf/src/include/zig_compat.h`.

> **Source of truth (Phase 2.5 T9):** `sf/src/emit_support.zig` is the only hand-edited support source; `sf/src/include/*` and `sf/src/c_exit.c` are generated snapshots refreshed by `scripts/gen_emit_support.sh` and verified by `scripts/check_emit_support.sh` (8/8).

### `zig_runtime.h` — Header Declarations

`zig_runtime.h` includes `zig_compat.h` and declares the PAL, arena, print, and cast surface, plus prototypes for the `-fsafe` and `__bootstrap_*` helpers (definitions live in `zig_runtime.c`).

| Decl | Visibility | Purpose | Notes |
|------|-----------|---------|-------|
| `pal_print_stderr` | extern | Raw stderr write | Takes `(const char*, unsigned int len)` |
| `pal_abort` | extern | Abort process | |
| `pal_trap` | extern | Trap (`int3`) with an optional Z98-installed handler | Called by `std_panic` and the `-fsafe` guard failures |
| `pal_i64_to_str` / `pal_u64_to_str` / `pal_f64_to_str` | extern | Int64/Uint64/Float64 to decimal string | Return length |
| `zig_poison_fill` | extern | `-fsafe` `undefined` poison (`0xAA` fill) | Present in the canonical sources; emitted only under `-fsafe` |
| `zig_ovf_*`, `zig_wrap_*`, `zig_overflow_flag_*` | extern | `-fsafe` UB-free wrap and overflow-flag math | Defined once in `zig_runtime.c` (prototypes here); emitted only under `-fsafe` |
| `arena_alloc_default` | decl | Default-arena entry point | Defined in the legacy `src/runtime/zig_runtime.c`, not in `sf/src/include` |
| `zig_default_arena` | extern | Global arena pointer | |
| `std_panic` | decl | Print panic + trap | Used by zig1 emission |
| `std_print` / `std_print_len` | decl | Stdout string helpers (raw bytes; format-string literal segments + console) | |
| `std_print_i32`..`std_print_hex_i64` | decl | **Bodies moved (Task 1, 2026-09-24)** — the declarations are retained in `zig_runtime.h` for compatibility, but the definitions were retired from `zig_runtime.c`/`emit_support.zig`; the formatting bodies now live in `sf/src/std_fmt.zig` (`std.fmt`); see `08_c89_emission.md` | |
| `std_checked_cast_*` | decl | Legacy upper-bound-only numeric casts | Panic `"int cast overflow for <T>"`; NOT emitted by zig1 |
| `c_char` + `__bootstrap_<DST>_from_<SRC>` (20) | typedef + prototypes | Retained `@intCast` range-check helpers | prototypes here + external defs in `zig_runtime.c`; the emitter now uses `zig_cast_checked_s/u` instead |
| `zig_cast_checked_s` / `zig_cast_checked_u` | extern | `-fsafe` width/sign-aware checked `@intCast` | Defined in `zig_runtime.c` (prototype here); emitted only under `-fsafe` |

All declarations at `sf/src/include/zig_runtime.h`.

### `zig_runtime.c` — Runtime Implementations

| Function | Visibility | Purpose | Calls | Key Decisions |
|----------|-----------|---------|-------|---------------|
| `std_panic` | extern | Prints `"panic: "` + msg + `"\n"` to stderr, then calls `pal_trap` | `pal_print_stderr`, `strlen`, `pal_trap` | Fatal — no return; uses `pal_print_stderr`, not `pal_print_stdout` |
| `std_print` | extern | Print null-terminated string to stdout | `pal_print_stdout`, `strlen` | Null-safety check; raw bytes for the `.print_str` literal segments |
| `std_print_len` | extern | Print string with explicit length | `pal_print_stdout` | Requires both ptr and len non-zero; raw bytes for the console builtins |
| ~~`std_print_i32`..`std_print_hex_i64`~~ | — | **MOVED (Task 1, 2026-09-24)** — the formatting bodies are now `sf/src/std_fmt.zig` (`std.fmt`) re-implementations over the same PAL primitives | `pal_print_stdout`, `pal_i64/u64/f64_to_str` | The compiler emits mangled `std.fmt` calls; the C definitions are retired from `zig_runtime.c` + `emit_support.zig` |
| `std_checked_cast_i8`..`std_checked_cast_u64` (8) | extern | Upper-bound-only u64→target casts | `std_panic` | **Legacy — not emitted** (use `zig_cast_checked_s/u`); `u64` is an identity pass-through |
| `__bootstrap_<DST>_from_<SRC>` (20) | extern | Range-checked `@intCast` support | `std_panic` | Retained; the emitter no longer selects them (see `08_c89_emission.md`) |
| `zig_poison_fill` | extern | `-fsafe` `undefined` poison (`0xAA` fill) | none | Emitted only under `-fsafe` |

The live `zig_runtime.c` no longer defines the `__bootstrap_print*`/`__bootstrap_write`/`__bootstrap_sleep_ms`/`__bootstrap_panic` backward-compat aliases (removed F4, 2026-08-08).

### `zig_pal.c` — Platform Abstraction Layer

| Function | Visibility | Purpose | Called By | Calls | Key Decisions |
|----------|-----------|---------|-----------|-------|---------------|
| `pal_strlen` | static | String length | (unused) | `strlen` (Unix) | Win32 manual loop; Unix wraps libc |
| `pal_memcpy` | static | Memory copy | (unused) | `memcpy` (Unix) | Win32 byte loop; Unix wraps libc |
| `pal_reverse` | static | In-place char buffer reversal | `pal_u64_to_str_buf` | none | Two-pointer swap |
| `pal_u64_to_str_buf` | static | Unsigned int to decimal string | `pal_u64_to_str`, `pal_i64_to_str` | `pal_reverse` | Reverse digit extraction; handles zero |
| `pal_print_stderr` | extern | Write `len` bytes to stderr (fd 2) | `std_panic`, diagnostics, `@stderrWrite` | `write` / `WriteConsoleA`+`WriteFile` | Win32 tries Console then File |
| `pal_print_stdout` | extern | Write `len` bytes to stdout (fd 1) | `std_print`, `std_print_len`, `std.fmt` printers (`std_fmt.zig`), `std.io`/`std.debug`, `@stdoutWrite` | `write` / `WriteConsoleA`+`WriteFile` | Same dual-path as stderr; **unbuffered on POSIX** (`write(1)`) — one stack with the `std.fmt` printers |
| `pal_putchar` | extern | Write one byte to stdout | `@putChar` / `std_io.writeByte` | `write(1,…)` / `WriteConsoleA`+`WriteFile` | Returns the byte on success, `-1` on write failure; unbuffered like `pal_print_stdout` |
| `pal_getchar` | extern | Read one byte from stdin | `@getChar` / `std_io.readByte` | `read(0,…)` / `ReadFile` | Returns the byte (0–255) or `-1` at EOF/error |
| `pal_set_trap_handler` | extern | Install a Z98 trap handler | `std_debug.zig` | none | `TrapContext` layout must match `std_debug.zig` (10 × `unsigned int`) |
| `pal_abort` | extern | Abort process | `pal_trap` fallback | `abort()` / `TerminateProcess` | Win32 uses exit code 3 |
| `pal_trap` | extern | Invoke handler, then `int3` | `std_panic`, `-fsafe` guards | `g_trap_handler`, inline asm, `pal_abort` | Register capture GCC/x86-only; `int3` on x86, `pal_abort` elsewhere |
| `pal_i64_to_str` | extern | Signed 64-bit to decimal string | `std.fmt.printI32`/`printI64` (`std_fmt.zig`); historically `std_print_i32`/`std_print_i64` | `pal_u64_to_str_buf` | Two's-complement-safe negate: `-(value+1)+1` |
| `pal_u64_to_str` | extern | Unsigned 64-bit to decimal string | `std.fmt.printU32`/`printU64`; historically `std_print_u32`/`std_print_u64` | `pal_u64_to_str_buf` | Thin wrapper |
| `pal_f64_to_str` | extern | Double to decimal string (integral values with no fraction; else up to 6 fractional digits) | `std.fmt.printF64`; historically `std_print_f64` | `pal_i64_to_str` | Strips trailing zeros; integer part via i64, fraction via loop ×10. **Task 2:** an integral value (`(f64)(i64)value == value`) returns after the integer digits with no `'.'` (`7.0` → `7`); the non-integral 6-digit truncation / `1e20` cast UB / `-0.0` → `0` are documented Q2 residuals |
| `pal_file_open` | extern | Open existing file for read (`PAL_FILE_OPEN_READ`) or create/truncate for write (`PAL_FILE_OPEN_WRITE`) | zig1 `fileOpen`, `std_io` | `open` / `CreateFileA` | Returns a `PlatFile`; `PLAT_INVALID_FILE` on failure; POSIX `O_WRONLY\|O_CREAT\|O_TRUNC\|flags, 0644` |
| `pal_file_read` | extern | Read up to `len` bytes (EINTR-retrying) | zig1 `fileRead`, `std_io` | `read` / `ReadFile` | `-1` on error, else bytes read |
| `pal_file_write` | extern | Write `len` bytes with partial-write loop | zig1 `fileWrite`, `std_io` | `write` / `WriteFile` | Loops until all bytes written; `-1` on error |
| `pal_file_close` | extern | Close a `PlatFile` | zig1 `fileClose`, `std_io` | `close` / `CloseHandle` | |
| `pal_dir_exists` | extern | Directory existence test | `pal.zig` `dirExists` (CLI output-dir check `main.zig:164` + default lib-dir lookup `main.zig:437`) | `stat` / `GetFileAttributesA` | POSIX checks the `S_IFDIR` bit. Task 5B: the default lib path `<exe_dir>/lib` is a directory, so this probe (not `pal_file_exists`/`fopen`) guards it. [updated: 2026-09-22 — Task 5B] |
| `pal_get_default_lib_path` | extern | Compute the compiler-relative `<exe_dir>/lib` path | `pal.zig` | `readlink("/proc/self/exe")` / `GetModuleFileNameA` | Returns the written path length, or 0 on failure |
| `mainCRTStartup` | Win32 only | CRT-less Win32 entry point | Win32 loader | `main`, `ExitProcess` | Compiled only with `ZIG_NO_CRT` |

`PlatFile` is `void*` on Win32 and `int` on POSIX; `PLAT_INVALID_FILE` is `((void*)-1)` / `(-1)`. This matches the `pal.zig` wrappers, which read the handle as a 32-bit `usize`. A 64-bit-Windows `HANDLE` still would not fit — a pre-existing, out-of-scope limitation (target is 32-bit Windows 9x/NT per `docs/sf/AGENTS.md` §0.1).

### `zig_special_types.h` — Stub

| Decl | Notes |
|------|-------|
| `#include "zig_compat.h"` | Empty beyond the include; reserved for future type tables. Slice/Optional/ErrorUnion structs are emitted per-module by zig1 codegen, not here |

### Prelude headers — `net_prelude.h`, `std_os_prelude.h`, `std_time_prelude.h`

Target-neutral include preludes selected at C-compile time (`_WIN32`). Each is emitted into the output directory only when a reachable module carries the matching `@cInclude`, so a stdio-only program carries none.

- **`net_prelude.h`** — Winsock/libc includes for the `std_net` extern surface, plus the `_os` aliases `accept_os`/`connect_os`/`send_os`/`recv_os`/`close_os`/`select_os` (declared after the includes; `std_net`'s public API owns the unsuffixed names). See `std_net.zig`.
- **`std_os_prelude.h`** — `getcwd`/`getenv`/`exit`/`GetCurrentDirectoryA` for `std_os`/`std_file`/`std_stdin`.
- **`std_time_prelude.h`** — `time`/`clock_gettime`/`gettimeofday` for `std_time`, the `Z98_HAS_CLOCK_MONOTONIC` compile-time probe, `z98_time_clock_monotonic_available()`, and `z98_time_monotonic_ns()` (POSIX only; Win32 uses `QueryPerformanceCounter`).

### Legacy Arena Allocator (`src/runtime/zig_runtime.c` — outside `sf/src`, linked separately)

| Function | Visibility | Purpose | Key Decisions |
|----------|-----------|---------|---------------|
| `arena_create` | extern | Create arena with `initial_capacity` bytes | 16 KB min; linked-block list |
| `arena_alloc` | extern | Allocate `size` bytes | 8-byte alignment; lazy-init default arena if arg is NULL; doubles block size on overflow |
| `arena_free` | extern | No-op — individual arena allocations cannot be freed | Use `arena_reset`/`arena_destroy` for bulk free |
| `arena_alloc_default` | extern | Allocate from default arena (NULL arg shortcut) | Lazily creates a 1 MB default arena via `zig_default_arena` |
| `arena_reset` | extern | Reset all blocks to empty | Keeps blocks allocated |
| `arena_destroy` | extern | Free all blocks + arena struct | Not called during normal operation |
| `zig_default_arena` | global | Global arena pointer | Initialized NULL; created on first use |

The current emitter does not call this allocator for user programs; it is the definition site for the vestigial `arena_alloc_default`/`zig_default_arena` declarations in `zig_runtime.h`.

### `extern_c.zig` / `extern_c_z98.zig` — Extern Declarations

Both files declare the same three C symbols:

```zig
pub extern fn write(fd: i32, buf: [*]const u8, count: i32) i32;
pub extern fn __bootstrap_print(s: [*]const u8) void;
pub extern fn __bootstrap_print_int(n: i32) void;
```

`extern_c.zig` is the live form: `pal.zig`, `main_exp.zig`, and `test_a.zig` import it (`pal.zig` uses `ext_c.write`). `extern_c_z98.zig` is the Z98-native variant with `const _ = @cInclude("pal.h")` / `@cInclude("zig_runtime.h")` capture lines; it is **dead** — not imported by the 40-module build, and `pal.h` is not in the tree.

### `c_exit.c`

`sf/src/c_exit.c` defines `void c_exit(int code) { exit(code); }`. It backs the `extern "c" fn c_exit` in `pal.zig` (the CLI's exit path) and is one of the emitted support files.

### Emitted support files (`emit_support.zig`)

The compiler does not link the `sf/src/include/*` files at emission time; `emit_support.zig` holds their canonical bytes as Z98 string constants and writes them into the output directory, so the emitted tree is self-contained. `scripts/check_emit_support.sh` asserts emitted == canonical byte-for-byte. The emitted set is `zig_compat.h`, `zig_runtime.h`, `zig_runtime.c`, `zig_pal.c`, `c_exit.c` (always) plus the conditionally-emitted `net_prelude.h`/`std_os_prelude.h`/`std_time_prelude.h`. `zig_special_types.h` and the per-module `.c`/`.h` are emitted by the C89 emitter. The old `emitZigPalC`/`emitZigRuntimeC` dead stale mirrors were **removed** from `c89_emit.zig` at the print-formatting plan closeout (Task 7, 2026-09-25); the live bytes come from `emit_support.zig` only. The older `emitZigCompatH` mirror is still present, pre-existing dead code (zero call sites), and was left in place deliberately at that closeout to avoid a post-rotation source change. See `08_c89_emission.md` §6 for the full function table and companion build scripts.

---

## Data Flow

```
zig1 emitted C89 code
  │
  ├─ std.io.write/writeStr/printInt, std.debug.log/logInt, @stdoutWrite, @putChar → pal_print_stdout / pal_putchar → write(1,…)
  ├─ @stderrWrite → pal_print_stderr → write(2,…)
  ├─ @getChar / std.io.readByte → pal_getchar → read(0,…)
  ├─ std.io.print(fmt, .{...}) → mangled std.fmt.<printer>(...) (std_fmt.zig) → pal_print_stdout → write(1,…)
  ├─ @panic(...) → std_panic(msg) → pal_print_stderr("panic: " + msg) → pal_trap() → int3 / pal_abort
  ├─ @intCast(T, val) checked [-fsafe] → zig_cast_checked_s/u(val, src_w, src_s, dst_w) → range check → return/trap
  ├─ legacy `__bootstrap_<DST>_from_<SRC>` helpers — retained, no longer selected by the emitter
  ├─ legacy `std_checked_cast_*` (upper-bound-only) — not emitted by zig1
  ├─ -fsafe wrap/flag ops → zig_wrap_* / zig_overflow_flag_* ; undefined → zig_poison_fill
  ├─ legacy arena alloc → arena_alloc_default(n) → arena_alloc(NULL, n) → platform_alloc → malloc/VirtualAlloc
  │                  └─ if NULL: lazy init zig_default_arena → arena_create(1MB)
  ├─ Slice type → struct { ptr; len; } (emitted by zig1 codegen)
  ├─ Optional type → struct { payload; has_value; } (emitted by zig1 codegen)
  └─ ErrorUnion type → struct { payload; error_code; } (emitted by zig1 codegen)
```

**C89 type chain:**
```
zig_compat.h → i8/u8/i16/u16/i32/u32/i64/u64/f32/f64/usize/bool
    └─ zig_runtime.h includes zig_compat.h, adds PAL/arena/print/cast decls + -fsafe helpers
    └─ zig_special_types.h includes zig_compat.h (stub)
```

**Build linking:** a program built from `--dump-c89` output links the emitted support `.c` files
(`zig_runtime.c`, `zig_pal.c`, `c_exit.c`) from its output directory, not the `sf/src/include/*`
sources. **zig1's own build** (`sf/scripts/build_release.sh`) links `sf/src/include/zig_pal.c`
into the compiler binary — it defines `pal_file_*` plus `pal_dir_exists`/`pal_get_default_lib_path`,
which the `pal.zig` wrappers (`fileOpen`/`fileWrite`/`fileClose`/`dirExists`) call. `dirExists`
probes a directory via `pal_dir_exists` and is used both for the CLI output-dir check and for the
default lib-dir lookup (`<exe_dir>/lib`, Task 5B). Any manual zig1
rebuild MUST include it in the gcc line, else the link fails with `undefined reference to
'pal_file_open'` / `pal_file_write` / `pal_file_close`.

---

## Debugging

- **Link errors `undefined reference`** — missing `sf/src/include/zig_pal.c` (or `zig_runtime.c`) in a manual gcc link step. zig1's own build (`sf/scripts/build_release.sh`) links `sf/src/include/zig_pal.c` into the compiler binary because `pal.zig`'s wrappers call `pal_file_*`, `pal_dir_exists`, and `pal_get_default_lib_path`; a manual zig1 rebuild must include it too. A program built from `--dump-c89` output instead links the emitted `zig_runtime.c`/`zig_pal.c`/`c_exit.c` from its output directory.
- **Assert/panic at runtime** — `std_panic`, `zig_cast_checked_s/u`, or the retained `__bootstrap_<DST>_from_<SRC>` helpers are reachable. `std_panic` now ends in `pal_trap()` (`int3`), not `pal_abort()`, so a debugger stops on the trap. Check overflow values or add `pal_print_stderr` markers before the panic site.
- **`arena_alloc_default` not found** — this symbol is defined in the legacy `src/runtime/zig_runtime.c`, NOT in `sf/src/include/`. zig1 emits its own arena for user programs; the legacy symbol is only for zig0-output programs.
- **Slice/Optional/ErrorUnion struct layout** — these are NOT in any header; zig1's C89 emission generates type-specific structs per module (see `08_c89_emission.md`). Layout is: Slice = `{ ptr; len }`, Optional = `{ payload; has_value }`, ErrorUnion = `{ payload; error_code }`.
- **`pal_trap` vs `pal_abort`** — `pal_trap` invokes the Z98-installed handler (if any), then executes `int3` on x86 (MSVC/Watcom `__asm { int 3 }`) or falls back to `pal_abort` elsewhere. Win32 `pal_abort` is `TerminateProcess(GetCurrentProcess(), 3)`; Unix `abort()`. Not recoverable.

---

## Known Issues

- **`__bootstrap_print` / `__bootstrap_print_int` are declared with no live definition.** `extern_c.zig` declares them and the `zig_runtime.h`/`zig_runtime.c` backward-compat aliases were removed (F4, 2026-08-08); the live runtime defines neither, and the last copy (the dead `emitZigRuntimeC` mirror in `c89_emit.zig`) was removed at the print-formatting closeout (Task 7, 2026-09-25). `pal.zig` uses only `ext_c.write`, so no live release caller links against them; they are retained legacy import surface.
- **PAL output functions are not declared in `zig_runtime.h`.** `pal_print_stdout`, `pal_print_stderr`, `pal_putchar` and `pal_getchar` are defined in `zig_pal.c`; `zig_runtime.h` only declares `pal_print_stderr` plus the non-output PAL surface. An emitted TU that calls the output PAL supplies its own C89 old-style declarations: `std_fmt.zig`/`std_io.zig` declare them `extern "c"`, and since Phase 3.5 Task 3 the C89 emitter writes no-prototype declarations (`extern void pal_print_stdout();` / `extern int pal_putchar();`) into any module that lowers `@stdoutWrite`/`@stderrWrite`/`@putChar`/`@getChar`.
- **`net_runtime.c` / `net_runtime.h` are dead.** None of the 12 socket helpers declared in `net_runtime.h` are referenced by `sf/src`; 6 carry the `plat_socket_*` prefix (`plat_socket_init`/`cleanup`/`select`/`fd_zero`/`fd_set`/`fd_isset`), the other 6 are the remaining socket helpers (`plat_create_tcp_server`, `plat_bind_listen`, `plat_accept`, `plat_recv`, `plat_send`, `plat_close_socket`). `std_net` is now the extern surface via `net_prelude.h`. The file remains only for legacy/pre-F6 example builds.
- **`optstar_repro.h` is a repro stub** referencing `extFn` and `fopen` with mangled types; it is included by no live TU.
- **`extern_c_z98.zig` is dead.** It is not imported by the 40-module build, and its `@cInclude("pal.h")` names a header that is not present in the tree.
- **`usize` is 32-bit even on 64-bit hosts**, so a 64-bit Windows `HANDLE` cannot round-trip through `PlatFile`/`usize`; the supported target is 32-bit Windows 9x/NT.

---

## D8 — stdout family is one PAL stack [fixed: 2026-11-08 — Phase 3.5 Task 3]

**Status:** FIXED. The four stdout-family compiler builtins lower to the PAL, so
`@stdoutWrite`/`@stderrWrite`/`@putChar`/`@getChar`, `std.io`, `std.debug` and
`std.fmt` share one unbuffered OS-native stack on both the CRT and no-CRT
profiles. `examples/torrent_example_defects.md` D8 was deleted. D8 had no
pre-fix RED: its fixture (`repro/mi_matrix/known_excluded/stdout_order_ok`)
passed by luck because the buffered C-stdio data happened to flush at normal
exit after the unbuffered PAL writes; it is the post-fix regression oracle.

### What changed

- The emitter now lowers `.builtin_stdout_write`/`.builtin_stderr_write` to
  `pal_print_stdout`/`pal_print_stderr`, `.builtin_put_char` to `pal_putchar`,
  and `.builtin_get_char` to `pal_getchar` (`sf/src/c89_emit.zig`).
- `#include <stdio.h>` is no longer emitted for those builtins;
  `moduleHasStdoutFamily` instead writes no-prototype PAL declarations into the
  module `.c`. Programs that use `@consoleClear`/`@consoleGotoxy`/
  `@consoleSetColor` still include `<stdio.h>` for their own `sprintf` path,
  which is unrelated to D8.
- `sf/src/emit_support.zig` gained `pal_putchar` (one-byte stdout write) and
  `pal_getchar` (one-byte stdin read) over the same POSIX `write`/`read` and
  Win32 `WriteConsoleA`/`WriteFile`/`ReadFile` primitives as the existing PAL
  print functions. `sf/src/include/zig_pal.c` was regenerated from that single
  source; `sf/src/include/*` must not be hand-edited.
- The `zig_nocrt.c` C-stdio shims (`fwrite`, `putchar`, `getchar`, …) were left
  in place for compatibility with externally-authored C, but no emitted Z98
  stdout-family call reaches them any more. The Win9x no-CRT binary imports only
  `KERNEL32.dll` (verified with `objdump -p`).

### Current C-runtime surface (post-D8)

| Surface | Provider | Used by | Notes |
|---|---|---|---|
| stdout/stderr bytes | `zig_pal.c`: `pal_print_stdout`, `pal_print_stderr`, `pal_putchar` | `@stdoutWrite`, `@stderrWrite`, `@putChar`, `std_io`, `std_debug`, `std_fmt` | POSIX `write(1/2,…)`; Win32 `WriteConsoleA` then `WriteFile`; unbuffered |
| stdin bytes | `zig_pal.c`: `pal_getchar` | `@getChar`, `std_io.readByte` | POSIX `read(0,…)`; Win32 `ReadFile` |
| formatted output bodies | `sf/src/std_fmt.zig` | `std.io.print(fmt, …)` | Z98 code over `pal_print_stdout` + `pal_i64/u64/f64_to_str` |
| panic / trap | `zig_runtime.c` `std_panic`; `zig_pal.c` `pal_trap`, `pal_abort`, `pal_set_trap_handler` | `@panic`, `assert`, `-fsafe` guards | Ends in `int3`/`TerminateProcess`/`abort` |
| checked casts / overflow | `zig_runtime.c`: `__bootstrap_*` (20, retained), `std_checked_cast_*` (legacy), `zig_cast_checked_s/u`, `zig_wrap_*`, `zig_ovf_*`, `zig_overflow_flag_*`, `zig_poison_fill` | `@intCast`, `-fsafe` arithmetic, `undefined` | Pure integer helpers, no OS calls |
| file / dir / env / time | `zig_pal.c`: `pal_file_*`, `pal_dir_exists`, `pal_get_default_lib_path`, `pal_getenv`, `pal_wallclock_unix` | `std.io` file API, `std_os`, `std_time`, compiler CLI | POSIX `open`/`read`/`write`/`close`/`stat`/`getenv`; Win32 `CreateFileA`/`ReadFile`/`WriteFile`/`GetFileAttributesA`/… |
| memory / string | CRT libc, or `zig_runtime.c` under `ZIG_NO_CRT` | emitted code | `ZIG_NO_CRT` defines `strlen`/`memcpy`/`memset`/`strncmp` |
| process startup / exit | `zig_pal.c` `mainCRTStartup` (`ZIG_NO_CRT`), `c_exit.c`; otherwise the toolchain CRT | every program | no-CRT entry calls `main` and `exit` |
| headers | `zig_compat.h`, `zig_special_types.h`, module `.h`; conditional `net_prelude.h`/`std_os_prelude.h`/`std_time_prelude.h`/`std_page_prelude.h` | all programs | `<windows.h>`/`<unistd.h>` appear only where the PAL or a prelude needs them |
| console ANSI builtins | `<windows.h>` / `<stdio.h>` + `sprintf` | `@consoleGotoxy`, `@consoleSetColor` | Separate from the stdout family; the remaining C-stdio writer in emitted code |
| `zig_nocrt.c` shims | `fwrite`/`fflush`/`getchar`/`getc`/`fgetc`/`putchar`/`putc`/`fputc`/`_filbuf`/`_flsbuf`/`getenv`/`time` | external C callers only | Retained compatibility surface; no Z98 builtin depends on it after D8 |

The CRT dependency of the stdout family is therefore gone: on CRT builds the
calls compile to `write`/`read` (POSIX) or Win32 console/file calls, and on
no-CRT builds the same Win32 calls are made directly. Buffered C-stdio data can
no longer be lost or reordered relative to PAL output.

### Reduction path toward a C-free backend

The PAL is the intended seam between emitted code and the host. A backend that
emits machine code instead of C can replace each PAL entry point as follows:

- `pal_print_stdout` / `pal_print_stderr` / `pal_putchar` → a raw `write` syscall
  on POSIX, or `WriteFile`/`WriteConsoleA` on Win32; no buffering layer.
- `pal_getchar` → raw `read` syscall / `ReadFile`.
- `pal_file_open`/`read`/`write`/`close`/`seek64`/`size`/`mtime` → the native
  file syscalls or Win32 file calls the PAL already selects.
- `pal_dir_exists` / `pal_getenv` / `pal_get_default_lib_path` /
  `pal_wallclock_unix` → `stat`/`getenv`/`readlink`/`gettimeofday` syscalls, or
  the Win32 equivalents.
- `pal_abort` / `pal_trap` / `pal_set_trap_handler` → a direct trap instruction
  plus an optional in-process handler.
- The `__bootstrap_<DST>_from_<SRC>`, `std_checked_cast_*`,
  `zig_cast_checked_s/u`, `zig_wrap_*`, `zig_ovf_*`, `zig_overflow_flag_*` and
  `zig_poison_fill` helpers → inline sign/zero extension, width masks and
  overflow flags; the `-fsafe` variants become guarded branches/traps.
- The `ZIG_NO_CRT` `strlen`/`memcpy`/`memset`/`strncmp` shims → inline loops or
  string instructions.
- `mainCRTStartup` / `c_exit.c` → the target's native entry stub and exit path
  (ELF `_start` + `exit` syscall; PE entry + `ExitProcess`).
- The remaining `sprintf` use in the console ANSI builtins can move onto the
  same PAL formatting helpers, removing the last emitted `<stdio.h>` writer.

What remains after that reduction is only the OS-call seam (which any backend
must have) and the user-requested `@cInclude` surface; there is no required C
runtime call left for the stdout family.

### Verification

- `stdout_order_ok` prints `A\nB\nC\nDZ\n`, rc 0, with stdin `Z`, byte-exact
  under gcc CRT and `scripts/win32_cross/cross_nocrt.sh` + Wine, in both
  `-ffast` and `-fsafe`. The no-CRT PE imports only `KERNEL32.dll`.
- Emitted `main`/`std_io` for the fixture contain `pal_print_stdout`,
  `pal_putchar`, `pal_getchar` and no `fwrite`/`putchar`/`getchar`/`<stdio.h>`.
- `scripts/check_emit_support.sh` passes (9/9: 6 core + 3 conditional preludes
  in the current script enumeration); `scripts/compiler/gate_warn_clean.sh` is
  GREEN under `-m32 -std=c89 -pedantic -Wall -Werror -Wno-long-long`.
- Representative stdlib/example programs (hello, `tco_factorial`,
  `lisp_interpreter_curr`, the `stdlib_print_*`/`stdlib_debug_*`/`stdlib_os_*`
  fixtures) keep their pre-fix stdout byte-for-byte.
