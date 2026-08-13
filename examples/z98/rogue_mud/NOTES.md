# rogue_mud — Z98 Example

## What it tests
Rogue-like dungeon crawler with a multi-module game engine (dungeon
generation via BSP, rooms, scenario/quests, pathfinding, combat, entities,
networking, UI). 22 modules total (`main.zig` + 14 `lib/*.zig` +
`ui.zig` + mud_server `std.zig`/`std_io.zig`/`std_debug.zig` transitive).

**Entry file:** `main.zig`

**Status as of 2026-08-13 (F5 — console builtins migration):** **FIXED — links + runs**
on the standard recipe (both single- and multi-module). The 5 `plat_*` console
externs were replaced with the F2 console builtins (`@isWindows` + `@consoleClear`/
`@consoleGotoxy`/`@consoleSetColor`/`@putChar`) — the D4 gap is closed.

## Build Recipes

### Single-module recipe (zig1, dump C89 to one file)
```bash
sf/build/out_release/zig1 --dump-c89 main.zig > /tmp/rm.c
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include \
    /tmp/rm.c /workspace/znineeight/sf/src/include/zig_runtime.c \
    /workspace/znineeight/sf/src/include/zig_pal.c \
    /workspace/znineeight/sf/src/include/net_runtime.c -o /tmp/rm
```

### Multi-module recipe (zig1, per-module C89 emission)
```bash
mkdir -p /tmp/rm_dir
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/rm_dir main.zig
cd /tmp/rm_dir
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c \
    /workspace/znineeight/sf/src/include/zig_pal.c \
    /workspace/znineeight/sf/src/include/net_runtime.c -o rm
```

## Status (measured 2026-08-13, sf/build/out_release/zig1)
- **dump rc=0** — all **22 modules** emit `.c`/`.h` files: main, sand, rng,
  scenario, point, entity, combat, tile, room, persistence, net, ui,
  array_list, bsp, pathfinding, priority_queue, plus mud_server `std` +
  `std_io` + `std_debug` (transitive) = 22.
- **gcc compile rc=0** — 0 errors, **5 warnings** (pointer-to-int
  conversions in BSP/Room generics, benign).
- **gcc LINK rc=0** (was rc=1) — the **5 platform console/detect stubs are
  GONE**: `plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
  `plat_console_putchar`, `plat_console_clear` were replaced by the F2 console
  builtins (BOTH single-module and multi-module recipes). **[F5 2026-08-13]**
- **run rc=0** — boots ("Welcome to Rogue MUD!", generates dungeon, renders
  via ANSI escapes on POSIX: `@consoleGotoxy`/`@consoleSetColor`/`@putChar`
  emit `\x1b[<y+1>;<x+1>H` + `\x1b[<fg>;<bg>m` + char), accepts WASD/Q input,
  exits cleanly on `q`. `@isWindows()` folds to 0 (comptime) → POSIX branch
  taken.
- **NO module-symbol gaps:** all module functions (generateDungeon,
  Room_centerX/Y, findPath, connectRooms, etc.) resolve and link — the
  module→`.c` emission is complete.
- **[F4 2026-08-08]** I/O migration: `__bootstrap_print`/`__bootstrap_print_int`/
  `__bootstrap_write`/`__bootstrap_print_bytes` externs → `std.io.print`/
  `std.io.printInt`/`std.io.write` (mud_server `std.zig`/`std_io.zig` copies,
  imported as `../mud_server/std.zig` — existing pattern). Console (`plat_*`)
  migration was F5's job — done 2026-08-13. Zero `__bootstrap_*` refs remain.
  Module count 20 → 22 (mud_server `std_io` now transitively included).

## Deferred to std-lib (D4, operator ruling) — CLOSED by F5
Prior (F4) status: all 22 modules emit, gcc compile rc=0, link failed on exactly
the 5 `plat_*` stubs — `plat_is_windows`, `plat_console_gotoxy`,
`plat_console_setcolor`, `plat_console_putchar`, `plat_console_clear` (BOTH
single-module and multi-module recipes). All 5 were missing from ALL runtime
files (`zig_runtime.c`/`zig_pal.c`/`net_runtime.c`) and are rogue_mud-only;
zig0 failed identically → the **D4 runtime-library gap, NOT a compiler
defect**. **[F5 2026-08-13: CLOSED via the F2 console builtins** — ui.zig's 5
externs replaced with `@isWindows()`/`@consoleClear()`/`@consoleGotoxy()`/
`@consoleSetColor()`/`@putChar()`; main.zig's `ui_mod.plat_is_windows()` → the
comptime `@isWindows()`. Guarded by `repro/mi_matrix/plat_stubs_missing_xmod/`
(now links + runs). rogue_mud links + runs on the standard recipe.]**

## Classification
FIXED — standard recipe (both single- and multi-module) dump rc=0, gcc rc=0,
link rc=0, run rc=0 (server boots; ANSI console output verified). Re-verified
2026-08-13 at F5.
