# Z98 MUD Server Example

This is a minimal telnet MUD (Multi-User Dungeon) server implemented in the Z98 subset of Zig. It demonstrates the use of the new Platform Abstraction Layer (PAL) socket API.

## Features

- Multiple simultaneous connections using `select()`.
- Basic room-based movement (north, south, east, west).
- Look command for room descriptions.
- Simple line-based command processing.

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

The emitted build scripts link the Winsock library (`wsock32`) automatically
for the server's `std_net` imports; no manual `-lwsock32` is needed when you
use them.

Sources: `main.zig` (entry) imports `util.zig`; pass only `main.zig` — the
compiler resolves the rest.

## Running

1. Start the server:
   ```bash
   ./out/prog
   ```
   The server will listen on port 4000.

2. Connect via telnet from one or more terminals:
   ```bash
   telnet localhost 4000
   ```

## Z98 Subset Notes

- **Manual Socket Init**: Unlike modern Zig, you must explicitly call `plat_socket_init()` and `plat_socket_cleanup()`.
- **Minimal Stdlib**: This example uses a local `util.zig` for basic string operations as the Z98 standard library is extremely minimal.
- **Milestone 11 Features**: Uses tagged unions for commands, braceless control flow normalization, and array-to-slice coercions.
