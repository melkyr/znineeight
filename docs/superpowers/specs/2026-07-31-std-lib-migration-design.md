# Bootstrap → Z98 Std Lib Migration — Design Specification

**Version:** 1.0
**Date:** 2026-07-31
**Status:** Approved

## 1. Goal

Migrate all 18 Z98 examples (and eventually zig1 itself) away from `extern fn __bootstrap_*` declarations to a proper Z98 standard library (`std.zig`, `std_io.zig`, `std_net.zig`). The PAL C layer (`zig_pal.c`) stays in C for Win9x/POSIX portability. Pure Z98 wherever possible; extern C only at the PAL boundary.

## 2. Architecture

```
Z98 layer (compiled by zig1, emitted as C89):
  sf/src/std.zig          — root package: pub const io = @import("std_io.zig");
  sf/src/std_io.zig       — print (format + itoa), write, read_line
  sf/src/std_net.zig      — socket create/connect/send/recv/select wrappers
  sf/src/std_os.zig       — sleep_ms, exit, getenv

PAL C layer (linked, unchanged):
  sf/src/include/zig_pal.c    — pal_print_stderr, pal_write, pal_memcpy,
                                 pal_u64_to_str_buf, pal_i64_to_str,
                                 Win32 (_WIN32) vs POSIX (#else) #ifdef
  sf/src/include/zig_pal.h    — extern prototypes
```

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
   - Multi-module examples (game_of_life, lzw, json_parser) — std imports used across modules
   - Networking examples (mud_server) — `std.net` wrappers
   - Lisp interpreters (curr) — heavy print usage
5. **Remove `__bootstrap_*` wrappers** from `sf/src/include/zig_runtime.c:67-72` — they're now dead code
6. **Update all 18 NOTES.md** with new recipes

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

- `sf/src/std.zig`, `sf/src/std_io.zig` exist with Z98 bodies for print/write/format
- All 18 examples compile + link + run using `@import("std")` instead of `extern fn __bootstrap_*`
- zig1 compiles + runs using `std.io` for its own diagnostic output
- `__bootstrap_*` wrappers removed from `sf/src/include/zig_runtime.c`
- All NOTES.md updated
- Corpus: 184 repros, OK=176 FAIL=8 ICE=0 CRASH=0
