# Win32 Cross-Compile Pre-Test — Design

**Date:** 2026-09-04. Branch: `zig1_start`. Status: design (approved scope; pending implementation).

## Purpose

Before the operator "pulls the trigger" (zig0 closeout, release notes, merge), prove that the C89 emitted by the zig1 self-hosted compiler can be **cross-compiled to win32 executables** with `i686-w64-mingw32-gcc` and **run under 32-bit `wine`**, with behavior byte-parity to the already-verified linux runs. This is the pre-test for a subsequent check in the operator's win9x VM. It is a **test/report plan — no source edits**.

## Operator rulings (binding)

1. **Program scope:** all 4 gate programs (`game_of_life`, `lisp_interpreter_curr`, `json_parser`, `mud_server`) + both `_upgraded` showcase programs (`lisp_interpreter_upgraded`, `rogue_mud_upgraded`, incl. the local `i` demo) + the net demo (rogue net variant server+client and `mud_server` server — the win-socket path).
2. **Runtime fix scope:** **report gaps only — zero `sf/src` edits** (no changes to `sf/src/include/*.c`, the emitter, parser, sema, or any example source). Any win32-path breakage is recorded as a gap, not fixed.
3. **`ZIG_NO_CRT`:** include **one** no-CRT smoke now (the `#if defined(_WIN32) && defined(ZIG_NO_CRT)` `mainCRTStartup`+`ExitProcess` path in `zig_pal.c`), run under wine, closest proxy for the win9x VM.
4. **Self-host cross:** **also cross-compile the compiler** (`sf/src/main.zig` → C89 → mingw win32 PE) and run it under wine on a small input (report-only; gaps recorded, not fixed).

## Environment

- `i686-w64-mingw32-gcc` (GCC 12-win32) — 32-bit win32 cross compiler; also present: `x86_64-w64-mingw32-gcc`, `i686-w64-mingw32-ld`, `gdb-multiarch`.
- `wine 8.0` (Debian) — 32-bit-capable; use a `WINEARCH=win32` prefix for 32-bit PE runs.
- Reference compiler: `/tmp/fx_subfolder/zig1` (md5 `7c08d2d5`; std lib at `/tmp/fx_subfolder/lib`).
- Existing linux run/verify harness: `scripts/closeout/run_upgraded.sh`, `scripts/closeout/verify_upgraded.sh`; goldens under `examples/z98/*_upgraded/demo/` and `/tmp/fx_fix/{golden_ref,matrix_ref}`.

## Runtime portability facts (read at HEAD 9dbacdfe)

- `sf/src/include/zig_compat.h`: C89 typedefs; has `_MSC_VER`, `__WATCOMC__`, plain paths (retro ambitions already present).
- `sf/src/include/zig_pal.c`: full `#ifdef _WIN32` split — `pal_print_stdout/stderr` via `WriteConsoleA`→`WriteFile` fallback; `pal_file_open/write/close` via `CreateFileA`/`WriteFile`/`CloseHandle`; `pal_abort` via `TerminateProcess`; `pal_get_default_lib_path` via `GetModuleFileNameA` (win9x-comment). Plus `ZIG_NO_CRT` `mainCRTStartup`.
- `sf/src/include/net_runtime.c`: `#ifdef _WIN32` winsock (`winsock.h`, `WSAStartup`/`WSACleanup`, `SOCKET` casts, `closesocket`, `#pragma comment(lib,"wsock32.lib")`), POSIX otherwise.
- **Net link rule (QUICK_REF, authoritative):** modern F6-migrated `mud_server` (z98) does **not** need `net_runtime.c` (the 11 socket builtins / `std_net.zig` lower inline); legacy/pre-F6 examples DO need it. The exact per-program link set is captured from QUICK_REF during Task 0.
- Compiler `sf/src` imports only `std.zig` (`std_io`, `std_arena`) + its modules — **not** `std_net`. File reads go through `pal.zig` → libc `fopen`/`fread`/`fclose` (CRT, available in mingw msvcrt). So compiler cross-compile needs no winsock.

## Success criteria

1. Toolchain smoke: trivial C89 compiles with `i686-w64-mingw32-gcc` and runs under the win32 wine prefix.
2. Every in-scope program: cross-compiles rc=0 (0 `error[`, 0 PANIC at dump; gcc/link rc=0), runs under wine, and its stdout matches the corresponding linux golden byte-for-byte (masked rules unchanged: lisp demo `(address)` line is per-run on both platforms).
3. Net programs (mud_server server, rogue net variant server+client) run under wine via winsock on localhost with the documented poll/timeout discipline and produce their expected output.
4. One `ZIG_NO_CRT` build links and runs under wine.
5. Compiler self-host cross: `sf/src/main.zig` dumps C89, mingw-cross-compiles to a win32 PE, and that PE dumps at least one small input under wine.
6. A verdict report (program × cross-compile / wine-run / byte-parity) + a gaps list; any failure is classified gap vs environment vs toolchain and reported — never silently fixed.

## Out of scope

- Any edit to `sf/src`, `sf/src/include/*`, `examples/*`, gate programs, or goldens.
- Full corpus win32 sweep (scope = the enumerated set).
- `x86_64` (win64) target; win9x VM pass (operator-owned, later).
- EXPECTED_FAIL.md / QUICK_REF.md reconciliation (deferred to closeout, operator-ruled).

## Risks / open verification points

- No wine run has been executed yet; Task 0 must surface: wine prefix init, 32-bit PE execution, stdout newline semantics (pal uses `WriteFile` raw `\n` when stdout is redirected — parity expected but unproven), stdin piping into win32 console programs (lisp feeds), and mingw C89 flag quirks.
- `ZIG_NO_CRT` binaries depend only on kernel32 (ExitProcess); link order/entry (`-e mainCRTStartup` or the pal-provided stub) must be validated in Task 4.
