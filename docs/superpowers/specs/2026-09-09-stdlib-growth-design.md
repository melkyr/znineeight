# Stdlib Growth — Design Spec

**Date:** 2026-09-09 · **Branch:** zig1_improvements · **Type:** stdlib (usability lever; runs after EMITCOMPACT in the forward queue)

## 1. Purpose

Grow zig1's standard library from its current 4-file / 389-line core into a usable base for 1998-era programs. The stdlib is the top usability lever: it is what lets a newcomer write a real program without hand-rolling string/io/mem/arena code per project. Every module is written **in Z98**, so the stdlib doubles as the exercise + permanent pin of the shipped feature set (uN/iN, packed struct/union, enum(uN), optionals, error unions) through the corpus/runtime gates.

## 2. Binding operator decisions

- **Win9x API set — no cstdio / no C-runtime dependence.** On Win9x the CRT/library may not exist on the host machine; the compiler cannot assume it. All input/output/alloc/file behavior MUST go through the existing PAL/Win32 primitives (`pal_print_stdout` → `WriteConsoleA`/`WriteFile` on Win32, `write(1,…)` on POSIX; file I/O via `pal_file_open/write/close` → `CreateFileA`/`WriteFile`). No `printf`, `fwrite`, `fopen`, `malloc`, `strlen`, etc. This is a hard, grep-audited constraint on every module.
- **Available Z98 builtins the stdlib may rely on** (compiler-recognized, no import needed): `@putChar`, `@stdoutWrite`, `@getChar`, `@sleepMs`, `@isWindows`, `@cInclude`, `@intCast`, `@ptrCast`, `@intToPtr`, `@sizeOf`, `@alignOf`, plus extern `"c"` declarations through the existing `extern_c`/`@cInclude` machinery (`extern_c_z98.zig`, `zig_runtime.h`, `pal.h`).
- **Module set (operator-approved A1/A2):** `std_str`, `std_mem`, `std_math`, `std_debug` as new modules; `std_io` expansion including **file I/O** (wrap the existing `pal_file_open/write/close` + `streamOpen/Write/Read/Seek/Close` surface — worth verifying which already work); `std_arena` rewritten to be a real per-arena allocator (not the current shared-global stub); `std.zig` re-exports every module, including the currently-missing `std_net`, **if it can be done** (A2 — net needs `@cInclude`; if re-exporting it unconditionally breaks non-net builds, re-export conditionally on `@isWindows`/platform availability — the plan's census verifies).
- **Stdlib files live at `sf/src/` (source of truth) and are installed to `<exe>/lib`** as part of every seed rebuild / reference install (existing 4-file mechanism extended).
- **Modules are user-program modules, not compiler modules.** Adding stdlib files does NOT change the compiler's self-emission or fixed point (they are not in the `sf/src/main.zig` import graph). They are compiled when a *program* imports `std`, so the **corpus is the accuracy oracle** for stdlib work: each module is pinned by ≥1 new corpus fixture with byte-exact GREEN stdout.
- **Corpus/Gates (same as every plan):** current corpus state = 419 dirs (365 mi_matrix + 54 repro top-level) = 404 OK / 9 GREEN / 6 FAIL. Each stdlib increment: corpus zero-asymmetric except the new fixture dirs (absent → OK/GREEN). Golden 9/9 + matrix 21/21 run byte-identity. 4-MD5 dump gates are UNCHANGED by stdlib work unless a gate *program* imports a changed std module — recorded-not-rebaselined if so, operator-ruled re-baseline only at closeout.
- **Closeout + seed rotation** at Task N: N-hop + behavioral identity + docs GATE + `archive_seed.sh` rotation (seed unchanged unless the compiler source moved — stdlib-only plans rotate only if the fixed point moved).
- **Flag-set rule binding:** every gcc `-c` = `gcc -m32 -std=c89 -O0 -Wall -Wno-long-long -Wno-pointer-sign -Wno-implicit-function-declaration -I <inc>`; separate `-Wall -Wextra -O3 -fsyntax-only` verification gate, never the build command.
- **Working conventions:** SDD skill mandatory; compression forbidden during build sessions; memories via `mnemoria --path .opencode/memory` under agent `<plan>-session`; edits via `edit`/`fastedit` only; no commit until review clean.

## 3. Module specifications (v1)

### 3.1 `std_str.zig` — byte-string helpers (pure, no externs)
- `pub fn len(s: []const u8) usize` (alias of `.len`; convenience).
- `pub fn eql(a: []const u8, b: []const u8) bool`
- `pub fn copy(dst: []u8, src: []const u8) void` (bounds-safe copy of `src.len ≤ dst.len`).
- `pub fn copyZ(dst: [*]u8, src: []const u8) usize` (copies + NUL-terminates; returns length) — for C-boundary strings.
- `pub fn findChar(s: []const u8, c: u8) ?usize`
- `pub fn startsWith(s: []const u8, prefix: []const u8) bool`
- `pub fn endsWith(s: []const u8, suffix: []const u8) bool`
- `pub fn toUpper(s: []u8) void`, `pub fn toLower(s: []u8) void` (ASCII in place).
- Implementation is pure index/compare loops over slices — exercises `[]const u8`, `for`, optional return (`?usize`), `orelse`.

### 3.2 `std_mem.zig` — raw memory helpers (pure pointer math)
- `pub fn copy(comptime T: type, dst: [*]T, src: [*]const T, n: usize) void` — NOTE: no comptime/generics in Z98; provide **concrete** variants instead: `copyU8(dst: [*]u8, src: [*]const u8, n: usize)`, `copyU32(...)`, `copyU64(...)`.
- `pub fn zeroU8(dst: [*]u8, n: usize) void`
- `pub fn eqlU8(a: [*]const u8, b: [*]const u8, n: usize) bool`
- Pure pointer/index loops; no externs.

### 3.3 `std_math.zig` — scalar helpers (pure)
- `pub fn min(a: i32, b: i32) i32`, `pub fn max(a: i32, b: i32) i32` (+ `minU`/`maxU` for `u32`).
- `pub fn abs(n: i32) i32`
- `pub fn clamp(v: i32, lo: i32, hi: i32) i32` (+ `clampU`).
- `pub fn isPowerOfTwoU32(n: u32) bool`
- `pub fn alignUp(n: u32, align: u32) u32`, `pub fn alignDown(n: u32, align: u32) u32`

### 3.4 `std_debug.zig` — logging + assertions (routes through `@`-builtins only)
- `pub fn log(msg: []const u8) void` → `@stdoutWrite`.
- `pub fn logInt(tag: []const u8, n: i32) void`
- `pub fn assert(cond: bool) void` → panic via `@panic`/`unreachable` path or printed abort (plan pins the exact divergence mechanism available in Z98).
- `pub fn panic(msg: []const u8) noreturn`
- All output via `@stdoutWrite`/`@putChar` — never cstdio.

### 3.5 `std_io.zig` expansion — add file I/O (verify + wrap existing PAL)
- Keep current `writeByte`/`write`/`writeStr`/`print`/`printInt`/`readByte`/`sleepMs`.
- Add **file wrappers** over the existing `pal_file_*`/`stream_*` surface (verify which are live at HEAD first — `pal.zig:88-153` declares `fileOpen/fileWrite/fileClose` + `streamOpen/streamClose/streamWrite/streamRead/streamSeek` backed by `CreateFileA`/`WriteFile` on Win32):
  - `pub const File = struct { handle: usize, ... }` or function-based handle API.
  - `pub fn fileOpen(path: []const u8, write: bool) ?File`
  - `pub fn fileWrite(f: File, data: []const u8) void`
  - `pub fn fileRead(f: File, buf: []u8) usize` (returns bytes read; wraps `streamRead`)
  - `pub fn fileClose(f: File) void`
  - Exact signatures TBD by the census against the real PAL; the file surface must compile clean and run a read-write-back file round trip GREEN on POSIX (the win9x path is compile-gated by the same `CreateFileA` machinery already in `zig_pal.c`).

### 3.6 `std_arena.zig` rewrite — real per-arena allocator
- Current `std_arena.zig` is a stub: `Arena.create` ignores its argument and all instances share one `g_storage[1048576]`/`g_used` global. Rewrite so each `Arena` is self-contained over caller-provided backing storage:
  - `pub fn init(data: []u8) Arena` — wraps a caller slice.
  - `pub fn alloc(self: *Arena, size: usize) ?[*]u8` — bump within `self.data`, returns `null` on exhaustion.
  - `pub fn reset(self: *Arena) void` — `self.used = 0`.
  - Remove the shared `g_storage`/`g_used` globals.
- This is a **behavioral change** to an existing module — the plan must check every current `std.arena` consumer (compiler examples, fixtures that `@import("std")` and use `arena`) and migrate them to the new `init(data)` form, with the affected fixtures re-baselined under runtime byte-identity.

### 3.7 `std.zig` — re-export all modules
- Current: `pub const io = @import("std_io.zig"); pub const arena = @import("std_arena.zig");`
- Extend to: `io`, `arena`, `str`, `mem`, `math`, `debug`, and `net` **if it can be done** (A2). Census verifies whether unconditional `pub const net = @import("std_net.zig")` breaks builds that never use net (std_net carries `@cInclude("<net_prelude.h>")` + wsock32 externs); if it does, gate the re-export on `@isWindows`/platform or leave net importable directly (`@import("std_net.zig")`) with a documented note.

## 4. Fixture / corpus pinning

- Each new/changed module ships ≥1 corpus fixture `repro/mi_matrix/stdlib_*_xmod/main.zig` (convention: header comment with GREEN contract, `const std = @import("std");`, `pub fn main() void`, `std.io.printInt`/`std.io.writeByte` output, deterministic byte-exact stdout). The fixture must exercise the module AND at least one shipped compiler feature (uN/iN width, packed field, enum(uN), optional/error-union) so the stdlib genuinely pins feature+stdlib together.
- A file-I/O fixture must write a temp file, read it back, and assert byte-exact content (POSIX run; the win9x path is the same PAL code).
- Arena fixture exercises two independent `Arena`s over distinct buffers (proves the shared-global stub is gone).

## 5. Out of scope (later plans / queue)

- String formatting beyond the existing `std.io` builtin decompose; parsing libraries; containers (ArrayList/hash-map std forms — the compiler keeps its internal concrete maps); anything requiring new compiler features.
- New compiler features (see the separate C89-ahead plan).
- EMITCOMPACT executes before this plan in the forward queue.

## 6. Task list (implementation plan structure)

- Task 1 (I, record-only): baseline + PAL file-surface census + `std.zig` re-export (A2) census + `std_arena` consumer audit + RED probes.
- Task 2 (F): `std_str` + `std_mem` + `std_math` pure modules + fixtures.
- Task 3 (F): `std_debug` + `std_io` file I/O over the verified PAL surface + fixtures.
- Task 4 (F): `std_arena` per-arena rewrite + consumer migration + fixture.
- Task 5 (F): `std.zig` full re-export close incl. `net` per the A2 verdict.
- Task 6 (I then F): full battery + docs GATE + seed rotation (if fixed point moved).
