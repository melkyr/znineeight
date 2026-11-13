# UNDERSANDED — M1 platform skeleton

Two no-CRT Win9x executables built from one source tree, proving the link
configs and platform plumbing before any game code exists (spec §26/§32/§33,
G15 scaffold). Both are Z98 → C89 → `i686-w64-mingw32-gcc` PE32 images that
import only GDI32/KERNEL32/USER32 and pass `check_win9x_imports.sh <exe> 9x`.

| Binary | Subsystem | Entry | Presentation |
| :--- | :--- | :--- | :--- |
| `under.exe` | `WINDOWS_GUI` | `main.zig` | windowed terminal mode: `std_gfx.gfxOpen(80, 30)` titled `UNDERSANDED` |
| `undtool.exe` | `WINDOWS_CUI` | `main_console.zig` | console/headless: `gfxOpenMemory(80, 30)` + stdout, no window |

`app.zig` is the shared skeleton used by both entries. There is no runtime
`--headless` flag: the mode is selected at build/link time (Ruling A), because
Z98 has no program-level `-D` build option.

## Skeleton behaviour

1. `std_os.initArgs(argc, argv)`.
2. Resolve the exe dir (`paths.resolveDataDir`) and probe writability
   (`paths.probeWritable`). Mutable output goes to `paths.dataDirOrFallback`
   (the exe dir when writable, else `C:\WINDOWS\TEMP\UNDERSAN\`).
3. Install the trap handler with `std.debug.setTrapHandler` and a
   **pre-allocated** backtrace buffer (no allocation inside the handler). On a
   fatal trap it writes `crash.dmp` (`writeCoreDump`) and `crash.log`
   (backtrace) beside the writable data and prints one line to stderr.
4. Read `sample.txt` from the exe dir (installed content, spec §32).
5. Write `probe_out.txt` into the writable dir with the sample bytes.
6. Draw one line (`UNDERSANDED M1: skeleton OK`) on the given surface.
7. Exit 0.

`undtool.exe` also prints the resolved paths, the surface line, and the sample
contents to stdout.

## Build

The compiler resolves `lib/` from a sibling directory, so sync the std modules
first if the compiler lives outside the tree:

```sh
cp sf/src/std_*.zig /tmp/zig1-m1/lib/
ZIG=/tmp/zig1-m1/zig1_5_clean sh examples/z98/undersanded/build.sh
```

Run from the repo root (the script resolves it itself). Defaults: compiler
`/tmp/zig1-m1/zig1_5_clean`, output `examples/z98/undersanded/out`. Env
overrides: `ZIG`, `OUT`.

The script runs `-fsafe -W` (warnings as errors) dumps for both entries, then
links:

* `under.exe` — `DUMP_TARGET=-osw`, `EXTRA_LIBS="-luser32 -lgdi32"`,
  `EXTRA_LDFLAGS="-Wl,--subsystem,windows"`.
* `undtool.exe` — `DUMP_TARGET=-osw`, console subsystem (no `--subsystem`
  override). The same GDI32/USER32 libs are linked because the cell surface is
  part of the image even in memory mode.

`tests/fixtures/sample.txt` is copied to the output dir next to both exes.

## Outputs

* `out/under.exe`, `out/undtool.exe`, `out/sample.txt`
* `out/probe_out.txt` — written at run time (exact bytes of `sample.txt`)
* `out/build_gui.log`, `out/build_cui.log`, `out/warn_*.log`
