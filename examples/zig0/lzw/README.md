# LZW Compressor/Decompressor Demo

This example implements the Lempel‑Ziv‑Welch (LZW) compression algorithm in the Z98 Zig subset. It demonstrates several advanced features of the Z98 compiler, including multi-module support, error handling with error unions, and resource management with `defer` and `errdefer`.

## Features Demonstrated

- **Multi-Module Support**: The project is split into `dict.zig`, `io.zig`, `compress.zig`, `decompress.zig`, and `main.zig`, showcasing the separate compilation model.
- **Error Handling**: Uses `error` sets and `!T` error unions to handle dictionary overflow and I/O issues.
- **Defer/Errdefer**: Demonstrates the use of `defer` for completion messages and could be extended for resource cleanup.
- **Arrays and Slices**: Uses fixed-size arrays for the dictionary and demonstrates slice-like patterns.
- **Extern C Interop**: Interacts with the C standard library via `getchar` and `putchar`.

## Building the Example

Ensure you have the `zig0` compiler built in the root directory. Then, from the root:

```bash
./zig0 examples/lzw/main.zig -o examples/lzw/
cd examples/lzw/
./build_target.sh
```

This will generate an `lzw` executable.

## Running the Example

### Compression
Run the program and select 'c':
```bash
$ ./main
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
$ ./main
LZW Compressor/Decompressor Demo
Select mode: [c]ompress, [d]ecompress: d
Enter space-separated codes to decompress (end with EOF/Ctrl-D):
84 79 66 69 79 82 78 79 84 256 258 260 265 259 261 263
TOBEORNOTTOBEORTOBEORNOT
LZW Operation Finished.
```

## Implementation Details

The dictionary uses a simple linear search for finding entries, which is efficient enough for this 4096-entry demo. The decompression uses recursion to expand the codes back into their original character sequences.
