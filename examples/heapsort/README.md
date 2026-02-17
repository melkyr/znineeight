# Heapsort Example

This example demonstrates in-place sorting of a fixed-size array using the Heapsort algorithm.

## Files
- `main.zig`: Entry point with `heapSort` and `heapify` logic.
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
   gcc -std=c89 -pedantic -Wno-pointer-sign -o heapsort main.c std.c std_debug.c ../../../src/runtime/zig_runtime.c -I../../../src/include -I.
   ```

3. Run the executable:
   ```bash
   ./heapsort
   ```

Expected output: `135671112131520` (or sorted numbers on separate lines).
