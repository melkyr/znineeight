# std_net Extern OS Bindings + Target-Aware `@isWindows()` — Design Spec

> Date: 2026-09-05 · Branch: zig1_start · Status: operator-approved design (brainstorming closed)

## Goal

Make Z98 networking work correctly on win9x/win32 AND Linux by moving all OS-facing networking out of the compiler and into the `std_net` standard library, expressed as `extern "c"` OS bindings selected per compile target — the "normal compiler" model. Remove the compiler's socket knowledge entirely (the 11 socket builtins and their `#ifdef` C bodies). Give the compiler a target model so `@isWindows()` (and target selection) is correct.

## Background / problem (evidence)

- The F6-era migration made `std_net` a thin wrapper over 11 compiler **builtins** (`@socketCreate` … `@socketClose`). `c89_emit.zig` emits their bodies as target-agnostic C with `#ifdef _WIN32/#else`, and gates a winsock include block via `moduleHasNetBuiltin` (`c89_emit.zig:2244`).
- The emitted programs **never call `WSAStartup`**, so under wine/win32 `socket()` returns `WSANOTINITIALISED` (10093). Reproduced (win32 cross pre-test Task 2, `task-WIN32-report.md`): `mud_server` cannot bind (`Failed to create server socket`); `rogue net_main` degrades to local-only. Wine winsock itself is capable (control probe PASS) — the gap is in the emitted code.
- `@isWindows()` folds from a hardcoded constant `config.zig:4 host_is_windows = false`, so it is never target-aware (`comptime_eval.zig:212-217`). There is no target flag in `main.zig`.
- Non-variadic `extern "c"` functions are not forward-declared by the emitter (`c89_emit.zig:2281` skips them); they rely on `@cInclude`'d C headers (precedent: `persistence.zig` uses `@cInclude("<stdio.h>")` + `extern "c" fn fopen/fwrite/...`).
- `FD_ZERO`/`FD_SET`/`FD_ISSET` are C **macros** over the `fd_set` struct on Windows — not callable symbols — so the win32 `fd_set` layout and bit operations must be expressed in Z98, as real Zig does for `std.os.windows`.

## Operator rulings (binding)

