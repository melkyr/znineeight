# plat_stubs_missing_xmod — OK-by-gate/LATENT (platform stubs missing from runtime, NOT a compiler defect)  [R1d, 2026-08-08]

## What it tests
A cross-module call to the Windows console platform layer:
`console.zig` declares `extern "c" fn plat_is_windows() bool;` and
`extern "c" fn plat_console_putchar(c: i32) void;`, and `doConsole()`
calls both. `main.zig` imports `console.zig` and calls `c.doConsole()`.
Minimal version of `examples/z98/rogue_mud` (gcc link FAIL:
`plat_is_windows`, `plat_console_setcolor`, `plat_console_gotoxy`,
`plat_console_putchar`, `plat_console_clear` — MEM4).

## The compiler gap (NOT a compiler defect — D4, out-of-scope)
zig1's runtime library (`sf/src/include/zig_runtime.c` + `zig_pal.c` +
`net_runtime.c`) provides NO console/platform-detection layer. The `extern`
calls emit correctly and gcc compiles every module clean; the LINK fails
because the symbols are simply not defined anywhere in the runtime. This is
a missing-runtime-library gap (a future std-lib plan), not a C89 emission
bug.

## Measured result (2026-08-08, sf/build/out_release/zig1)
- dump rc=0, `.c`/`.h` emitted.
- gcc `-c` of each emitted `.c`: rc=0 (0 errors).
- gcc link: rc=1 — `undefined reference to plat_is_windows`,
  `plat_console_putchar` (both from console_*.c).
- Classification: **OK-by-gate/latent** — the compiler produces correct C;
  the gap is in the runtime library (mirrors `opt_slice_null_return`'s
  "OK-by-gate/latent, not counted as a corpus FAIL" precedent). Feeds the
  future std-lib plan.

## plat_ symbol catalog (measured 2026-08-08)
PRESENT — `sf/src/include/net_runtime.c` socket family (**12 symbols**):
`plat_accept`, `plat_bind_listen`, `plat_close_socket`,
`plat_create_tcp_server`, `plat_recv`, `plat_send`, `plat_socket_cleanup`,
`plat_socket_fd_isset`, `plat_socket_fd_set`, `plat_socket_fd_zero`,
`plat_socket_init`, `plat_socket_select`.
(Note: the plan/brief cites "14 symbols" — measured count is 12; all
socket-family.)
MISSING — console/platform-detect family (**5 symbols**, all requested by
rogue_mud, none in zig_runtime.c / zig_pal.c / net_runtime.c):
`plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
`plat_console_putchar`, `plat_console_clear`.

## Oracle verification (zig0)
`sf/build/zig0` on a /tmp copy: dump rc=0, gcc compile rc=0, and the SAME
link failure (`undefined reference to plat_is_windows`,
`plat_console_putchar`). This confirms the gap is in the runtime library,
NOT the compiler — zig0 emits equivalent C that also fails to link.

## Deferred to std-lib (D4, operator ruling)
The **5 missing stubs** — `plat_is_windows`, `plat_console_gotoxy`,
`plat_console_setcolor`, `plat_console_putchar`, `plat_console_clear` —
are **ALL rogue_mud-only** (declared in `examples/z98/rogue_mud/ui.zig`);
no other example requests the console/platform-detect family. zig0 fails
IDENTICALLY (same undefined-reference link rc=1) → this is a
**runtime-library gap, NOT a compiler defect**. **Deferred to the
std-zig1 library — NOT fixed here** (no compiler changes, no runtime-file
changes). Feeds the future std-lib plan: add a console/platform-detect
layer (5 stubs) to the runtime — `plat_is_windows` + `plat_console_*`,
target signatures from `rogue_mud/ui.zig` (mirroring `net_runtime.c`).
This repro is the guard (flips to link-ok when the stubs land).

## Expected classification
OK-by-gate/latent (D4, out-of-scope). NOT counted as a corpus FAIL. Will
link when the future std-lib plan adds the console/platform-detect stubs.
