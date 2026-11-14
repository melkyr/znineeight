# Task 2 report — Win9x console backend

**Status:** DONE.

**Commit sha:** `d86b3441` `example(z9play): Win9x console backend`
(2 files, 426 insertions: `platform/console_win9x.zig`,
`platform/console_win9x_pal.zig`).

## What changed

- `examples/z98/z9play/platform/console_win9x.zig` (new) — complete M5b
  `Console` contract as nine public free functions matching
  `platform/console.zig` exactly (`enterRaw`, `leaveRaw`, `readKey`, `clear`,
  `setCursor`, `writeStr`, `width`, `height`, `cursorShow`). The caller
  assembles the `Console` literal; no function returns `Console` (D8 note kept).
  `ConsoleWinState` holds the saved input handle/mode and an `entered` flag.
- `examples/z98/z9play/platform/console_win9x_pal.zig` (new) — `extern
  "stdcall"` Win32 externs, `@cInclude("<windows.h>")`/`<stdlib.h>`, and the
  `COORD`/`SMALL_RECT`/`CONSOLE_SCREEN_BUFFER_INFO`/`CONSOLE_CURSOR_INFO`/
  `KEY_EVENT_RECORD`/`INPUT_RECORD` mirrors (mirrors live in the PAL because
  `COORD` is passed by value, so the externs and backend must name one type).

Behaviour mapped exactly as the task context specifies:

- `enterRaw`: `GetConsoleMode` saves the input mode; `SetConsoleMode` clears
  `ENABLE_LINE_INPUT` (0x0002) and `ENABLE_ECHO_INPUT` (0x0004) and keeps
  `ENABLE_PROCESSED_INPUT` (0x0001). Non-console handle (`GetConsoleMode`
  fails) is a no-op. Idempotent guard/reset of the sticky SIGINT flag.
- `leaveRaw`: restores the saved mode, idempotent, unregisters the control
  handler. Safe/cheap for Task 3 to call before every `std.os.exit`.
- Crash backstop: `SetConsoleCtrlHandler` (restore on
  C/BREAK/CLOSE/LOGOFF/SHUTDOWN; C/BREAK also set the sticky flag and return
  TRUE) plus `atexit(restoreAtExit)`. C/BREAK do not restore raw mode because
  the process continues and `readKey` must return `.sigint`.
- `readKey`: non-blocking `GetNumberOfConsoleInputEvents` then
  `ReadConsoleInputA`; skips non-KEY_EVENT and key-up records; maps
  `VK_UP/DOWN/LEFT/RIGHT` (0x26/0x28/0x25/0x27), `VK_RETURN` (0x0D),
  `VK_ESCAPE` (0x1B), else `.char` from the low byte of `uChar` when non-zero;
  sticky Ctrl-C flag takes priority -> `.sigint`; no event -> `.none`.
- `clear`: `FillConsoleOutputCharacterA(' ', dwSize.X*dwSize.Y, {0,0})` then
  `SetConsoleCursorPosition({0,0})`.
- `setCursor`: `COORD{x=col, y=row}` (0-based, same convention as Linux).
- `writeStr`: `WriteConsoleA`.
- `width`/`height`: `GetConsoleScreenBufferInfo` -> `dwSize.X/Y` (the context's
  chosen mapping; documented in the file), 80x24 fallback on failure/zero.
- `cursorShow`: `GetConsoleCursorInfo` + set `bVisible` +
  `SetConsoleCursorInfo`.

## Struct-layout evidence

