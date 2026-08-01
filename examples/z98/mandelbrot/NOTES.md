# mandelbrot — Z98 Example

**Status:** OK

**Entry file:** `mandelbrot.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `924141a542ecf3d5185d5d0f1980118d`

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
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include -c /tmp/out/*.c
gcc -m32 /tmp/out/*.o sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/out/prog
/tmp/out/prog
```

## Expected Output
```
(Mandelbrot set ASCII art)
```

## Notes
Entry file is `mandelbrot.zig`, NOT `main.zig`. Single file.
