# Mandelbrot Set ASCII Art Generator

A self-contained Z98 example that computes and renders the Mandelbrot set as ASCII art in the console.

## Overview

This example demonstrates the following Z98 features:
- **Floating-point arithmetic**: Uses `f64` for complex number calculations.
- **Nested loops**: Iterates over a 2D grid to render pixels.
- **Fixed-size arrays**: Manages line buffers and character maps.
- **Built-in functions**: Uses `@intToFloat` and `@intCast` for type conversions.
- **C Interoperability**: Calls `__bootstrap_print` to output rendered lines.

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

### Linux

```sh
mkdir -p out
/path/to/zig1_5_clean -o out mandelbrot.zig
sh out/build_target.sh
./out/prog
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out mandelbrot.zig
cd out
build_owc_crt.bat
prog.exe
```

`build_owc_crt.bat` (OpenWatcom, static CRT) is the verified path;
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first);
`build_owc_nocrt.bat` / `build_target_nocrt.bat` are the no-CRT alternates; and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.

## Implementation Details

The program computes the escape time for each point $(cx, cy)$ in the complex plane using the iterative formula:
$z_{n+1} = z_n^2 + c$
where $z_0 = 0$.

The iteration count is then mapped to a character from a predefined set to represent density/depth in the ASCII output.
