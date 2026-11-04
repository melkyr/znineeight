# z9zstddecomp

A single-shot zstd frame decompressor CLI for Z98. It reads a complete `.zst`
stream, decodes it with `std_zstd`, and writes the plain bytes. Standard frames,
skippable frames, content checksums, and RFC 8878 dictionaries are supported.

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
./out/prog <in.zst> <out>
```

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw nt -o out main.zig
cd out
build_mingw_crt.bat
prog.exe <in.zst> <out>
```

This app does file I/O through `std_file`, so the Windows smoke path is the
**CRT** build (`-osw nt`, which sets `ZIG_WIN_NT`; `build_mingw_crt.bat` /
`build_target_crt.bat` / `build_owc_crt.bat` do not use `-nostdlib`). The
default 9x no-CRT profile (`-osw`, `-nostdlib`, no `msvcrt.dll`) is not the
supported path for this example. The MinGW CRT build imports `msvcrt.dll`; the
`check_win9x_imports.sh ... nt` gate is the relevant import gate. The
no-msvcrt `9x` gate is for operator-run static-CRT OWC/MSVC builds.

## Usage

```sh
z9zstddecomp <in.zst> <out> [--dict <file>] [--max-window-log <n>] [--max-output <n>]
z9zstddecomp -h
```

- `--dict <file>` loads a dictionary. A magic dictionary (prefix
  `0xEC30A437`, with a dictionary id and entropy tables) and a raw-content
  dictionary are both accepted. Use it whenever the producer used
  `zstd -D <dict>` (magic) or a raw dictionary; frames carrying a nonzero
  dictionary id are rejected without the matching magic dictionary.
- `--max-window-log <n>` caps the accepted frame window at `2^n` bytes.
  Default: **27** (the zstd maximum). A smaller value rejects larger-window
  frames with exit code 3 (`WindowTooBig`).
- `--max-output <n>` caps decoded output at `n` bytes. Default: **16 MiB**.
  When the frame declares an exact content size, that size is used directly;
  otherwise the output buffer grows by doubling up to the cap. Exceeding the
  cap exits 5.

## Exit codes

| code | meaning |
|---|---|
| 0 | success |
| 1 | usage error (missing/extra operands, unknown flag, bad number) |
| 2 | input open/read error (including a missing/unreadable `--dict` file) |
| 3 | decode error (`Corrupt` or `WindowTooBig`) |
| 4 | output write error (for example, the output path is a directory) |
| 5 | output exceeds `--max-output` |

## Fixtures and tier

`tests/fixtures/*.zst` are committed, deterministic outputs from
`tests/gen_fixtures.c` (dev-time, links libzstd 1.5.4). They cover plain text,
4-stream Huffman literals, an RLE block, a skippable frame plus payload, a
content checksum, a magic dictionary, a raw-content dictionary, a dictionary
mismatch, and a truncated frame.

`tests/tier_zstddecomp.sh` builds this example with a seed-built compiler
(`ZIG=/tmp/p3_t5_base/zig1_5_clean`), checks every fixture's exit code and
output md5 on Linux, exercises the exit-code contract, then emits with
`-osw nt`, builds the MinGW CRT executable, runs the `nt` import gate, and runs
the plain and magic-dictionary cases under Wine.
