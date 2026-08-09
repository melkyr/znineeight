# Bootstrap → Z98 Std Lib Migration + Compiler Builtins — Design Specification

**Version:** 2.0
**Date:** 2026-07-31 (AMENDED 2026-08-08 — builtin architecture, Phase 1/2, bootstrap constraint)
**Status:** Approved. Ready for plan.

## 1. Goal

Implement 20 compiler builtins for platform I/O, console, and networking; create a pure-Z98 standard library (`std.zig`, `std_io.zig`, `std_arena.zig`) built on those builtins; migrate all 21 Z98 examples away from `extern fn __bootstrap_*` declarations; solve the two deferred gaps (arena_alloc_default, plat_ console stubs). **Zero `extern "c"` in the std lib** — the compiler owns all platform abstraction via `#ifdef`-guarded C89 emission. Design for future backend independence (LLVM IR, WASM, direct x86, 16-bit targets) with one LIR instruction per builtin.

## 2. Architecture

```
Z98 std lib (pure Z98, compiled by zig1 — zero extern "c"):
  sf/src/std.zig         — root package: pub const io = @import("std_io.zig");
  sf/src/std_io.zig      — print (format + itoa), write, readByte, writeByte
  sf/src/std_arena.zig   — bump allocator: create/alloc/reset/free

Builtins (zig1 compiler intrinsics — sema + lowerer + C89 emitter):
  sf/src/semantic_analyzer.zig  — intrinsic name → type resolution
  sf/src/lower.zig              — one LIR instruction per builtin
  sf/src/c89_emit.zig           — #ifdef-guarded C emission per target

PAL C layer (UNCHANGED for now — Phase 2 evolution):
  sf/src/include/zig_pal.c      — kept for zig0 bootstrap + reference
  sf/src/include/net_runtime.c  — 12 plat_socket_* (reference for builtin emission)
  sf/src/include/zig_runtime.c  — cast helpers stay; __bootstrap_* I/O removed after migration
```

## 2b. Bootstrap Constraint (CRITICAL)

```
zig0 (C++ bootstrap, understands z98 dialect only)
  └─ compiles zig1 source (sf/src/*.zig) — MUST stay in zig0-compatible dialect
  └─ does NOT support the new builtins → zig1's own diagnostics stay pal.zig/extern_c.zig

zig1 (self-hosted, knows the new builtins)
  └─ compiles 21 examples + repros — they use std lib + builtins
  └─ compiles its OWN source → zig1.5 (future, gated on self-compile working)

zig1.5 → zig2 (uses std lib in own source, zig0 retired) — FUTURE PLAN, NOT THIS ONE
```

**This plan does NOT change zig1's own source.** zig1's code stays compiled by zig0 with the existing patterns. The std lib + builtins are for Z98 programs compiled BY zig1. The self-hosted evolution (zig1.5, zig2) is a separate future plan gated on zig1 self-compile (arena F5 scratch-arena OOM is the current blocker).

## 2c. Deferred gaps now in scope (from multi-module fixes plan)

