# Hello World Example

This is a modular "Hello World" example for the RetroZig bootstrap compiler.
It demonstrates multi-module compilation, cross-module function calls, and runtime integration.

## Files
- `main.zig`: Entry point.
- `greetings.zig`: Helper module.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities.

## Building and Running

1. Compile the Zig source to C89 using the RetroZig compiler:
   ```
   ./zig0 main.zig --output output/
   ```

2. Compile the generated C code with a C toolchain:
   ```
   gcc -std=c89 -pedantic -Wno-pointer-sign -o hello output/main.c src/runtime/zig_runtime.c -Isrc/include -Ioutput
   ```

3. Run the executable:
   ```
   ./hello
   ```
