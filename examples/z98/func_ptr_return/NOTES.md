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
sf/build/out_release/zig1 --dump-c89 examples/z98/func_ptr_return/func_ptr_return.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
10 + 5 = 15
10 - 5 = 5
```

## Notes
Entry file is `func_ptr_return.zig`, NOT `main.zig`.
