# mandelbrot — Z98 Example

**Status:** OK

**Entry file:** `mandelbrot.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `32ceaf9cb1d22d8c95ed1dab21d425fa` [updated: 2026-08-08]

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/zig0/mandelbrot/mandelbrot.zig -o build/mandelbrot
```

### zig1 (dump C89)
```bash
mkdir -p /tmp/out
sf/build/out_release/zig1 --dump-c89 --output-dir /tmp/out examples/z98/mandelbrot/mandelbrot.zig
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
(Mandelbrot set ASCII art)
```

## Notes
Entry file is `mandelbrot.zig`, NOT `main.zig`. Single file.
[F4 2026-08-08: `__bootstrap_print` extern → `std.io.print` (via local `std.zig`/`std_io.zig`/`std_arena.zig` copies).]
