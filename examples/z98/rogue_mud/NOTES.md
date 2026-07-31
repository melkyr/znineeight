# rogue_mud — Z98 Example

**Status:** BROKEN

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** N/A (dump fails)

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/rogue_mud/main.zig -o build/rogue_mud
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/rogue_mud/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
N/A — does not build
```

## Notes
Multi-file: 14+ modules. Dump rc=2, syntax errors. Uses `catch |err| { ...; s }` block-expression pattern unsupported by Z98 parser. Also uses `fn(...)` ptr types. Syntax incompatibilities with Z98 parser.
