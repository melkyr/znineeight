# fibonacci — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `6eae64764ee46dd90e644e3d717d02e6` [updated: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/fibonacci/main.zig -o build/fibonacci
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/fibonacci/main.zig
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
55
```

## Notes
10th Fibonacci number.
[F4 2026-08-08: `std_debug.zig` migrated from `__bootstrap_print*` externs to `std.io` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
