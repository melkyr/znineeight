# Networking Demos

Two standalone programs live here, each with its own `main.zig`:

- `tls_demo/` — HTTPS fetch over `std_net` + `std_tls` (TLS 1.2/1.3).
- `wireguard_demo/` — a userspace TCP/IP client over a real WireGuard tunnel.

See `tls_demo/README.md` and `wireguard_demo/README.md` for the program
details and their individual test tiers. The build recipe below is the same
for both: only the entry path and output name change.

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
/path/to/zig1_5_clean -o out tls_demo/main.zig
sh out/build_target.sh
./out/prog

# The WireGuard demo:
mkdir -p out_wg
/path/to/zig1_5_clean -o out_wg wireguard_demo/main.zig
sh out_wg/build_target.sh
./out_wg/prog
```

Both programs take their arguments at runtime (see their READMEs); with no
arguments `tls_demo` fetches `https://www.google.com/` and `wireguard_demo`
reads `wg.conf` from the current directory.

### Windows 9x / NT

Run this from the example directory in a Command Prompt. `-osw` selects the
Windows target and emits the batch scripts.

```bat
mkdir out
z1.exe -I lib -osw -o out tls_demo/main.zig
cd out
build_owc_crt.bat
prog.exe

rem The WireGuard demo:
cd ..
mkdir out_wg
z1.exe -I lib -osw -o out_wg wireguard_demo/main.zig
cd out_wg
build_owc_crt.bat
prog.exe
```

`build_owc_crt.bat` (OpenWatcom, static CRT) is the verified path;
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first);
`build_owc_nocrt.bat` / `build_target_nocrt.bat` are the no-CRT alternates; and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.

Both programs are multi-file: `tls_demo/main.zig` imports the TLS/HTTP demo
modules and the std library; `wireguard_demo/main.zig` imports the WireGuard
and userspace-TCP/IP demos plus the std library. Pass only the entry file — the
compiler resolves the imports.
