# Conway's Game of Life (Z98 Example)

This example implements a console-based version of Conway's Game of Life using the Z98 "Zig subset" language.

## Features Demonstrated
- **Tagged Unions**: Used for the `Cell` state (`Dead`, `Alive`).
- **Switch Captures**: Used to inspect cell states.
- **Braceless Control Flow**: Single-statement `if` and `while` blocks.
- **Enhanced Print Lowering**: Support for `{c}` (character) and `{s}` (string) format specifiers in `std.debug.print`.
- **Win32/C Interop**: Calls `system("cls")` and `Sleep(ms)` via `extern "c"`.

## Status
**Working**. The example now compiles and runs in 32-bit mode. The compiler successfully lifts aggregate initializers into temporary variables for C89 compatibility.

A known bug in the `C89Emitter` regarding pointers to fixed-size arrays requires using slices (`[]T`) instead of pointers to arrays (`*[N]T`) for function arguments.

## Linux Support
A Linux-compatible version is provided in `main_lin.zig`. It uses `system("clear")` and `usleep`.

## Compilation
To compile and run on Linux:
```bash
../../zig0 main_lin.zig -o out_lin/
cd out_lin/
gcc -m32 -std=c89 -I. -I../../../src/include main_lin.c builtin.c std.c std_debug.c zig_runtime.c -o app
./app
```

On Windows, use `main.zig` and the provided `build_target.bat`.
