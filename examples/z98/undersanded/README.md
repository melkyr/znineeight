# UNDERSANDED — M1 platform · M2 console fight · M3 sim/replay/tooling · M4 dock loop · M10.1 UX feedback

Two no-CRT Win9x executables built from one source tree (spec §26/§32/§33),
plus a **native Linux gate runner**. All are Z98 → C89 images; the Win9x pair
links through `i686-w64-mingw32-gcc` as PE32 and imports only
GDI32/KERNEL32/USER32, passing `check_win9x_imports.sh <exe> 9x`.

| Binary | Subsystem | Entry | Presentation |
| :--- | :--- | :--- | :--- |
| `under.exe` | `WINDOWS_GUI` | `main.zig` | **M9 playable window**: one `std_gfx` window (80×30 cells); dock/map/node/journal/help are cell screens, the fight is the 640×480 px art frame |
| `undtool.exe` | `WINDOWS_CUI` | `main_console.zig` | **M4 playable console**: dock-first expedition navigation, `std_io` text frames + stdin keys, no window |
| `undtool.nix` | Linux ELF | `undtool_native.zig` | tooling and `--play`/`--fight`: `--sim`, `--replay`, `--test-rules`, `--dump-grid`, `--dump-defs` |

`undtool.exe` with no arguments starts at the **dock** and runs the M4
expedition loop (`D`epart → map → zone → node → hunt/rest/surface). Fights use
the M2 keys (`S`/`R`/`E`/`F`, with the rare/named subdue modal on
`A`/`F`/`Esc`). A successful subdue shows the explicit `[C]ontinue` intro,
then settlement uses `[1] Release` or `[2] Sell` (never `R`/`S`). Every field
action leaves a one-line status: the terminal prints it after the frame and the
window renders it on cell row 29; it is cleared at the next key. `under.exe`
runs the same boot/nav state machines in one window: first-run lore, the start
menu and the save-error screen all render, and the dock/map/node/journal/help
stay cell-rendered while a live fight (or its subdue modal) presents the art
frame. `app.zig` owns the shared init/probe path and routes the console entry
to `nav.zig`.

Two optional console flags select a play mode directly (they never touch the
M1 sample/probe path):

* `--play` — dock-first expedition navigation, the same loop as the no-argument
  console (available in `undtool.exe` and the native `undtool.nix`).
* `--fight` — the M2 one-off fight with the 1–5 creature chooser.

Both flags are exclusive: combining them with each other or with any tool flag
(`--sim`, `--replay`, `--test-rules`, `--dump-grid`, `--dump-defs`, `--screen`,
`--creature`, `--seed`, `--hull`) exits 2. There is no runtime `--headless` flag: the GUI
mode is selected at build/link time (Ruling A), because Z98 has no
program-level `-D` build option.

`undtool.exe` (and native `undtool.nix --play`) starts directly at the dock and
skips the lore/menu boot. This boot skip is **test-only**: `under.exe` is the
real game and always runs the shared boot flow. Record it as a test affordance;
do not add console boot.

## Console play (dock, map, node)

| Screen | Keys |
| :--- | :--- |
| Dock | `R`efine / `U`pgrade / `C`raft / `B`uy / `E`quipment open their sub-menus; `T` Rest (safe, one phase); `D`epart → map; `Q`uit; `[?] Help`; `[J]ournal` |
| Map | `1`–`8` travel to Z1–Z8; `9` boss route (refused while locked); `Esc` back to dock; `[?] Help`; `[J]ournal` |
| Node | `H`unt; `R`est; `S`urface (return to dock); `[?] Help`; `[J]ournal` |
| Pending Subdue | `[C]ontinue` → settlement; `[1] Release` or `[2] Sell`, then back to the node |

`[?] Help` opens the page-appropriate manual (pages 1–9) on every screen;
`[J]ournal` opens the journal on dock/field screens when a save is active. `Q`
quits only at the dock. EOF on stdin quits anywhere (including from a fight),
so a no-input run exits cleanly with status 0.

## Window play (`under.exe`)

