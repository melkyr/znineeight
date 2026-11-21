# days_in_month — Z98 Example

**Status:** OK

**Entry file:** `main.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `47847b359c3fa3cc241008111d3dfc3b` [updated: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/days_in_month/main.zig -o build/days_in_month
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/days_in_month/main.zig
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
(Calendar output, month names show null bytes — display corruption)
```

## Notes
Cosmetic: month name null bytes cause display corruption in calendar output.
[F4 2026-08-08: `std_debug.zig` extern `print` → `std.io.print` wrapper (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies). Runtime output byte-identical to pre-F4.]
