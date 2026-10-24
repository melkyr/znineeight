# z9dbg — Z98 source-level debugger

| | |
|---|---|
| **Source** | `examples/z98/z9dbg/` |
| **Input** | a debuggee plus the opt-in map from `zig1 -d` |
| **Backends** | Linux ptrace (i386); Win32 Debug API (Win9x) |
| **Debug info** | DWARF 2/3/4 in ELF; DWARF-in-PE; embedded COFF (`/Z7`) |

## Overview

`z9dbg` is a small, dependency-free debugger for Z98 programs. It resolves
source lines and functions without `#line`, using the compiler's opt-in map
sidecars (`sf/docs/std_lib/debug_map.md`) plus the debuggee's own DWARF or
embedded COFF. The upper layer is portable; only the process-control backend is
platform specific.

It is an **opt-in compiler-development tool**. Normal builds are unchanged and
should be debugged with `gdb` on the generated C as before.

## Quick start (Linux)

```sh
# 1. Compiler from the seed, with the standard library beside it
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9
# 2. Debuggee: emit the map, then rebuild the C with DWARF
/tmp/z9/zig1_5_clean -d --output-dir /tmp/demo examples/z98/z9dbg/tests/fixtures/live/main.zig
( cd /tmp/demo && gcc -m32 -std=c89 -O0 -g -gdwarf-2 -fno-omit-frame-pointer \
    -I /workspace/znineeight/sf/src/include -c *.c && gcc -m32 *.o -o prog )
# 3. Debugger
/tmp/z9/zig1_5_clean -o /tmp/z9d examples/z98/z9dbg/main.zig
( cd /tmp/z9d && sh build_target.sh linux prog )
/tmp/z9d/prog /tmp/demo/prog
```

Commands: `break <file>:<line>`, `continue`, `step`, `backtrace`,
`dump variables [path]`, `quit`. There is no `run`; the session stops at the
entry source line before the first prompt. `break` accepts a basename or a
path suffix; a line with no executable code snaps to the next mapped line
unless that would cross the next function declaration.

## Win9x / Win98

Build the debugger and debuggee as PE32 with the mingw no-CRT profile:

```sh
ZIG=/tmp/z9/zig1_5_clean
$ZIG -osw -o /tmp/z9w examples/z98/z9dbg/main.zig
sh /tmp/z9w/build_target.sh mingw /tmp/z9w/z9dbg.exe
$ZIG -q -d -osw --output-dir /tmp/z9w/demo <entry.zig>
( cd /tmp/z9w/demo && i686-w64-mingw32-gcc -m32 -std=c89 -O0 -g -gdwarf-2 \
    -DZIG_NO_CRT -I . -c *.c && i686-w64-mingw32-gcc -m32 -nostdlib \
    -Wl,-e,_mainCRTStartup *.o -o prog.exe -lgcc -lkernel32 )
wine /tmp/z9w/z9dbg.exe /tmp/z9w/demo/prog.exe
```

The backend uses only `CreateProcessA`, `WaitForDebugEvent`,
`ContinueDebugEvent`, `GetThreadContext`, `SetThreadContext`,
`ReadProcessMemory`, `WriteProcessMemory`, and `FlushInstructionCache`, all on
the 9x KERNEL32 whitelist (`scripts/win32_cross/check_win9x_imports.sh`).
`quit` is **terminate-on-quit** on Win9x: breakpoint bytes are restored and the
debuggee is terminated (there is no detach/reattach API in the 9x profile).

## Debug-info readers

| Toolchain | Build recipe | Reader |
|:--|:--|:--|
| mingw | `-g -gdwarf-2` | PE container → `.debug_line` + COFF symtab |
| OpenWatcom | `wcc386 -d2` (default DWARF) + `wlink debug all` | PE container → DWARF |
| MSVC 6 | `cl /Z7` + `link /DEBUG /DEBUGTYPE:COFF` | embedded COFF symbol/line records |

All three produce the same `DebugInfo` (line rows + function entries). PE rows
are link-time VAs; the session applies the runtime bias from
`CREATE_PROCESS_DEBUG_INFO.lpBaseOfImage`.

### Out of v1

- PDB and CodeView (`/DEBUGTYPE:CV`, `-dhc`).
- DWARF 5 and DWARF64.
- 64-bit debuggees (the debuggee ABI is i386).

Those degrade to `break: no debug info` plus function-entry breakpoints from the
symbol table.

## Windows terminal/stdout note (D8)

The compiler's builtin output goes through C stdio, while `std.fmt`/`std.io`
use the PAL. On Win9x the PAL path is the unbuffered no-CRT `fwrite` shim, and
`z9dbg` deliberately does **not** call `fflush` on Windows (the shim has none;
the `flushOut()` call is compile-time guarded). This preserves already-written
output ordering without changing the compiler or runtime sources.

## Limits

- Frame-pointer unwinding only; build with `-fno-omit-frame-pointer` or accept
  the `backtrace: frame chain unreliable` warning.
- `dump variables` is a snapshot (registers, current frame, mapped globals);
  there is no expression evaluator.
- Single debuggee thread; extra thread create/exit events are continued
  internally.
- The map and the executable must sit next to each other; the map is matched by
  executable stem or a single unambiguous candidate.
