# prime — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `95a6b1d545f9632e8846e8cc73cd8e38` [updated: 2026-08-08]

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
cd /tmp/out
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I /workspace/znineeight/sf/src/include -c *.c
gcc -m32 *.o /workspace/znineeight/sf/src/include/zig_runtime.c /workspace/znineeight/sf/src/include/zig_pal.c -o prog
/tmp/out/prog
```

## Expected Output
```
2357
```

## Notes
Primes output.
[F4 2026-08-08: `std_debug.zig` migrated from `__bootstrap_print*` externs to `std.io` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
