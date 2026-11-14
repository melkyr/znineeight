# io_builtin_test — Core I/O builtins (Task F1, 2026-08-08)

## What it tests
Exercises all 6 new compiler builtins end-to-end: `@putChar(u8)→void`,
`@stdoutWrite([*]const u8, usize)→void`, `@stderrWrite([*]const u8, usize)→void`,
`@getChar()→u8`, `@exit(u8)→noreturn`, `@sleepMs(u32)→void`.

## Expected output (stdin = `x`)
- stdout: `H` `i` (two `@putChar`), `Hello` (`@stdoutWrite`), then the getchar echo
  (`__bootstrap_print_int` prints the decimal value of the byte read: `'x'` = `120`).
- stderr: `ERR` (`@stderrWrite`).
- run rc=0 (`@exit(0)`).

Measured stdout = `120HiHello`, stderr = `ERR`, run rc=0.

## Upstream defect (fixed by Task F1)
- The 6 builtins were silently dropped: sema/lower had no dispatch, so `builtin_call`
  fell through to the generic path and emitted nothing (dump rc=0, no C).
- Pre-existing parser gap (uncovered by `@getChar`): `parserParseBuiltinCall`
  (`parser.zig`) always parsed ≥1 argument, so a **zero-arg** builtin like
  `@getChar()` failed with `error[2000]` "expected expression". Fixed by breaking out
  of the arg loop on a leading `)` (parser.zig:581).

## Measured result (recorded 2026-08-08)
- RED: `@getChar()` → dump rc=2 (`error[2000]`); the other 5 builtins dump rc=0 but
  emit NO C (silently dropped).
- GREEN: dump rc=0, gcc rc=0 (single- AND multi-module `--output-dir`), run rc=0,
  stdout `120HiHello`, stderr `ERR`.
- Emitted C: `putchar(zT_0);` / `fwrite(zT_4, 1, zT_5, stdout);` /
  `fwrite(zT_7, 1, zT_8, stderr);` / `zT_13 = getchar();` / `exit(zT_15);` /
  `#ifdef _WIN32 Sleep(zT_10); #else usleep(zT_10 * 1000); #endif`.
- Includes emitted only when used: `#include <stdio.h>` (putChar/stdoutWrite/
  stderrWrite/getChar), `#include <stdlib.h>` (exit), guarded
  `#ifdef _WIN32 #include <windows.h> #else #include <unistd.h> #endif` (sleepMs).
- Classifies OK per the QUICK_REF corpus gate. See EXPECTED_FAIL.md / plan report
  `.superpowers/sdd/task-F1-builtin-report.md`.
