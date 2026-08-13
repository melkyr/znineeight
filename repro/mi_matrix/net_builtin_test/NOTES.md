# net_builtin_test — Networking builtins (F6) [Task F6, 2026-08-13]

## What it tests
All 11 F6 networking builtins in one process (client + server on 127.0.0.1):
`@socketCreate` (server on 4001 + client on ephemeral 0), `@socketBindListen`,
`@socketConnect` (success + negative test: connect to a closed port must return -1),
`@socketSelect`, `@socketFdZero`/`@socketFdSet`/`@socketFdIsset`,
`@socketAccept`, `@socketSend`/`@socketRecv` (5-byte echo round-trip),
`@socketClose`. Uses `std_net.fd_set` + `std_net`-style builtin calls (local
`std.zig`/`std_io.zig`/`std_arena.zig`/`std_net.zig` copies; D1 no-search-path
precedent).

## Measured result (2026-08-13, /tmp/fx_subfolder/zig1)
- **dump rc=0** — 5 modules emit (main, std, std_io, std_arena, std_net).
- **gcc -c rc=0** — 0 errors, emitted socket C carries the `#ifdef _WIN32`/`#else`
  ported bodies inline (0 `net_runtime.c` / 0 `plat_*` refs).
- **link rc=0** — WITHOUT `net_runtime.c` (standard `zig_runtime.c` + `zig_pal.c`).
- **run rc=0** — prints `1` (`std.io.printInt(1)` after all 11 builtins exercise
  cleanly). `@socketConnect` to a closed port correctly returns -1.
- Corpus classifier: **OK** (240-dir sweep: OK=233 FAIL=3 ICE=0 CRASH=0 GREEN=4).

## Notes
The emitted `@socketSelect` handles null optional args correctly (bare `NULL` passed to
`select()` — the null-literal temp is not type-tracked, so no `.value` deref). The `fd`
convention is plain i32 (arch-independence ruling m0544). `init`/`cleanup` are std_net.zig
no-ops on POSIX (WSAStartup/WSACleanup not auto-emitted — Win-only lifecycle caveat).
