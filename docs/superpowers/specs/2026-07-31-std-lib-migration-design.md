# Bootstrap → Z98 Std Lib Migration — Design Specification

**Version:** 1.1
**Date:** 2026-07-31 (AMENDED 2026-08-08)
**Status:** Approved. Amended to incorporate current repo state + the two std-lib-deferred gaps from the multi-module fixes plan.

## 1. Goal

Migrate all 21 Z98 examples (and eventually zig1 itself) away from `extern fn __bootstrap_*` declarations to a proper Z98 standard library (`std.zig`, `std_io.zig`, `std_net.zig`, `std_os.zig`, `std_arena.zig`). The PAL C layer (`zig_pal.c`) stays in C for Win9x/POSIX portability. Pure Z98 wherever possible; extern C only at the PAL boundary. **Additionally solve the two deferred gaps: `arena_alloc_default` (json_parser + json_parser_workaround) and the 5 `plat_console_*`/`plat_is_windows` stubs (rogue_mud).**

## 2. Architecture

```
Z98 layer (compiled by zig1, emitted as C89):
  sf/src/std.zig          — root package: pub const io = @import("std_io.zig");
  sf/src/std_io.zig       — print (format + itoa), write, read_line
  sf/src/std_net.zig      — socket create/connect/send/recv/select wrappers
  sf/src/std_os.zig       — sleep_ms, exit, getenv
  sf/src/std_arena.zig    — bump allocator: create/alloc/reset/free (solves json_parser, AMENDMENT 2026-08-08)

PAL C layer (linked, unchanged):
  sf/src/include/zig_pal.c    — pal_print_stderr, pal_write, pal_memcpy,
                                 pal_u64_to_str_buf, pal_i64_to_str,
                                 Win32 (_WIN32) vs POSIX (#else) #ifdef
                                 + plat_is_windows, plat_console_* (AMENDMENT 2026-08-08 — solves rogue_mud)
  sf/src/include/zig_pal.h    — extern prototypes
```

## 2b. AMENDMENT 2026-08-08 — deferred gaps now in scope

The multi-module fixes plan (a83c6e27..4f58aa56) deferred two runtime-library gaps to the std-lib plan. This spec now includes them:

| Gap | Source | Affected | Current status | std-lib solution |
|---|---|---|---|---|
| `arena_alloc_default` extern | json.zig:253, file.zig:25; declared zig_runtime.h:21-22; defined ONLY in legacy `src/runtime/zig_runtime.c:154-156` | json_parser, json_parser_workaround | OK-by-gate/latent (link fails on 5 undefined refs) | `std_arena.zig` (pure Z98 bump allocator, Option A preferred) |
| `plat_is_windows`, `plat_console_gotoxy/setcolor/putchar/clear` | rogue_mud ui.zig:11-14 | rogue_mud | OK-by-gate/latent (link fails on 5 undefined refs) | PAL C functions in `zig_pal.c` (POSIX ANSI-escape implementations + Win32 stubs) + `std_pal.zig` externs |

Current corpus (2026-08-08): manifest 230 repros OK=223/FAIL=3/gg=4; sweep 237 dirs OK=229/FAIL=8/ICE=0/CRASH=0. 4 MD5 gates: mud `6c0a83f1…`, gol `0d8f0092…`, lisp `a12f2fce…` (post-F1), json `c403f079…`. 21 examples.

## 3. std io design

```zig
// sf/src/std_io.zig
const pal = @import("std_pal.zig");

pub const Writer = struct {
    write_fn: fn ([]const u8) void,
};
pub var out: Writer = undefined;  // init in std.init()
pub var err: Writer = undefined;

pub fn print(self: *Writer, comptime fmt: []const u8, args: ...) void {
    // format string → Z98 itoa/util → call write_fn
}

pub fn write(self: *Writer, data: []const u8) void {
    self.write_fn(data);
}

// PAL bridge — single extern C boundary
// sf/src/std_pal.zig
extern "c" fn pal_print_stdout(buf: [*]const u8, len: usize) void;
extern "c" fn pal_print_stderr(buf: [*]const u8, len: usize) void;

pub fn stdoutWrite(data: []const u8) void {
    pal_print_stdout(data.ptr, data.len);
}
pub fn stderrWrite(data: []const u8) void {
    pal_print_stderr(data.ptr, data.len);
}
```

