# z9dbg

A source-level debugger for Z98 programs. It loads the `.z98dbg` sidecars
emitted by `zig1 -d`, sets breakpoints by source line, steps, shows a
backtrace, and dumps variables against a Linux (`ptrace`) or Win98 debuggee.

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

### Debug maps

The program being debugged (the *debuggee*) must be emitted with `-d` so the
map sidecars exist next to its generated C:

```sh
mkdir -p dbgout
/path/to/zig1_5_clean -d -o dbgout ../hello/main.zig
sh dbgout/build_target.sh
./out/prog dbgout/prog
```

The `-d` emission writes the C and the map sidecars but not an executable;
`sh dbgout/build_target.sh` links them into `dbgout/prog` (the script defaults
to the `linux` target and `prog` output). The sidecars stay next to that
executable, where z9dbg scans for them.

`-d` writes `<stem>.z98dbg.syms`, `<stem>.z98dbg.lines`, and
`<stem>.z98dbg.cnames`. z9dbg then reports `z9dbg: ... <debuggee>` and stops
at the debuggee's first mapped source line. Without a map it reports that no
debug information was found.

Sources: `main.zig` (entry) imports `backend.zig`, `backend_linux.zig`,
`backend_select.zig`, `backend_win98.zig`, `coff_lines.zig`, `dbg_core.zig`,
`dwarf_lines.zig`, `map_reader.zig`, and `pe_debug.zig`; pass only `main.zig` —
the compiler resolves the rest.
