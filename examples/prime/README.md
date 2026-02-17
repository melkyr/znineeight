# Prime Number Example

This example demonstrates algorithmic features of the RetroZig bootstrap compiler, including:
- Loops (`while`)
- Conditionals (`if`)
- Arithmetic operators (modulo `%`, multiplication `*`)
- Numeric casts (`@intCast`)
- Multi-module organization

## Files
- `main.zig`: Entry point with `isPrime` logic.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities for printing integers.

## Building and Running

1. Compile the Zig source to C89 using the RetroZig compiler:
   ```bash
   # Assuming zig0 is in the root directory
   ../../zig0 main.zig std.zig std_debug.zig --output output/
   ```

2. Compile the generated C code with a C toolchain (e.g., GCC):
   ```bash
   # You'll need to link all generated modules and the runtime
   cd output/
   gcc -std=c89 -pedantic -Wno-pointer-sign -o prime main.c std.c std_debug.c ../../../src/runtime/zig_runtime.c -I../../../src/include -I.
   ```

3. Run the executable:
   ```bash
   ./prime
   ```

Expected output: `2357` (or `2`, `3`, `5`, `7` on separate lines depending on `__bootstrap_print_int` implementation).
