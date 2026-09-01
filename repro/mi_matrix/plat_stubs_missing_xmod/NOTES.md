# plat_stubs_missing_xmod — FULLY OK (F5: console builtins migration closed the D4 gap)  [R1d → F5, 2026-08-13]

## What it tests
A cross-module call to the console/platform-detect layer:
`console.zig` originally declared `extern "c" fn plat_is_windows() bool;` and
`extern "c" fn plat_console_putchar(c: i32) void;`, and `doConsole()` called
both. `main.zig` imports `console.zig` and calls `c.doConsole()`.
Minimal version of `examples/z98/rogue_mud` (gcc link FAIL on the 5 missing
console stubs — MEM4).

## The compiler gap (NOT a compiler defect — D4, out-of-scope)
zig1's runtime library (`sf/src/include/zig_runtime.c` + `zig_pal.c` +
`net_runtime.c`) provides NO console/platform-detection layer. The `extern`
calls emitted correctly and gcc compiled every module clean; the LINK failed
because the symbols were not defined anywhere in the runtime. This was a
missing-runtime-library gap (std-lib-deferred), not a C89 emission bug.

## Measured result (2026-08-08, sf/build/out_release/zig1) — RED (pre-F5)
- dump rc=0, `.c`/`.h` emitted.
- gcc `-c` of each emitted `.c`: rc=0 (0 errors).
- gcc link: rc=1 — `undefined reference to plat_is_windows`,
  `plat_console_putchar` (both from console_*.c).
- Classification: **OK-by-gate/latent** — the compiler produced correct C;
  the gap was in the runtime library (mirrors `opt_slice_null_return`'s
  "OK-by-gate/latent, not counted as a corpus FAIL" precedent).

## F5 migration + GREEN result (2026-08-13)
**F5 (std-zig1 lib plan, console builtins migration) closed the D4 gap the
F2 way — via the compiler builtins, not runtime stubs.** `console.zig`
migrated off the 2 externs to the builtins: `plat_is_windows()` →
`@isWindows()` (comptime-folds to 0 on POSIX host) and
`plat_console_putchar('X')` → `@putChar('X')`. This mirrors the rogue_mud
`ui.zig` migration (the 5 `plat_*` console externs → `@isWindows`/
`@consoleClear`/`@consoleGotoxy`/`@consoleSetColor`/`@putChar`).
- dump rc=0, all modules emit.
- gcc `-c` rc=0; **link rc=0** (standard recipe: `zig_runtime.c` +
  `zig_pal.c`); run rc=0.
- Classification: **FULLY OK** — the D4 OK-by-gate/latent deferral is CLEARED.

## plat_ symbol catalog (measured 2026-08-08)
PRESENT — `sf/src/include/net_runtime.c` socket family (**12 symbols**):
`plat_accept`, `plat_bind_listen`, `plat_close_socket`,
`plat_create_tcp_server`, `plat_recv`, `plat_send`, `plat_socket_cleanup`,
`plat_socket_fd_isset`, `plat_socket_fd_set`, `plat_socket_fd_zero`,
`plat_socket_init`, `plat_socket_select`.
MISSING-then-CLOSED — console/platform-detect family (**5 symbols**, all
rogue_mud-only, none in zig_runtime.c / zig_pal.c / net_runtime.c):
`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
`plat_console_putchar`, `plat_console_clear`. **CLOSED by F5 via the F2
console builtins** (no runtime stubs added; rogue_mud + this repro now use
the builtins directly).

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy: dump rc=0, gcc compile rc=0, and the SAME
link failure (`undefined reference to plat_is_windows`,
`plat_console_putchar`). This confirmed the gap was in the runtime library,
NOT the compiler — zig0 emits equivalent C that also fails to link.

## Expected classification
FULLY OK (F5 2026-08-13). The D4 OK-by-gate/latent deferral is CLEARED —
the guard now links + runs on the standard recipe.