| Gap | Source | Affected | Current status | Solution |
|---|---|---|---|---|
| `arena_alloc_default` extern | json.zig:253, file.zig:25; declared zig_runtime.h:21-22; defined ONLY in legacy `src/runtime/zig_runtime.c:154-156` | json_parser, json_parser_workaround | OK-by-gate/latent (link fails 5 undefined refs) | `std_arena.zig` — pure Z98 bump allocator (0 builtins) |
| `plat_is_windows`, `plat_console_gotoxy/setcolor/putchar/clear` | rogue_mud ui.zig:11-14 | rogue_mud | OK-by-gate/latent (link fails 5 undefined refs) | Console builtins (`@isWindows`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`, `@putChar`) |

## 3. Builtin Catalog

### Phase 1 — I/O + console (9 builtins)

| Builtin | Signature | C89 emission (POSIX) | C89 emission (Win32) | C89 emission (OpenWatcom) |
|---|---|---|---|---|
| `@putChar` | `(c: u8) void` | `putchar(c);` | `putchar(c);` | `putchar(c);` |
| `@stderrWrite` | `(buf: [*]const u8, len: usize) void` | `fwrite(buf, 1, len, stderr);` | same | same |
| `@getChar` | `() u8` | `getchar();` (EOF→255) | same | same |
| `@exit` | `(code: u8) noreturn` | `exit(code);` | same | same |
| `@sleepMs` | `(ms: u32) void` | `usleep(ms*1000);` | `Sleep(ms);` | `delay((int)ms);` |
| `@isWindows` | `() bool` | comptime `0` | comptime `1` | comptime `0` |
| `@consoleClear` | `() void` | `printf("\\x1b[2J");` | `system("cls");` | `printf("\\x1b[2J");` |
| `@consoleGotoxy` | `(x: i32, y: i32) void` | `printf("\\x1b[%d;%dH", y, x);` | `SetConsoleCursorPosition` | `printf("\\x1b[%d;%dH", y, x);` |
| `@consoleSetColor` | `(fg: i32, bg: i32) void` | `printf("\\x1b[%d;%dm", fg, bg);` | `SetConsoleTextAttribute` | `printf("\\x1b[%d;%dm", fg, bg);` |

`@isWindows` is comptime-folded: the C89 emitter never sees it. `if (@isWindows()) {...} else {...}` resolves to only the active branch at sema.

### Phase 2 — Networking (11 builtins)

| Builtin | Signature | C89 emission |
|---|---|---|
| `@socketCreate` | `() i32` | `socket(AF_INET, SOCK_STREAM, 0)` |
| `@socketBindListen` | `(port: u16) i32` | `bind` + `listen` (server helper) |
| `@socketAccept` | `(fd: i32) i32` | `accept(fd, ...)` |
| `@socketConnect` | `(fd: i32, addr: u32, port: u16) i32` | `connect(...)` |
| `@socketSend` | `(fd: i32, buf: [*]const u8, len: usize) i32` | `send(...)` |
| `@socketRecv` | `(fd: i32, buf: [*]u8, len: usize) i32` | `recv(...)` |
| `@socketSelect` | `(fd: i32, timeout_ms: u32) bool` | `select(...)` |
| `@socketFdZero` | `(fd_set*) void` | `FD_ZERO` |
| `@socketFdSet` | `(fd_set*, fd) void` | `FD_SET` |
| `@socketFdIsset` | `(fd_set*, fd) bool` | `FD_ISSET` |
| `@socketClose` | `(fd: i32) void` | `closesocket`/`close` |

Emission patterns are `#ifdef`-guarded per target, matching the `net_runtime.c` implementations (I-NET + I-PAL provide the exact per-platform bodies).

## 4. Data Flow (Z98 → C89)

```
Z98 source:  std.io.out.writeByte('A')  →  @putChar(@intCast(u8, 'A'))

Sema:        sees @putChar identifier → intrinsic table → TYPE_VOID, args=(u8)
Lowerer:     lowers @putChar(arg) → .builtin_put_char{ .char = tid }
C89 Emitter: .builtin_put_char → resolveTempName(tid) → emit "putchar(zT_3);\n"
```

Per-platform ops (e.g. `@sleepMs`) emit `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else / #endif` blocks. `@isWindows` is comptime-folded and never reaches the emitter.

## 5. File Structure

| File | Responsibility | Change |
|---|---|---|
| `sf/src/std.zig` | std lib root package | Create (F4) |
| `sf/src/std_io.zig` | print/write/readByte + format/itoa | Create (F4) |
| `sf/src/std_arena.zig` | bump allocator (pure Z98, 0 builtins) | Create (F3) |
| `sf/src/semantic_analyzer.zig` | intrinsic table + comptime `@isWindows` | Modify (F1, F2, F6) |
| `sf/src/lower.zig` | one LIR inst per builtin | Modify (F1, F2, F6) |
| `sf/src/c89_emit.zig` | `#ifdef`-guarded C emission | Modify (F1, F2, F6) |
| `sf/src/include/zig_runtime.c` | remove dead `__bootstrap_*` I/O | Modify (F4) |
| 21 example `.zig` files | `__bootstrap_*` → `@import("std")` | Modify (F4, F5) |
| 3 tech docs | `00_shared_infra.md`, `05_semantic_analysis.md`, `07_lir_lowering.md`, `08_c89_emission.md` | Modify (I-tasks, F-tasks) |

## 6. Tasks

**Phase 0 — Investigation (3 batched I-tasks, combined STOP):**
- I-RT: `zig_runtime.c` inventory + questionnaire (`.superpowers/sdd/I-RT-bootstrap-report.md`, updates `07_lir_lowering.md`)
- I-NET: `net_runtime.c` inventory + questionnaire (`.superpowers/sdd/I-net-report.md`, updates `08_c89_emission.md`)
- I-PAL: zig0 C++ PAL study + questionnaire (`.superpowers/sdd/I-pal-report.md`, updates `00_shared_infra.md`)

**Phase 1 — Core (F1-F4) + rogue_mud (F5):**
- F1: 5 core I/O builtins (`@putChar`, `@stderrWrite`, `@getChar`, `@exit`, `@sleepMs`)
- F2: 4 console builtins (`@isWindows`, `@consoleClear`, `@consoleGotoxy`, `@consoleSetColor`)
- F3: `std_arena.zig` + json_parser + json_parser_workaround migration
- F4: `std.zig` + `std_io.zig` + migrate all 21 examples + remove dead `__bootstrap_*`
- F5: rogue_mud console externs → builtins

**Phase 2 — Networking (F6):**
- F6: 11 networking builtins + mud_server verification

**Closeout (F7):**
- F7: gate sweep + full matrix + EXPECTED_FAIL.md v29

## 7. Success Criteria

- 20 builtins implemented (sema + lowerer + C89 emitter with per-target `#ifdef`)
- `std.zig`, `std_io.zig`, `std_arena.zig` exist with pure Z98 bodies (zero `extern "c"`)
- All 21 examples compile + link + run via `@import("std")` (no `__bootstrap_*` externs)
- json_parser + json_parser_workaround link rc=0 + run rc=0 (standard runtime, no legacy file)
- rogue_mud link rc=0 + runs (console builtins)
- mud_server still compiles + links + runs (Phase 2 networking builtins)
- `__bootstrap_print/write/print_int/print_char/panic/sleep_ms/getchar` removed from `zig_runtime.c`
- 4 MD5 gates byte-identical (json re-baseline only if emitted C changes, with runtime proof)
- Corpus: manifest 230 repros OK=223/FAIL=3/gg=4 (FAIL not increased)
- zig1 source unchanged (bootstrap constraint honored)

## 8. Out of Scope

- **zig1 source migration to std lib** — bootstrap constraint (zig0 can't compile builtins). Deferred to the self-hosted zig1.5/zig2 plan.
- **zig1 self-compile full cycle** — gated on the F5 scratch-arena OOM (future investigation)
- **`#ifdef` for future targets beyond msvc6/openwatcom/posix** — catalog covers these 3; new targets add emission branches later
- **Removing `zig_pal.c`** — kept for zig0 bootstrap reference; Phase 2 evolution may shrink it
- **16-bit target support** — the architecture is 16-bit-compatible (no size assumptions in std lib), but actual 16-bit emission is future work
