# prime — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `97eea16a2e45dfa0f332e1a42472d063`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/prime/main.zig -o build/prime
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/prime/main.zig
# produces: /tmp/out/*.c + /tmp/out/*.h + /tmp/out/zig_special_types.h
```

### GCC compile + link + run
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c /tmp/out/*.c
gcc -m32 /tmp/out/*.o sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/out/prog
/tmp/out/prog
```

## Expected Output
```
2357
```

## Notes
Primes output.
