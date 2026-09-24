# 10 — C Runtime Layer [updated: 2026-09-24 — Task 1 (z98-print-formatting): the `std_print_i32/u32/i64/u64/f64/bool/char/str/hex_*` formatting bodies were retired from `zig_runtime.c` (canonical) and `emit_support.zig` (emitted copy) and now live in the Z98 std module `sf/src/std_fmt.zig` (`std.fmt`), called through the same PAL primitives (`pal_print_stdout` + `pal_i64/u64/f64_to_str`). `std_print`/`std_print_len` remain the raw-bytes runtime helpers.] [updated: 2026-09-20 — refreshed against current source: `pal_trap`/trap handler, `pal_file_read`/`pal_dir_exists`/`pal_get_default_lib_path`, 15 print helpers incl. hex, 20 `__bootstrap_*` helpers, the `-fsafe` overflow/checked-cast/poison helpers, the three target-neutral preludes, `c_exit.c`, and the dead `extern_c_z98.zig`; emitted-support relationship now via `emit_support.zig`; line references and dated evidence removed]

> Covers: `sf/src/include/*`, `c_exit.c`, `extern_c.zig`, `extern_c_z98.zig`

## Summary Table

| Artifact | Count | Notes |
|----------|-------|-------|
| Header files | 8 | `zig_compat.h`, `zig_runtime.h`, `zig_special_types.h`, `net_prelude.h`, `std_os_prelude.h`, `std_time_prelude.h`, `net_runtime.h` (legacy), `optstar_repro.h` (repro stub) |
| C source files | 3 | `zig_runtime.c`, `zig_pal.c`, `net_runtime.c` (legacy, unlinked) |
| PAL functions | 15 | `pal_print_stderr`/`stdout`, `pal_set_trap_handler`, `pal_abort`, `pal_trap`, `pal_i64/u64/f64_to_str`, `pal_file_open`/`read`/`write`/`close`, `pal_dir_exists`, `pal_get_default_lib_path`, `mainCRTStartup` (Win32 `ZIG_NO_CRT`), plus 4 file-static helpers |
| Runtime print helpers | 3 | `std_panic`, `std_print`, `std_print_len` — the typed `std_print_i32/u32/i64/u64/f64/bool/char/str/hex_*` formatting bodies moved to `sf/src/std_fmt.zig` (`std.fmt`) in Task 1, 2026-09-24 |
| Checked cast functions | 8 | `std_checked_cast_i8..u64` — **legacy, NOT emitted by zig1** (upper-bound-only) |
| `__bootstrap_<DST>_from_<SRC>` helpers | 20 | Retained `@intCast` range-check support: `static` defs in `zig_runtime.h` + `extern` defs in `zig_runtime.c`; panic `"integer cast overflow in @intCast"` on out-of-range. The emitter no longer selects them (see `08_c89_emission.md`) |
| `-fsafe` helpers | 28 | 25 wrap/overflow-flag helpers + 2 width/sign-aware `zig_cast_checked_s/u` + `zig_poison_fill`; header-static, emitted only under `-fsafe` |
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

### `zig_runtime.h` — Header Declarations

`zig_runtime.h` includes `zig_compat.h` and declares the PAL, arena, print, and cast surface, plus the header-static `-fsafe` and `__bootstrap_*` helpers.

