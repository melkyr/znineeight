# Fibonacci Example

This example demonstrates recursion in the RetroZig bootstrap compiler.

## Files
- `main.zig`: Entry point with recursive `fib` function.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities for printing integers.

## Building and Running

1. Compile the Zig source to C89 using the RetroZig compiler:
   ```bash
   ../../zig0 main.zig std.zig std_debug.zig --output output/
   ```

2. Compile the generated C code with a C toolchain:
   ```bash
   cd output/
   gcc -std=c89 -pedantic -Wno-pointer-sign -o fibonacci main.c std.c std_debug.c ../../../src/runtime/zig_runtime.c -I../../../src/include -I.
   ```

3. Run the executable:
   ```bash
   ./fibonacci
   ```

Expected output: `55`
