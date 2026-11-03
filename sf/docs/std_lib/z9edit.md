# z9edit — single-file Z98 source editor (Win9x)

| | |
|---|---|
| **Source** | `examples/z98/z9edit/` (`main.zig`, `ui.zig`, six headless core modules) |
| **Platform** | Win9x / Win98, PE32, no-CRT (Wine is the Linux story) |
| **Built on** | `std_gfx` (`sf/docs/std_lib/gfx.md`) |
| **v1 scope** | one file, syntax + declared-ident colors, bracket awareness, selection, clipboard, undo, save |

## Overview

`z9edit` is the minimal source editor mandated by the Phase 2 roadmap. It is a
thin `ui.zig` shell over the GUI-free headless core (`buffer`, `lexer`,
`idents`, `match`, `undo`, `errtab`) and `std_gfx`. The core is native-Linux
testable; the shell is gated by a scripted `--smoke` save-byte golden plus an
Xvfb/Wine window smoke. Interactive fidelity is verified on operator Win98
hardware.

## Build + run

```sh
# compiler from the seed (lib/ beside it)
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/z9

# no-CRT Win9x exe
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32" \
  bash scripts/win32_cross/cross_nocrt.sh /tmp/z9/zig1_5_clean \
    examples/z98/z9edit/main.zig /tmp/z9edit/work /tmp/z9edit/z9edit.exe

# run (Wine on Linux, or the real Win98 box)
wine /tmp/z9edit/z9edit.exe path\to\file.zig
```

No extra C file is needed: DDraw is loaded dynamically and the window is polled.
The exe passes `check_win9x_imports.sh z9edit.exe 9x` with `GDI32/USER32/
KERNEL32` (no `DDRAW.DLL`) and **no `msvcrt.dll`**.

## Usage

`z9edit <path>` opens one file. A missing file starts an empty buffer and is
created by the first `Ctrl+S`. Close box or `Ctrl+Q` quits; there is **no
unsaved-exit prompt** in v1 (the title shows `*` while dirty). The window title
is `z9edit — <basename>`.

Test affordance: `z9edit --smoke <in> <out>` loads `<in>`, feeds a scripted
`Event` sequence through the same `uiStep` the real pump uses, saves to `<out>`
via `Ctrl+S`, and exits 0. It prints a flushed `READY` before the scripted
frames so the Xvfb runner can key off it. `--theme-test` prints the config
selection, exercises the memory-mode theme API, and cycles `F2` through
`uiStep` without opening a window.

### Theme config

At startup `z9edit` reads `z9edit.ini`, then `z9edit.cfg`, looking in the exe
directory first and the current working directory second. A line
`theme=white|solarized|dark` is matched case-insensitively (surrounding
whitespace is ignored). A missing file, missing key, unknown value, or
malformed theme line selects **white** (the default) and never crashes. `F2`
cycles white → solarized → dark → white for the session only; it does **not**
rewrite the config.

## Key map

| Key | Action |
|:--|:--|
| `Left/Right/Up/Down` | move caret |
| `PgUp/PgDn` | move one viewport |
| `Home/End` | line start / content end |
| `Shift` + arrows/nav | extend selection |
| `Ctrl+A` | select all |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | copy / cut / paste (`CF_TEXT` + internal fallback) |
| `Ctrl+Z` | undo (no redo) |
| `Ctrl+S` | save (clears dirty) |
| `Ctrl+Q` / close box | quit |
| `F2` | cycle theme white → solarized → dark → white |
| type / `Backspace` / `Delete` | insert / delete; with a selection, replaces it |
| mouse click | move caret to the clicked cell |
| mouse drag | select from anchor to cursor |
| wheel | scroll **3 lines per notch** (no scrollbar) |

`Enter` inserts a newline; `Tab` inserts a tab displayed at 8-column stops.
Typing any printable ASCII inserts it.

## Display

- Visible lines only, colored by the per-line lexer with block-comment and
  multi-line-string state carried across lines.
- Token colors: keyword, builtin (`@...`), `error[NNNN]`, string, comment,
  number, type name, identifier. Identifiers that name a `const`/`var`/`fn`
  declared in the file get a distinct color.
- Gutter line numbers (right-aligned).
- Status bar: `line,col` (1-based), `unbalanced <ch> from line N` when the
  bracket scan finds an unmatched opener/closer, and `error[NNNN] <message>`
  when the cursor is inside an error code. The message table is the editor's
  own, seeded from `sf/src/diagnostics.zig` (no compiler import).
- Cursor adjacent to `()[]{}` inverts the matching pair (cross-line works);
  the bracket character itself is drawn in the foreground role for readability.
- Selection is drawn inverted (`15` on `13`); cursor is a bright block
  (`0` on `15`). The same role indices are used on all three themes.

The declared-identifier table is rebuilt at load, at save, and after **2 s of
edit idle** (`std_time.ticksMs` in the event loop). It is never rebuilt on the
keystroke path.

## CRLF / LF behavior

The buffer is **canonical LF internally**; positions and `bufLen` are canonical
offsets. On load, every CRLF is folded to LF and the file's ending is
remembered. On save, every canonical LF is expanded back to CRLF when the file
used CRLF. A pure-LF or pure-CRLF file therefore round-trips byte-identically
with no edits, and edits use the file's own ending. A mixed-ending file is
classified CRLF (documented, not byte-identical on a mixed round trip).

## Limits (v1)

- One file; no tabs, no multi-file, no split view.
- No redo (undo only), no search/find, no completion popup, no print.
- No scrollbar widget; click-to-cursor + wheel + PgUp/PgDn only.
- No compile-from-editor and no error fixing beyond the status-bar message.
- ASCII editing surface (`std_gfx` glyphs are 32..126).
- Strictly one window; the editor is not a plugin host.
- Files are capped by the core gap buffer (16 MiB) and the 12 MiB runtime
  arena; normal source files are far below either.

## Measured cost (this test box)

| Metric | Value | Notes |
|:--|:--|:--|
| Z98 compile max RSS (`main.zig`, `-osw --dump-c89`) | **7,012–7,304 KiB** | compile-only 16 MB gate |
| Editor runtime RSS (Wine-hosted) | **≈35.4 MiB** | evidence only, not gated; includes Wine overhead |
| Real Win98 runtime RSS | **not measured** | operator hardware |
| Open a 100 KB file | **≈40 ms** | native core `bufLoad` + `identScan`, 3,414-line file, this test box |

The **16 MB gate is compile-only** (Z98 compile peak RSS < 16 MB). Runtime
memory is not gated: the Wine-hosted ≈35.4 MiB figure is recorded evidence
that includes Wine overhead, and real Win98 runtime RSS is operator-owned and
not measured here. The operator session (edit/select/undo/save) is the hardware
proof; the Xvfb/Wine screenshot is a smoke signal only.
