# Hello World Example

This is a modular "Hello World" example for the RetroZig bootstrap compiler.
It demonstrates multi-module compilation, cross-module function calls, and runtime integration.

## Files
- `main.zig`: Entry point.
- `greetings.zig`: Helper module.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities.

## Building and Running

### 1. Generate C89 Source
Use the bootstrap compiler to translate the Zig modules into C:
```bash
# Assuming zig0 is built in the root directory
../../zig0 main.zig greetings.zig std.zig std_debug.zig -o output/
```

### 2. Compile with a C89 Compiler
Compile the generated `.c` files along with the Zig runtime:
```bash
cd output/
# Copy runtime files if needed, or include them from their source
gcc -std=c89 -pedantic -Wno-pointer-sign -I. -o hello main.c greetings.c std.c std_debug.c ../../../src/runtime/zig_runtime.c -I../../../src/include
```

### 3. Run the Executable
```bash
./hello
```
**Expected Output:**
```
Hello, world!
```

## Technical Notes
- String literals are automatically handled as `*const u8` (single-item pointers) by the bootstrap compiler for simplicity.
- The `__bootstrap_print` runtime helper is used for low-level output.
