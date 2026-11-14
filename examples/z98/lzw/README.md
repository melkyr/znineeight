# LZW Compressor/Decompressor Demo

This example implements the Lempel‑Ziv‑Welch (LZW) compression algorithm in the Z98 Zig subset. It demonstrates several advanced features of the Z98 compiler, including multi-module support, error handling with error unions, and resource management with `defer` and `errdefer`.

## Features Demonstrated

- **Multi-Module Support**: The project is split into `dict.zig`, `io.zig`, `compress.zig`, `decompress.zig`, and `main.zig`, showcasing the separate compilation model.
- **Error Handling**: Uses `error` sets and `!T` error unions to handle dictionary overflow and I/O issues.
- **Defer/Errdefer**: Demonstrates the use of `defer` for completion messages and could be extended for resource cleanup.
- **Arrays and Slices**: Uses fixed-size arrays for the dictionary and demonstrates slice-like patterns.
- **Extern C Interop**: Interacts with the C standard library via `getchar` and `putchar`.

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

Sources: `main.zig` (entry) imports `dict.zig`, `io.zig`, `compress.zig`, and
`decompress.zig`; pass only `main.zig` — the compiler resolves the rest.

## Running the Example

### Compression
Run the program and select 'c':
```bash
$ ./out/prog
LZW Compressor/Decompressor Demo
Select mode: [c]ompress, [d]ecompress: c
Enter text to compress (end with EOF/Ctrl-D):
TOBEORNOTTOBEORTOBEORNOT
84 79 66 69 79 82 78 79 84 256 258 260 265 259 261 263
LZW Operation Finished.
```

### Decompression
Run the program and select 'd':
```bash
$ ./out/prog
LZW Compressor/Decompressor Demo
Select mode: [c]ompress, [d]ecompress: d
Enter space-separated codes to decompress (end with EOF/Ctrl-D):
84 79 66 69 79 82 78 79 84 256 258 260 265 259 261 263
TOBEORNOTTOBEORTOBEORNOT
LZW Operation Finished.
```

## Implementation Details

The dictionary uses a simple linear search for finding entries, which is efficient enough for this 4096-entry demo. The decompression uses recursion to expand the codes back into their original character sequences.
