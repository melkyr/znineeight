# Prime Number Example

This example demonstrates algorithmic features of the Z98 bootstrap compiler, including:
- Loops (`while`)
- Conditionals (`if`)
- Arithmetic operators (modulo `%`, multiplication `*`)
- Numeric casts (`@intCast`)
- Multi-module organization

## Files
- `main.zig`: Entry point with `isPrime` logic.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities for printing integers.

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
/path/to/zig1_5_clean -o out main.zig
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

Expected output: `2357` (or `2`, `3`, `5`, `7` on separate lines depending on `__bootstrap_print_int` implementation).