`under.exe` opens one `std_gfx` window titled `UNDERSANDED` for the whole
session. It keeps the same boot flow as the console (lore → menu → save error)
and the same navigation keys:

| Screen | Presentation | Keys |
| :--- | :--- | :--- |
| Boot (lore/menu/save error) | 80×30 cells | `Enter`/`[C]ontinue`/`[N]ew`/`[F]resh`/`[B]ackup`/`[Q]uit`, `?` help |
| Dock/map/node/journal/help | 80×30 cells | same as console play |
| Fight | 640×480 art frame | `S`/`R`/`E`/`F` (or click the four buttons), `?` help |

The one-action status line renders on cell row 29 for cell-screen views; live
art notices go through `render_art.drawNotice` in the 640×480 fight log.
The pixel tier is attached once after content boot (`gfxPxAttach`). If attach
fails (including a depth below 16bpp) the session stays in all-cell mode and the
reason is logged once to `errors.log`; an art frame that loses its surface is
restored and fully repainted, and only a failed restore falls back to cells.
Mouse clicks are translated
only in the live fight: the four exported button rects synthesize the same
`S`/`R`/`E`/`F` key. Rendering never initialises RNG or advances game phases.

`under.exe --perf` samples each rendered frame with the high-resolution timer
and appends exactly one summary line to `errors.log` in the writable data dir on
exit:

```
perf frames=N p50=Xms p95=Yms p99=Zms
```

Frame timings are diagnostics only, never a gate. `--perf` is a `under.exe`
flag; console tool flags are routed by `undtool.exe` before this loop.

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
6. GUI entry (`under.exe`) runs the playable window loop (cell boot/nav plus
   the art fight); console entry (`undtool.exe`) runs the playable dock loop.
7. Exit 0.

`undtool.exe` first prints the M1 diagnostics (resolved paths,
writability/fallback, surface line, sample bytes), then runs the playable dock
loop. EOF on stdin (including a no-input run) terminates cleanly and exits 0.
The `--play` and `--fight` console flags bypass the M1 sample/probe path.

## Linux support

The console entry `main_console.zig` is Windows-only: it links `std_gfx` →
`std_gfx_pal` → `#include <windows.h>`. A Linux-compatible gate runner is
provided in `undtool_native.zig` — a gfx-free root that forwards to
`undtool.run`, so `--sim`, `--replay`, `--test-rules`, `--dump-grid`,
`--dump-defs`, `--play` and `--fight` behave exactly as in `undtool.exe`. This is the authoritative CI
path for the logic/sim gates (spec §26 test model); the Windows binaries remain
the shipped artifacts.

This example therefore has two separate tool roots: `undtool_native.zig` for
Linux and `main_console.zig` for Windows (they call different console APIs; the
native root uses `--play` for the gfx-free console loop).

### Linux

```sh
mkdir -p out/native
/path/to/zig1_5_clean -fsafe -W -osl --output-dir out/native \
  examples/z98/undersanded/undtool_native.zig
sh out/native/build_target.sh linux out/native/undtool.nix
./out/native/undtool.nix --test-rules    # rules_ok=100
./out/native/undtool.nix --dump-defs examples/z98/undersanded/data.z98
./out/native/undtool.nix --play          # dock-first console loop
./out/native/undtool.nix --fight         # M2 creature chooser
```

`build.sh` emits this runner automatically (`out/native/undtool.nix`) next to
the two cross-built exes.

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
* `out/native/undtool.nix` — `-osl` emit + `build_target.sh linux` link of
  `undtool_native.zig` (no Windows headers; native gate runner).

`tests/fixtures/sample.txt` is copied to the output dir next to both exes.

## Outputs

* `out/under.exe`, `out/undtool.exe`, `out/sample.txt`
* `out/native/undtool.nix` — native Linux gate runner (not shipped)
* `out/probe_out.txt` — written at run time (exact bytes of `sample.txt`)
* `out/build_gui.log`, `out/build_cui.log`, `out/build_native.log`,
  `out/link_native.log`, `out/warn_*.log`
