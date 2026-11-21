# Mandelbrot Set ASCII Art Generator

A self-contained Z98 example that computes and renders the Mandelbrot set as ASCII art in the console.

## Overview

This example demonstrates the following Z98 features:
- **Floating-point arithmetic**: Uses `f64` for complex number calculations.
- **Nested loops**: Iterates over a 2D grid to render pixels.
- **Fixed-size arrays**: Manages line buffers and character maps.
- **Built-in functions**: Uses `@intToFloat` and `@intCast` for type conversions.
- **C Interoperability**: Calls `__bootstrap_print` to output rendered lines.

## Building and Running

To compile the example to C89:

```bash
../../zig0 mandelbrot.zig -o output/
```

To build the native executable using the generated scripts:

```bash
cd output
./build_target.sh  # On Linux/Unix
# OR
build_target.bat   # On Windows
```

Then run the resulting executable:

```bash
./mandelbrot
```

## Implementation Details

The program computes the escape time for each point $(cx, cy)$ in the complex plane using the iterative formula:
$z_{n+1} = z_n^2 + c$
where $z_0 = 0$.

The iteration count is then mapped to a character from a predefined set to represent density/depth in the ASCII output.
