# Hello World Example

This is a modular "Hello World" example for the Z98 bootstrap compiler.
It demonstrates multi-module compilation, cross-module function calls, and runtime integration.

## Files
- `main.zig`: Entry point.
- `greetings.zig`: Helper module.
- `std.zig`: Minimal standard library mock.
- `std_debug.zig`: Debug utilities.

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

Sources: `main.zig` (entry) imports `greetings.zig`; pass only `main.zig` — the
compiler resolves the rest.

**Expected Output:**
```
Hello, world!
```

## Technical Notes
- String literals are automatically handled as `*const u8` (single-item pointers) by the bootstrap compiler for simplicity.
- The `__bootstrap_print` runtime helper is used for low-level output.
