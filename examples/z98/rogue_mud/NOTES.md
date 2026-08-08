# rogue_mud — Z98 Example

## What it tests
Rogue-like dungeon crawler with a multi-module game engine (dungeon
generation via BSP, rooms, scenario/quests, pathfinding, combat, entities,
networking, UI). 20 modules total (`main.zig` + 14 `lib/*.zig` +
`ui.zig` + `std.zig`/`std_debug.zig` transitive).

**Entry file:** `main.zig`

**Status as of 2026-08-08:** BROKEN at LINK only — compiler emission is
clean; the gap is the missing platform/console runtime layer (D4,
out-of-scope).

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

## Status (measured 2026-08-08, sf/build/out_release/zig1)
- **dump rc=0** — all **20 modules** emit `.c`/`.h` files: main, sand, rng,
  scenario, point, entity, combat, tile, room, persistence, net, ui,
  array_list, bsp, pathfinding, priority_queue, plus 2 std + 2 std_debug
  (transitive) = 20.
- **gcc compile rc=0** — 0 errors, **5 warnings** (pointer-to-int
  conversions in BSP/Room generics, benign).
- **gcc LINK FAILS** — exactly **5 undefined references**, all platform
  console/detect stubs (BOTH single-module and multi-module recipes):
  `plat_is_windows`, `plat_console_gotoxy`, `plat_console_setcolor`,
  `plat_console_putchar`, `plat_console_clear`. These symbols are missing
  from ALL runtime files (`zig_runtime.c`/`zig_pal.c`/`net_runtime.c`) —
  tracked as **D4 (platform-stub gap, out-of-scope, feeds the future
  std-lib plan)**. Guarded by `repro/mi_matrix/plat_stubs_missing_xmod/`.
- **NO module-symbol gaps:** all module functions (generateDungeon,
  Room_centerX/Y, findPath, connectRooms, etc.) resolve and link — the
  module→`.c` emission is complete. (The task-brief's Step-5 draft claimed
  "~15 undefined references / module symbol gaps" — NOT reproduced on the
  current compiler; only the 5 plat_* stubs fail.)

## Classification
BROKEN-at-link (runtime-library gap, D4). Compiler emission correct.
Run with timeout (`timeout 10 /tmp/rm_dir/rm` — server-style application).
Once the platform-stub std-lib plan lands, links and runs.
