# UNDERSANDED — M1 platform + M2 console fight

Two no-CRT Win9x executables built from one source tree (spec §26/§32/§33).
Both are Z98 → C89 → `i686-w64-mingw32-gcc` PE32 images that import only
GDI32/KERNEL32/USER32 and pass `check_win9x_imports.sh <exe> 9x`.

| Binary | Subsystem | Entry | Presentation |
| :--- | :--- | :--- | :--- |
| `under.exe` | `WINDOWS_GUI` | `main.zig` | windowed terminal mode: `std_gfx.gfxOpen(80, 30)` titled `UNDERSANDED` |
| `undtool.exe` | `WINDOWS_CUI` | `main_console.zig` | **M2 playable console fight**: `std_io` text frame + stdin keys, no window |

`undtool.exe` now runs the playable M2 text fight: on start it prints a 1–5
creature chooser, then the fight frame after every stdin key (`S`/`R`/`E`/`F`,
with the rare/named subdue modal on `A`/`F`/`Esc`) until an outcome line.
`under.exe` keeps the M1 skeleton surface unchanged. `app.zig` owns the shared
init/probe path and routes the console entry to `fight_console.zig`. There is
no runtime `--headless` flag: the mode is selected at build/link time
(Ruling A), because Z98 has no program-level `-D` build option.

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
6. GUI entry (`under.exe`) draws one line (`UNDERSANDED M1: skeleton OK`) on
   the given surface; console entry (`undtool.exe`) runs the playable fight.
7. Exit 0.

`undtool.exe` first prints the M1 diagnostics (resolved paths,
writability/fallback, surface line, sample bytes), then runs the playable fight
UI. EOF on stdin (including a no-input run) terminates cleanly and exits 0.

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
