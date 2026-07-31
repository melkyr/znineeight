# lzw — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5e4390561d5201b09a8d6695bd4cfb6c`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lzw/main.zig -o build/lzw
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/lzw/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
Interactive: compress BANANA → 66 65 78 257 65 10
```

## Notes
Multi-file: `main.zig` imports additional modules. Interactive program.
