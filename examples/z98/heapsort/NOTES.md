# heapsort — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `a8c47d442a58292ea9120ee61a92a890` [updated: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/heapsort/main.zig -o build/heapsort
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/heapsort/main.zig
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
135671112131520
```

## Notes
Sorted array output.
[F4 2026-08-08: `std_debug.zig` migrated from `__bootstrap_print*` externs to `std.io` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
