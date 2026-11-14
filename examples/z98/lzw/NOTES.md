# lzw — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `5e4390561d5201b09a8d6695bd4cfb6c` [verified: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/lzw/main.zig -o build/lzw
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/lzw/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
Interactive: compress BANANA → 66 65 78 257 65 10
```

## Notes
Multi-file: `main.zig` imports additional modules. Interactive program.
[F4 2026-08-08: NO `__bootstrap_*` references — no migration needed (source unchanged).]
