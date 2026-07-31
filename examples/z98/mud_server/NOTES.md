# mud_server — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5fb57e70c2d637276ab0264c1401cd0d`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/mud_server/main.zig -o build/mud_server
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/mud_server/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c sf/src/include/net_runtime.c -o /tmp/x
```

## Expected Output
```
MUD server listening on port 4000
```
(then timeout)

## Notes
Multi-file: `main.zig` imports `std.zig` and `util.zig`. Needs `sf/src/include/net_runtime.c` in the link step.
