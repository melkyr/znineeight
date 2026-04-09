# Conway's Game of Life (Z98 Example)

This example implements a console-based version of Conway's Game of Life using the Z98 "Zig subset" language.

## Features Demonstrated
- **Tagged Unions**: Used for the `Cell` state (`Dead`, `Alive`).
- **Switch Captures**: Used to inspect cell states.
- **Braceless Control Flow**: Single-statement `if` and `while` blocks.
- **Enhanced Print Lowering**: Support for `{c}` (character) and `{s}` (string) format specifiers in `std.debug.print`.
- **Win32/C Interop**: Calls `system("cls")` and `Sleep(ms)` via `extern "c"`.

## Status
**Experimental / Blocked**. While the code passes the Z98 type-checker, the generated C code currently requires C99 support for aggregate initializers in function calls (e.g., `set(..., Cell{ .Alive = {} })`).

See `missing_features_gol.md` for details on current limitations and workarounds.

## Compilation (Future)
Once the C89 emitter issues are resolved, it can be compiled using:
```bash
../../zig0 main.zig -o out/
cd out && bash build_target.sh
./app
```
