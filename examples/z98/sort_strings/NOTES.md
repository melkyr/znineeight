# sort_strings — Z98 Example

**Status:** OK

**Entry file:** `sort_strings.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `774222f59861d890b3217439d4e64b1a`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/sort_strings/sort_strings.zig -o build/sort_strings
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/sort_strings/sort_strings.zig
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
Original: banana apple cherry date
Sorted strings: apple banana cherry date
```

## Notes
Entry file is `sort_strings.zig`, NOT `main.zig`.
