# mandelbrot — Z98 Example

**Status:** OK

**Entry file:** `mandelbrot.zig`

**Working commit:** `9d029c2e`

**MD5 (`--dump-c89`):** `924141a542ecf3d5185d5d0f1980118d`

## Build Recipes

### zig0
```bash
./sf/build/zig0 examples/z98/mandelbrot/mandelbrot.zig -o build/mandelbrot
```

### zig1 (dump C89)
```bash
sf/build/out_release/zig1 --dump-c89 examples/z98/mandelbrot/mandelbrot.zig
```

### GCC compile + link
```bash
gcc -m32 -std=c89 -Wno-long-long -Wno-pointer-sign -I sf/src/include /tmp/x.c sf/src/include/zig_runtime.c sf/src/include/zig_pal.c -o /tmp/x
```

## Expected Output
```
(Mandelbrot set ASCII art)
```

## Notes
Entry file is `mandelbrot.zig`, NOT `main.zig`. Single file.
