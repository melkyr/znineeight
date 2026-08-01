# quicksort — Z98 Example

**Status:** OK

**Entry file:** `quicksort.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `c317e8ef5cb137357605835d4f1150eb`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/quicksort/quicksort.zig -o build/quicksort
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/quicksort/quicksort.zig
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
Original: 3 1 4 1 5 9 2 6 5 3
Sorted (ascending): 1 1 2 3 3 4 5 5 6 9
Sorted (descending): 9 6 5 5 4 3 3 2 1 1
```

## Notes
Entry file is `quicksort.zig`, NOT `main.zig`.