Mingw oracle (build + run under Wine; the Win32 headers' real layout):

```sh
i686-w64-mingw32-gcc -std=c89 -m32 -Wall -o /tmp/m6t2_probe/layout.exe /tmp/m6t2_probe/layout.c
WINEDEBUG=-all timeout 60 wine /tmp/m6t2_probe/layout.exe
# COORD size=4 x=0 y=2
# SMALL_RECT size=8 left=0 top=2 right=4 bottom=6
# CONSOLE_SCREEN_BUFFER_INFO size=22 dwSize=0 dwCursorPosition=4 wAttributes=8 srWindow=10 dwMaximumWindowSize=18
# CONSOLE_CURSOR_INFO size=8 dwSize=0 bVisible=4
# KEY_EVENT_RECORD size=16 bKeyDown=0 wRepeatCount=4 wVirtualKeyCode=6 wVirtualScanCode=8 uChar=10 dwControlKeyState=12
# INPUT_RECORD size=20 EventType=0 Event=4
# WINE_RC=0
```

Z98 mirror probe (`@sizeOf`/`@offsetOf` printed by a `-osw` program under Wine):

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/_probe_m6t2_layout.zig /tmp/m6t2_probe/layoutz \
    /tmp/m6t2_probe/layoutz/z9play.exe
# dump: rc=0 error_brk=0 panic=0 c=5 link ok
# XRUNRC=0
WINEDEBUG=-all timeout 60 wine /tmp/m6t2_probe/layoutz/z9play.exe
# COORD size=4 x=0 y=2
# SMALL_RECT size=8 left=0 top=2 right=4 bottom=6
# CONSOLE_SCREEN_BUFFER_INFO size=22 dwSize=0 dwCursorPosition=4 wAttributes=8 srWindow=10 dwMaximumWindowSize=18
# CONSOLE_CURSOR_INFO size=8 dwSize=0 bVisible=4
# KEY_EVENT_RECORD size=16 bKeyDown=0 wRepeatCount=4 wVirtualKeyCode=6 wVirtualScanCode=8 uChar=10 dwControlKeyState=12
# INPUT_RECORD size=20 event_type=0 key=4
# WINE_RC=0
```

**Result:** every mirror size/offset matches the mingw `offsetof`/`sizeof`
oracle byte-for-byte.

## Cross-build evidence (`-osw`, mingw)

Probe entry (scratch, removed before commit) imported only the new backend and
called all nine operations:

```zig
const con = @import("platform/console_win9x.zig");
pub fn main() void {
    var st: con.ConsoleWinState = undefined;
    var p: *void = @ptrCast(*void, &st);
    con.enterRaw(p);
    _ = con.readKey(p);
    con.clear(p);
    con.setCursor(p, 0, 0);
    con.writeStr(p, "probe");
    _ = con.width(p);
    _ = con.height(p);
    con.cursorShow(p, true);
    con.leaveRaw(p);
}
```

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/_probe_m6t2.zig /tmp/m6t2_probe/cross2 \
    /tmp/m6t2_probe/cross2/z9play.exe
# dump: rc=0 error_brk=0 panic=0 c=7 link ok
# XRUNRC=0
file /tmp/m6t2_probe/cross2/z9play.exe
# PE32 executable (console) Intel 80386, for MS Windows, 17 sections
```

`-osw --dump-c89` md5 (two runs, rc=0 both, identical):

```sh
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 examples/z98/z9play/_probe_m6t2.zig > /tmp/m6t2_probe/probe_osw_dump1.c89
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 examples/z98/z9play/_probe_m6t2.zig > /tmp/m6t2_probe/probe_osw_dump2.c89
md5sum /tmp/m6t2_probe/probe_osw_dump1.c89 /tmp/m6t2_probe/probe_osw_dump2.c89
# 224b09a61deec5d5ab479ab9485b3ebb  probe_osw_dump1.c89
# 224b09a61deec5d5ab479ab9485b3ebb  probe_osw_dump2.c89
```

Optional Wine smoke of the console probe:

```sh
WINEDEBUG=-all timeout 30 wine /tmp/m6t2_probe/cross2/z9play.exe
# WINE_RC=0
```

(No stdout was captured because Wine does not forward `WriteConsoleA` when the
process stdout is redirected; this probe was an exit/non-blocking check only.
Runtime key/cursor semantics are Task 4's tier.)

## Full-program `-osw` status (Task 3 scope, pre-ruling)

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/main.zig /tmp/m6t2_probe/cross_main \
    /tmp/m6t2_probe/cross_main/z9play.exe
# console_linux_FED0416D.h:6:10: fatal error: termios.h: No such file or directory
# XRUNRC=GCCFAIL
```

Expected: `main.zig` still unconditionally imports `console_linux`; Task 3 wires
`@isWindows()` selection. T2's gate is the probe-level `-osw` build above.

## Linux tiers (post-change)

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_probe/tier_console sh examples/z98/z9play/tests/tier_console.sh
# == tier_console summary: 11 passed, 0 failed ==
# TIER_CONSOLE PASS

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_probe/tier_cli sh examples/z98/z9play/tests/tier_cli.sh
# == tier_cli summary: 23 passed, 0 failed ==
# --dump-c89 md5: 3e169dc210e531b508029b270e8418ef (stable 2x)

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_probe/tier_info sh examples/z98/z9play/tests/tier_info.sh
# == tier_info summary: 20 passed, 0 failed ==

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_probe/tier_setup sh examples/z98/z9play/tests/tier_setup.sh
# == tier_setup summary: 21 passed, 0 failed ==

ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_probe/tier_audio sh examples/z98/z9play/tests/tier_audio.sh
# == tier_audio summary: 27 passed, 0 failed ==
```

## Concerns

1. **Control-handler calling convention.** Z98 never attaches a calling
   convention to non-extern *definitions* (win9x-calling-convention design
   §3.1), so `onCtrl` is a cdecl Z98 function converted with an explicit
   `@ptrCast(pal.CtrlHandler, onCtrl)` at the `SetConsoleCtrlHandler`
   registration site. The DWORD-in/BOOL-out frame shape is compatible, but the
   i386 stack-cleanup convention is technically mismatched for the kernel's
   stdcall callback. Task 4 should exercise Ctrl-C under Wine on real
   hardware/Wine; if this proves unstable, the alternative is `signal(SIGINT,
   ...)` (CRT installs its own correctly-conventioned control handler) plus
   `atexit`.
2. **gcc warnings.** Every `extern "stdcall"` call is emitted through the Z98
   use-site cast and gcc warns `function called through a non-compatible type`
   (same class already accepted by T1's waveOut backend). The harness compiles
   and links; these are warnings, not errors.
3. `width`/`height` use the screen-buffer size (`dwSize`), per the task
   context's chosen mapping, not the visible window rectangle
   (`srWindow`). The player's status line uses the buffer dimensions on Win9x.
4. Output operations use `WriteConsoleA` only (plan mapping); with redirected
   stdout the Win32 calls fail harmlessly and nothing is written. The Win9x
   player path is console-oriented.
5. No real Win9x hardware run was possible here; compile/link, layout, and the
   non-blocking Wine probe are the Task 2 evidence. Runtime parity/restore is
   Task 4.

## Fix round 1 (Option 3 — operator ruling)

**Status:** DONE. Supersedes the Ctrl-C path of the Task 2 implementation above;
the other eight operations are unchanged.

**Authority:** plan `ded73c0c` Task 2 + `## Amendment 1 — T2 Ctrl-C mechanism
(operator ruling, 2026-10-18)` at the end of
`docs/superpowers/plans/2026-10-11-z9play-m6-win9x-plan.md`; T2 review Critical
on `d86b3441`.

### Before -> after

- **Before** (`d86b3441`): `enterRaw` cleared `ENABLE_LINE_INPUT` +
  `ENABLE_ECHO_INPUT` and KEPT `ENABLE_PROCESSED_INPUT`; Ctrl-C was produced by
  a `SetConsoleCtrlHandler` callback. Z98 cannot define a stdcall function, so
  `onCtrl` was a cdecl Z98 function explicitly cast to `PHANDLER_ROUTINE` — the
  review's Critical finding (i386 stack cleanup: `ret` vs `ret $4`). The
  impossibility should have been STOP-presented; it is now filed as defect D5.
- **After** (`example(z9play): M6 T2 fix — Ctrl-C via processed-input off
  (option 3)`): `enterRaw` clears `ENABLE_LINE_INPUT`, `ENABLE_ECHO_INPUT` **and
  `ENABLE_PROCESSED_INPUT`**. With processed input off, Ctrl-C is reported in
  the input buffer as a `KEY_EVENT` with `uChar == 0x03`; `readKey` maps that to
  `.sigint` as the primary, documented Ctrl-C path (the old defensive arm is now
  the main arm). `SetConsoleCtrlHandler`, `onCtrl`, the stdcall-handler type
  alias, the cast, `g_sigint` and `g_ctrl_installed` are gone; `atexit
  restoreAtExit` is the remaining crash backstop. Known limits (Amendment 1):
  Ctrl-Break still terminates via the default handler; console-close/shutdown
  restore is moot because the console is gone.
- PAL: the `SetConsoleCtrlHandler` extern and the `CtrlHandler`
  (PHANDLER_ROUTINE) alias were removed; every other extern/mirror is unchanged.
  `examples/torrent_example_defects.md` gained **D5**.

### Evidence (re-run post-fix)

`-osw` cross-build of the probe that calls all nine operations:

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/_probe_m6t2.zig /tmp/m6t2_fix_probe/cross \
    /tmp/m6t2_fix_probe/cross/z9play.exe
# dump: rc=0 error_brk=0 panic=0 c=7 link ok
# XRUNRC=0
file /tmp/m6t2_fix_probe/cross/z9play.exe
# PE32 executable (console) Intel 80386, for MS Windows, 17 sections
```

New `-osw --dump-c89` md5 (two runs, rc=0, identical):

```sh
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 examples/z98/z9play/_probe_m6t2.zig > /tmp/m6t2_fix_probe/dump1.c89   # RC1=0
timeout 300 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 examples/z98/z9play/_probe_m6t2.zig > /tmp/m6t2_fix_probe/dump2.c89   # RC2=0
md5sum /tmp/m6t2_fix_probe/dump1.c89 /tmp/m6t2_fix_probe/dump2.c89
# 81c052098c89218b96da2ea908f77310  dump1.c89
# 81c052098c89218b96da2ea908f77310  dump2.c89
```

(For reference, the pre-fix `d86b3441` probe md5 was
`224b09a61deec5d5ab479ab9485b3ebb`.)

Grep-clean in the emitted C and in the sources:

```sh
grep -Rn "SetConsoleCtrlHandler\|PHANDLER_ROUTINE\|onCtrl\|CtrlHandler\|g_sigint\|g_ctrl_installed" /tmp/m6t2_fix_probe/cross/dump
# (no output; GREP_RC=1)
grep -n "SetConsoleCtrlHandler\|PHANDLER_ROUTINE\|onCtrl\|CtrlHandler\|g_sigint\|g_ctrl_installed" \
    examples/z98/z9play/platform/console_win9x.zig examples/z98/z9play/platform/console_win9x_pal.zig
# (no output; GREP_RC=1)
```

The emitted `enterRaw` mask is the requested three-bit clear:

```sh
grep -n "zT_26 = mode" /tmp/m6t2_fix_probe/cross/dump/console_win9x_383D9AF4.c
# zT_26 = mode & (unsigned int)(~(unsigned int)((unsigned int)(6) | (unsigned int)(1)));
```

(`6` = `ENABLE_LINE_INPUT|ENABLE_ECHO_INPUT`, `1` = `ENABLE_PROCESSED_INPUT`.)

Layout unchanged (only the mode mask and the Ctrl-C mapping changed). The Z98
layout probe was rebuilt and re-run:

```sh
bash scripts/win32_cross/cross_build_run.sh /tmp/z9play_m6/zig1_5_clean \
    examples/z98/z9play/_probe_m6t2_layout.zig /tmp/m6t2_fix_probe/layoutz \
    /tmp/m6t2_fix_probe/layoutz/z9play.exe
# dump: rc=0 error_brk=0 panic=0 c=5 link ok
# XRUNRC=0
WINEDEBUG=-all timeout 60 wine /tmp/m6t2_fix_probe/layoutz/z9play.exe
# COORD size=4 x=0 y=2
# SMALL_RECT size=8 left=0 top=2 right=4 bottom=6
# CONSOLE_SCREEN_BUFFER_INFO size=22 dwSize=0 dwCursorPosition=4 wAttributes=8 srWindow=10 dwMaximumWindowSize=18
# CONSOLE_CURSOR_INFO size=8 dwSize=0 bVisible=4
# KEY_EVENT_RECORD size=16 bKeyDown=0 wRepeatCount=4 wVirtualKeyCode=6 wVirtualScanCode=8 uChar=10 dwControlKeyState=12
# INPUT_RECORD size=20 event_type=0 key=4
```

Identical to the round-1 mingw `offsetof`/`sizeof` table. D5 probe (scratch
`/tmp/m6t2_fix_probe/d5probe.zig`):

```sh
timeout 120 /tmp/z9play_m6/zig1_5_clean -osw --dump-c89 --output-dir /tmp/m6t2_fix_probe/d5out /tmp/m6t2_fix_probe/d5probe.zig
# RC=0
grep -Rn "onCtrl" /tmp/m6t2_fix_probe/d5out/*.c /tmp/m6t2_fix_probe/d5out/*.h
# /tmp/m6t2_fix_probe/d5out/d5probe_EB908F68.c:10:    zT_1 = ((zT_65668B00_FS_int_unsigned_int)onCtrl);
# (reference only: no definition, no prototype)
i686-w64-mingw32-gcc -std=c89 -m32 -Wall -Wno-long-long -Wno-pointer-sign \
    -I /tmp/m6t2_fix_probe/d5out -c /tmp/m6t2_fix_probe/d5out/d5probe_EB908F68.c \
    -o /tmp/m6t2_fix_probe/d5probe.o
# error: 'onCtrl' undeclared (first use in this function)
```

Linux tiers (all green, unchanged from round 1):

```sh
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_fix_probe/tier_console sh examples/z98/z9play/tests/tier_console.sh
# == tier_console summary: 11 passed, 0 failed ==
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_fix_probe/tier_cli sh examples/z98/z9play/tests/tier_cli.sh
# == tier_cli summary: 23 passed, 0 failed ==
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_fix_probe/tier_info sh examples/z98/z9play/tests/tier_info.sh
# == tier_info summary: 20 passed, 0 failed ==
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_fix_probe/tier_setup sh examples/z98/z9play/tests/tier_setup.sh
# == tier_setup summary: 21 passed, 0 failed ==
ZIG=/tmp/z9play_m6/zig1_5_clean OUT=/tmp/m6t2_fix_probe/tier_audio sh examples/z98/z9play/tests/tier_audio.sh
# == tier_audio summary: 27 passed, 0 failed ==
```

### Concerns (fix round)

1. `Ctrl-Break` is no longer intercepted; it terminates via the default handler
   (Amendment 1 known limitation). Ctrl-C is now a normal input record, so
   Task 4 should assert the `.sigint` path under a real console/Wine; this round
   proves compile/link/mapping only.
2. Console-close/shutdown mode restore is moot (the console is gone); `atexit`
   covers normal exits that skip the caller's `leaveRaw` (Task 3's exit paths
   still call it explicitly).
3. Defect D5 remains OPEN (minimal fix = reject extern-fn-with-body; full fix =
   stdcall definitions); the example-only Option 3 workaround is in place.