## 4. Compiler's own I/O (first migration step)

Currently `pal.zig` in zig1's own source calls raw `write()` via `extern_c.zig`. After std.zig exists, zig1 switches to:
```zig
const std = @import("std");
std.io.err.write("error[2000]: expected ';'\n");
```
The compiler writes to stderr via `std.io.err.write()` → `std_pal.pal_print_stderr()` → `zig_pal.c`. The PAL layer stays in C; only the Z98 side changes.

## 5. Migration order

1. **Create Z98 std lib** — `sf/src/std.zig`, `sf/src/std_io.zig`, `sf/src/std_pal.zig` (extern C wrappers to existing zig_pal.c functions)
2. **Verify zig1 compiles + runs** using new std (requires std.zig to be importable during zig0 bootstrap — zig0 compiles zig1 → emits C89 → gcc links zig_pal.c)
3. **Migrate compiler's own I/O** — `pal.zig` → `std.io`
4. **Migrate examples** — one category at a time:
   - Single-file examples (hello, fibonacci, prime, mandelbrot) — replace `extern fn __bootstrap_print` with `const std = @import("std")`
   - Multi-module examples (game_of_life, lzw, json_parser, json_parser_workaround) — std imports used across modules
   - Networking examples (mud_server, rogue_mud) — `std.net` wrappers + plat console
   - Lisp interpreters (curr, adv, interpreter) — heavy print usage
5. **Remove `__bootstrap_*` wrappers** from `sf/src/include/zig_runtime.c:67-72` — they're now dead code (keep the cast-helper family if the compiler still needs it)
6. **Update all 21 NOTES.md** with new recipes

## 6. Bootstrap → Z98 function mapping

| `__bootstrap_*` | Z98 std equivalent | PAL backing |
|---|---|---|
| `__bootstrap_print(s)` | `std.io.print("{}", ...)` or `std.io.out.write(s)` | `pal_print_stdout` |
| `__bootstrap_print_int(n)` | `std.io.print("{}", .{n})` via itoa | `pal_print_stdout` |
| `__bootstrap_write(s, len)` | `std.io.out.write(s[0..len])` | `pal_print_stdout` |
| `__bootstrap_sleep_ms(ms)` | `std.os.sleep(ms)` | `pal_sleep_ms` (new PAL fn) |
| `__bootstrap_getchar()` | `std.io.in.readByte()` | `pal_read_stdin` (new PAL fn) |
| `__bootstrap_panic(msg)` | `@panic(msg)` (compiler builtin) | `pal_print_stderr` + `exit(1)` |

## 7. I-task scope

Research-only (no prototype code). Study:
1. Inventory all `__bootstrap_*` / `extern fn` call sites across all 18 Z98 examples (per-file, per-function)
2. Inventory all PAL C functions (`zig_pal.c`) and their Win32/POSIX `#ifdef` branches — what must be exposed to Z98
3. Design Z98 std function signatures — pure Z98 bodies for format/itoa/mem, extern C at PAL boundary only
4. Verify zig1 bootstrap compatibility — can zig0 compile zig1 + std.zig as a multi-module compilation? What must change in `main.zig` imports?
5. Map migration order — which examples migrate first, what changes per example (exact file:line)
6. Note: this is NOT a C runtime rewrite — PAL stays in C. Z98 code calls PAL via `extern "c"` in `std_pal.zig` only.

Produce report with exact edit targets (file:line), Option A/B/C comparison, blast-radius analysis. Then F-task executes the implementation.

## 8. Success criteria

- `sf/src/std.zig`, `sf/src/std_io.zig`, `sf/src/std_arena.zig` exist with Z98 bodies for print/write/format + bump allocator
- All 21 examples compile + link + run using `@import("std")` instead of `extern fn __bootstrap_*`
- **json_parser + json_parser_workaround link + run** via `std.arena` (no legacy runtime file)
- **rogue_mud links + runs** via the plat console PAL additions
- zig1 compiles + runs using `std.io` for its own diagnostic output
- `__bootstrap_*` I/O wrappers removed from `sf/src/include/zig_runtime.c`
- All NOTES.md updated
- Corpus (2026-08-08): 230 manifest repros, OK=223/FAIL=3/gg=4 (FAIL must not increase); 4 MD5 gates byte-identical (json re-baseline only if emitted C changes, with runtime proof)
