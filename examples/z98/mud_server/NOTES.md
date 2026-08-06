# mud_server — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `bf5d3636`

**MD5 (`--dump-c89`):** `4644ad1349c55af80fa1a18fe0e17989` [updated: 2026-08-06]
(Re-baselined 2026-08-03/2026-08-04 per AMENDMENT 9-11 / F-5 AMENDMENT B; previous `5fb57e70…` stale.)

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