1. **Full clean state**, no partial/hybrid end state. No release pressure: correctness and a well-scoped, divided plan are preferred over speed.
2. **One plan document** with incremental **sections**; each section carries its own I (investigation) and F (implementation) tasks: (S1) target model + `@isWindows()`; (S2) `std_net` extern rewrite; (S3) socket-builtin removal; (S4) gates/verification.
3. **Target flags:** `-osl` (linux, default) / `-osw` (windows); long form `--target linux|windows` accepted as an alias.
4. **Winsock surface = Winsock 1.1 via `wsock32`** (win9x-compatible), not `ws2_32`. `WSAStartup(MAKEWORD(1,1), &wsa)`.
5. **`htons`/`htonl` stay as extern `wsock32`/libc functions**; additionally provide **manual byte-swap helper functions** in `std_net` (debugging convenience).
6. The extern/include emission mechanism (platform-conditional include vs auto-emitted extern prototypes vs other) is **not decided by preference** — a dedicated I task settles it against the emitter architecture.
7. **Public `std_net` API unchanged** → `mud_server`, `rogue_mud`, `rogue_mud_upgraded`, and the net client need zero source edits. (Socket programs' *link* recipe on win32 keeps `-lwsock32`.)
8. `std_net.fd_set` public blob `[128]u32` (512B, covers win 260B / linux 128B) stays as the exported type; real per-target layout structs are internal, cast to/from the blob pointer.
9. The 4-MD5 `mud_server` gate (`53405b3b`) and the self-compile fixed point (`85733145`) will move — re-baseline only via explicit operator ruling; gol/lisp/json gates must stay byte-identical.

## Architecture

### Target model (S1)

- `main.zig` CLI accepts `-osl`/`-osw` (and `--target linux|windows`), defaulting to linux. The choice is stored in a compiler runtime config field (replacing the hardcoded `host_is_windows` const path).
- `@isWindows()` comptime-folds from the target config (windows ⇒ true).
- Consequences: comptime `if (@isWindows())` branches are selected at dump time; the emitted C for the net path is target-specific, containing only the selected platform's extern calls. The `_WIN32`-based `#ifdef` bodies in the socket builtins become obsolete and are deleted in S3.

### extern emission mechanism (S1-I verdict → used by S2/S3)

The I task decides between (hypotheses):
- **(a) platform-conditional `@cInclude`** — a way to emit `#include` guarded to a target (e.g. `#ifdef _WIN32`) or a `@cInclude` variant that only emits under the selected target;
- **(b) emitter auto-prototypes externs** — emit C forward declarations for non-variadic `extern "c"` functions (relax the `c89_emit.zig:2281` skip) so no system header is required;
- **(c) other**, if the investigation finds one better fit.
Winner is implemented and then used so `std_net` bindings compile cleanly under both `gcc -m32` and `i686-w64-mingw32-gcc`.

### std_net extern rewrite (S2)

`sf/src/std_net.zig` becomes pure Z98 + `extern "c"` OS bindings, split by `if (@isWindows())` comptime selection:

- **windows (`-osw`) — wsock32 (Winsock 1.1):**
  - extern: `WSAStartup`, `WSACleanup`, `socket`, `bind`, `listen`, `accept`, `connect`, `recv`, `send`, `select`, `closesocket`, `htons`, `htonl`.
  - Z98-defined layouts (internal): `WSADATA` (400B), `sockaddr_in` (16B), `timeval` (8B), `fd_set` = `{ fd_count: u32, fd_array: [64]u32 }` (260B).
  - `FD_ZERO`/`FD_SET`/`FD_ISSET` implemented as Z98 struct writes/bit-ops over the internal `fd_set`.
  - `SOCKET` ≡ `u32` (i686). Return convention: convert `INVALID_SOCKET`/`SOCKET_ERROR` to `-1` as today.
- **linux (`-osl`) — libc:**
  - extern: `socket`, `bind`, `listen`, `accept`, `connect`, `recv`, `send`, `select`, `close`, `htons`, `htonl`.
  - internal `fd_set` = `{ fds_bits: [32]u32 }` (128B); `FD_ZERO`/`FD_SET`/`FD_ISSET` = Z98 bit-ops.
- **init/cleanup:** windows `init()` = `WSAStartup(MAKEWORD(1,1), &wsa)` ≠ 0 → propagate nonzero (mud_server checks it); `cleanup()` = `WSACleanup()`. linux `init()` returns 0, `cleanup()` no-op.
- **Manual byte-swap helpers** added (public or internal per implementation choice): e.g. `htonsManual(u16) u16` / `htonlManual(u32) u32`, documented as debug alternatives to the extern `htons`/`htonl`.

### Socket-builtin removal (S3)

Delete every trace of the 11 socket builtins:
- `semantic_analyzer.zig`: struct fields (socket_*_name_id, ~:81-91), intern assignments (~:232-242), the supported-membership helper lines (~:296-306), the dispatch arms (~:1683-1718). Also remove from the `semanticAnalyzerIsBuiltinSupported` whitelist (F-CLEANDIAG) so `@socket*` yields the clean "unsupported builtin" error.
- `lower.zig`: name-id fields/intern/assign (~:396,:491-492,:562) + any socket branches.
- `c89_emit.zig`: the `#ifdef` C bodies (~:4573-4811), `moduleHasNetBuiltin` and the winsock include embed in `emitBuiltinIncludes` (~:2225-2247), any socket type-name handling.
- Full reference inventory happens in the S3-I task (removal completeness is the deliverable).

### Gates (S4)

- Re-run the win32 cross net matrix under `-osw` + wine: `mud_server` binds (`MUD server listening on port 4000` + response), rogue net demo (`net_main` + client) runs against `demo/net_demo_expected.txt` (LF-normalized parity, no extra warning line), client rc=0.
- Linux net under `-osl` still works: mud_server runtime boot/move, rogue net single/MP demos, net parity goldens unchanged.
- Full battery: golden 9/9, matrix 21/21, corpus 426 `-s0`, 4-MD5 gates (gol/lisp/json byte-identical; mud re-baselined by operator ruling), self-compile round-trip fixed point re-baselined by operator ruling.
- Win9x readiness note recorded.

## Out of scope

- The win32 console-rendering gap (rogue move feed; `@consoleGotoxy`/`@consoleSetColor` → `SetConsole*` invisible to stdout). Already classified platform/representation; separately VM-verified.
- `net_runtime.c` deletion/retention (the file remains in the tree as reference/legacy unless a task shows it is now fully dead; its `plat_socket_*` helpers become unused by `std_net`).
- The NO_CRT `system("cls")` issue in `game_of_life`.
- Any win9x *loader* work (PE subsystem/import checks already passed; real-loader compatibility is the operator's VM step).

## Success criteria

1. `-osl`/`-osw` select the target; `@isWindows()` folds correctly; RED fixture flips output per target.
2. `mud_server` + rogue net under `-osw`/wine bind and serve (no `10093`), matching linux behavior byte-for-byte (LF-normalized parity).
3. `std_net` public API unchanged; example sources unmodified.
4. Zero socket builtins remain in the compiler; `@socketCreate` etc. produce the clean unsupported-builtin error.
5. gol/lisp/json 4-MD5 gates byte-identical; mud + self-compile fixed point re-baselined only by operator ruling; full battery green.
6. Manual byte-swap helpers + extern `htons`/`htonl` both present and correct.
