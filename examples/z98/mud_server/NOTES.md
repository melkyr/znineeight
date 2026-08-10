# mud_server — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `ecd4086925e81c872abd1c32e7ce929e` [updated: 2026-08-08]
(Re-baselined 2026-08-08 F4: `std_debug.zig` `__bootstrap_print` extern → `std.io.print` (local
`std.zig`/`std_io.zig` copies; the `net_runtime.c` externs in `main.zig` stay until F6). Runtime
output byte-identical to pre-F4 ("MUD server listening on port 4000", rc=124 timeout), per F-5
AMENDMENT B. Previous `4644ad13…` stale.)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/mud_server/main.zig -o build/mud_server
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/mud_server/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c /workspace/znineeight/sf/src/include/net_runtime.c -o prog
/tmp/out/prog
```

## Expected Output
```
MUD server listening on port 4000
```
(then timeout)

## Notes
Multi-file: `main.zig` imports `std.zig` and `util.zig`. Needs `sf/src/include/net_runtime.c` in the link step.
[F4 2026-08-08: `std_debug.zig` `__bootstrap_print` extern → `std.io.print` via local `std.zig`/`std_io.zig` copies. Local `std.zig` = `io` + `debug` (NO `arena` re-export — mud_server/rogue_mud don't use `std.arena`, and importing std_arena in the rogue_mud build exposes a pre-existing module-instance≥1 struct-type emission bug).]
