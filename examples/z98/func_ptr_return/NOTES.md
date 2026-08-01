# func_ptr_return — Z98 Example

**Status:** OK

**Entry file:** `func_ptr_return.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `cf271327bed2a523b452640598ff5a24`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/func_ptr_return/func_ptr_return.zig -o build/func_ptr_return
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/func_ptr_return/func_ptr_return.zig
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
10 + 5 = 15
10 - 5 = 5
```

## Notes
Entry file is `func_ptr_return.zig`, NOT `main.zig`.
