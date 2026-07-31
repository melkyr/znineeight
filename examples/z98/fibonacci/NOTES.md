# fibonacci — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `31baff99d2d7de89b1dfa811d0966df3`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/fibonacci/main.zig -o build/fibonacci
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/fibonacci/main.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
55
```

## Notes
10th Fibonacci number.
