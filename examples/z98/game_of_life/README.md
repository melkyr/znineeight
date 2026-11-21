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

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

This example has two separate roots: `main_lin.zig` for Linux and `main.zig`
for Windows (they call different console APIs).

### Linux

```sh
mkdir -p out
/path/to/zig1_5_clean -o out main_lin.zig
sh out/build_target.sh
./out/prog
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out main.zig
cd out
build_owc_crt.bat
prog.exe
```

`build_owc_crt.bat` (OpenWatcom, static CRT) is the verified path;
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first);
`build_owc_nocrt.bat` / `build_target_nocrt.bat` are the no-CRT alternates; and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.