| Decl | Visibility | Purpose | Notes |
|------|-----------|---------|-------|
| `pal_print_stderr` | extern | Raw stderr write | Takes `(const char*, unsigned int len)` |
| `pal_abort` | extern | Abort process | |
| `pal_trap` | extern | Trap (`int3`) with an optional Z98-installed handler | Called by `std_panic` and the `-fsafe` guard failures |
| `pal_i64_to_str` / `pal_u64_to_str` / `pal_f64_to_str` | extern | Int64/Uint64/Float64 to decimal string | Return length |
| `zig_poison_fill` | extern | `-fsafe` `undefined` poison (`0xAA` fill) | Present in the canonical sources; emitted only under `-fsafe` |
| `zig_ovf_*`, `zig_wrap_*`, `zig_overflow_flag_*` | static | `-fsafe` UB-free wrap and overflow-flag math | Header-static so every emitted TU is self-sufficient; emitted only under `-fsafe` |
| `arena_alloc_default` | decl | Default-arena entry point | Defined in the legacy `src/runtime/zig_runtime.c`, not in `sf/src/include` |
| `zig_default_arena` | extern | Global arena pointer | |
| `std_panic` | decl | Print panic + trap | Used by zig1 emission |
| `std_print` / `std_print_len` | decl | Stdout string helpers (raw bytes; format-string literal segments + console) | |
| `std_print_i32`..`std_print_hex_i64` | decl | **Bodies moved (Task 1, 2026-09-24)** — the declarations are retained in `zig_runtime.h` for compatibility, but the definitions were retired from `zig_runtime.c`/`emit_support.zig`; the formatting bodies now live in `sf/src/std_fmt.zig` (`std.fmt`); see `08_c89_emission.md` | |
| `std_checked_cast_*` | decl | Legacy upper-bound-only numeric casts | Panic `"int cast overflow for <T>"`; NOT emitted by zig1 |
| `c_char` + `__bootstrap_<DST>_from_<SRC>` (20) | typedef + static | Retained `@intCast` range-check helpers | `static` here + `extern` in `zig_runtime.c`; the emitter now uses `zig_cast_checked_s/u` instead |
| `zig_cast_checked_s` / `zig_cast_checked_u` | static | `-fsafe` width/sign-aware checked `@intCast` | Header-static; emitted only under `-fsafe` |

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
| `pal_print_stderr` | extern | Write `len` bytes to stderr (fd 2) | `std_panic`, diagnostics | `write` / `WriteConsoleA`+`WriteFile` | Win32 tries Console then File |
| `pal_print_stdout` | extern | Write `len` bytes to stdout (fd 1) | `std_print`, `std_print_len`, `std.fmt` printers (`std_fmt.zig`) | `write` / `WriteConsoleA`+`WriteFile` | Same dual-path as stderr; **unbuffered on POSIX** (`write(1)`) — the `std.fmt` printers use it (not the buffered `@stdoutWrite`) so print output ordering is unchanged |
| `pal_set_trap_handler` | extern | Install a Z98 trap handler | `std_debug.zig` | none | `TrapContext` layout must match `std_debug.zig` (10 × `unsigned int`) |
| `pal_abort` | extern | Abort process | `pal_trap` fallback | `abort()` / `TerminateProcess` | Win32 uses exit code 3 |
| `pal_trap` | extern | Invoke handler, then `int3` | `std_panic`, `-fsafe` guards | `g_trap_handler`, inline asm, `pal_abort` | Register capture GCC/x86-only; `int3` on x86, `pal_abort` elsewhere |
| `pal_i64_to_str` | extern | Signed 64-bit to decimal string | `std.fmt.printI32`/`printI64` (`std_fmt.zig`); historically `std_print_i32`/`std_print_i64` | `pal_u64_to_str_buf` | Two's-complement-safe negate: `-(value+1)+1` |
| `pal_u64_to_str` | extern | Unsigned 64-bit to decimal string | `std.fmt.printU32`/`printU64`; historically `std_print_u32`/`std_print_u64` | `pal_u64_to_str_buf` | Thin wrapper |
| `pal_f64_to_str` | extern | Double to decimal string (up to 6 fractional digits) | `std.fmt.printF64`; historically `std_print_f64` | `pal_i64_to_str` | Strips trailing zeros; integer part via i64, fraction via loop ×10 |
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

The compiler does not link the `sf/src/include/*` files at emission time; `emit_support.zig` holds their canonical bytes as Z98 string constants and writes them into the output directory, so the emitted tree is self-contained. `scripts/check_emit_support.sh` asserts emitted == canonical byte-for-byte. The emitted set is `zig_compat.h`, `zig_runtime.h`, `zig_runtime.c`, `zig_pal.c`, `c_exit.c` (always) plus the conditionally-emitted `net_prelude.h`/`std_os_prelude.h`/`std_time_prelude.h`. `zig_special_types.h` and the per-module `.c`/`.h` are emitted by the C89 emitter. The old `emitZigPalC`/`emitZigCompatH`/`emitZigRuntimeC` functions in `c89_emit.zig` are dead stale mirrors. See `08_c89_emission.md` §6 for the full function table and companion build scripts.

---

## Data Flow

```
zig1 emitted C89 code
  │
  ├─ std.debug.print(...) → std_print*(...) → pal_print_stdout → write(1,...)
  ├─ std.io.print(fmt, .{...}) → mangled std.fmt.<printer>(...) (std_fmt.zig) → pal_print_stdout → write(1,...)
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

- **`__bootstrap_print` / `__bootstrap_print_int` are declared with no live definition.** `extern_c.zig` declares them and the `zig_runtime.h`/`zig_runtime.c` backward-compat aliases were removed (F4, 2026-08-08), but the live runtime defines neither (only the dead `emitZigRuntimeC` mirror in `c89_emit.zig` does). `pal.zig` uses only `ext_c.write`, so no live release caller links against them; they are retained legacy import surface.
- **`pal_print_stdout` is not declared in `zig_runtime.h`.** It is forward-declared inside `zig_runtime.c` and defined in `zig_pal.c`; an emitted TU that calls it must supply its own declaration. `std_fmt.zig` declares it `extern "c"` (the emitter skips prototypes for extern fns; the emitted `std_fmt` TU calls it with a C89 implicit declaration, as `std_io` already does for `pal_file_*`).
- **`net_runtime.c` / `net_runtime.h` are dead.** None of the 12 socket helpers declared in `net_runtime.h` are referenced by `sf/src`; 6 carry the `plat_socket_*` prefix (`plat_socket_init`/`cleanup`/`select`/`fd_zero`/`fd_set`/`fd_isset`), the other 6 are the remaining socket helpers (`plat_create_tcp_server`, `plat_bind_listen`, `plat_accept`, `plat_recv`, `plat_send`, `plat_close_socket`). `std_net` is now the extern surface via `net_prelude.h`. The file remains only for legacy/pre-F6 example builds.
- **`optstar_repro.h` is a repro stub** referencing `extFn` and `fopen` with mangled types; it is included by no live TU.
- **`extern_c_z98.zig` is dead.** It is not imported by the 40-module build, and its `@cInclude("pal.h")` names a header that is not present in the tree.
- **`usize` is 32-bit even on 64-bit hosts**, so a 64-bit Windows `HANDLE` cannot round-trip through `PlatFile`/`usize`; the supported target is 32-bit Windows 9x/NT.
