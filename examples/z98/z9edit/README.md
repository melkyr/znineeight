# z9edit

A single-file source editor for Z98, built on `std_gfx` with a Win9x window,
gap-buffer editing, an undo log, identifier matching, and a `--smoke` headless
mode used by its test tier (`tests/tier_edit.sh`).

## Building with zig1

The compiler is self-hosted. A seed build (`scripts/seed/build_from_seed.sh`)
puts `lib/` next to the `zig1` binary, and the compiler searches `<exe-dir>/lib`
automatically. When the binary lives elsewhere, pass the library directory with
`-I lib` (relative to the current directory). On Windows never use `-I /lib`:
that is the drive root, and the compiler reports `cannot find std`.

`-o <dir>` selects the output directory and is required; without it the
compiler emits nothing. Create the directory first.

### Linux

GUI examples are Windows-only: `std_gfx` provides a Win9x window with a
DirectDraw7 backend and a GDI fallback, so there is no Linux target build.

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
`build_target_crt.bat` is the MSVC 6 equivalent (run `VCVARS32.BAT` first); and
`build_mingw_crt.bat` is the MinGW fallback (needs `msvcrt.dll`). The output is
`out\prog.exe`.

The OpenWatcom **no-CRT** variant (`build_owc_nocrt.bat`) is **not supported
for GUI programs**: its link line sets `option nodefaultlibs` and omits
`user32`/`gdi32`, so the GUI symbols stay unresolved. Use `build_owc_crt.bat`
(verified static-CRT Win9x path), `build_target_crt.bat` (MSVC 6), or
`build_mingw_crt.bat` (MinGW, needs `msvcrt.dll`) for GUI builds. The non-GUI
no-CRT alternates (`build_owc_nocrt.bat` / `build_target_nocrt.bat`) remain
valid for console programs.

No extra C shim and no `-lddraw` are needed: DirectDraw is loaded dynamically
and GDI is the fallback. Run `prog.exe <path>` to open a file, or
`prog.exe --smoke <in> <out>` for the scripted headless save used by the tier.

Sources: `main.zig` (entry) imports `buffer.zig`, `errtab.zig`, `idents.zig`,
`lexer.zig`, `match.zig`, `ui.zig`, and `undo.zig`; pass only `main.zig` — the
compiler resolves the rest.
