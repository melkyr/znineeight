# console_builtin_test — Console builtins (Task F2, 2026-08-08)

## What it tests
Exercises the 4 new compiler builtins end-to-end:
- `@consoleClear() → void` — clears the terminal (POSIX ANSI `\x1b[2J\x1b[H`;
  Win32 `FillConsoleOutputCharacter`+`FillConsoleOutputAttribute`+home).
- `@consoleGotoxy(x, y) → void` — moves the cursor (POSIX ANSI `\x1b[%d;%dH`
  with (y+1, x+1); Win32 `SetConsoleCursorPosition(COORD)`).
- `@consoleSetColor(fg, bg) → void` — sets fg/bg (POSIX ANSI `\x1b[%s;%sm` fg/bg
  tables; Win32 `SetConsoleTextAttribute`).
- `@isWindows() → bool` — **comptime-folded** intrinsic: folds to `true` (1) on a
  Win32 build, `false` (0) on a POSIX build. `if (@isWindows())` folds so only the
  active branch is emitted in C.

## Expected output (POSIX build)
- stdout: ANSI escapes from clear/gotoxy/setcolor, then `POSIXBRANCH` (the else
  branch of the folded `@isWindows()` if) and `0` (`@isWindows()` folded to false,
  printed via `__bootstrap_print_int`).
- run rc=0 (`@exit(0)`).
- Note: `@stdoutWrite` uses libc stdio (buffered); the raw PAL writes (ANSI escapes,
  `__bootstrap_print_int`) flush first, so under redirection the numeric `0` can
  appear before `POSIXBRANCH`. Content is all present and correct.

## Gate (recorded 2026-08-08)
- RED (before F2): the 3 console builtins are silently dropped — dump rc=0, no C
  emitted (sema/lower have no dispatch, same as F1's pre-fix state); `@isWindows()`
  is undeclared (not dispatched) so the test has no valid emission.
- GREEN: dump rc=0, gcc rc=0, run rc=0.
- Emitted C has the `#ifdef _WIN32 / #elif defined(__WATCOMC__) / #else` guard chain
  (POSIX ANSI arm active on this build) and `if (@isWindows())` folds to ONLY the
  else branch (`WINBRANCH` absent, `POSIXBRANCH` present).
