# Graphics — `std_gfx` + `std_gfx_pal`

| | |
|---|---|
| **Modules** | `std_gfx` (contract + cell grid + metrics), `std_gfx_pal` (Win9x window/pump + DirectDraw7 + clipboard) |
| **Layers** | `L2` — app-facing GUI contract over `L3` OS backends |
| **Import (by path)** | `const std_gfx = @import("std_gfx");` |
| **Platform** | Win9x / Win98 (PE32, no-CRT profile); headless memory mode on any target |

## Module overview

`std_gfx` is the minimal windowed GUI layer used by `z9edit` and, later, the
Phase 5 3D work. The contract is deliberately small: a fixed-pitch ASCII cell
grid, one window, keyboard/mouse/wheel events, a 16-color app palette, and a
clipboard. Nothing about DirectDraw, Win32 handles, or COM vtables crosses the
`std_gfx` seam.

All coordinates are **cells** (`x`, `y`), not pixels. The window is resizable;
`gfxPollEvent` turns a `WM_SIZE` into an event carrying the new `cols`/`rows`
and the layer resizes its grid and offscreen surface. Drawing is immediate
against the offscreen surface between `gfxBeginFrame` and `gfxEndFrame`; the
end of a frame blits the offscreen to the primary surface 1:1 over the client
area.

`Color` is a `u8` palette index `0..15`. Three 16-color themes ship in
`std_gfx_pal` — **white (default)**, **solarized (light)**, and **dark**:
`0` background, `1` panel, `2` foreground, `3` comment, `4` fill background,
`5` green, `6` brown, `7` status background, `8` alternate background,
`9..12` syntax accents, `13` selection/accent, `14` warning/gold, `15` bright.
Token-to-index mapping is the app's choice; tests assert kinds, never pixels.
Unknown indices wrap (`idx & 15`).

### DirectDraw7 discipline

`DirectDrawCreate` returns the **v1 `IDirectDraw`**. The layer immediately
`QueryInterface(IID_IDirectDraw7)` and uses `IDirectDraw7` /
`IDirectDrawSurface7` from then on. Passing a 124-byte `DDSURFACEDESC2` to the
v1 `CreateSurface` fails with `E_INVALIDARG 0x80070057` (confirmed under Wine).
The windowed path is `DDSCL_NORMAL`, primary + 640x480 offscreen
(`DDSCAPS_OFFSCREENPLAIN`), GDI text into the offscreen DC, then
`Blt(primary <- offscreen, DDBLT_WAIT)`. There is **no** `Flip`, no back-buffer
caps, and no `CoInitialize`; the GUID is a local 16-byte value so `dxguid` is
not linked.

### COM vtable discipline

Every COM call goes through a hand-written vtable struct whose fields are
`extern "stdcall"` function-pointer **types**; the call site uses the
convention-qualified cast documented in QUICK_REF §"Calling convention
(Win9x)". Unused slots stay in the struct with the correct index. A wrong slot
order misbehaves silently, so the slot order is taken from `ddraw.h`
(`IDirectDraw7`, `IDirectDrawSurface7`, `IDirectDrawClipper`).

## Quick start (Win9x window)

```zig
const std_gfx = @import("std_gfx");

pub fn main() void {
    const g = std_gfx.gfxOpen("demo", 80, 25) catch return;
    var ev: std_gfx.Event = undefined;
    while (std_gfx.gfxPollEvent(g, &ev)) { /* handle */ }
    if (!std_gfx.gfxBeginFrame(g)) return;
    std_gfx.gfxClear(g, 0);
    std_gfx.gfxDrawText(g, 1, 0, "hello", 2, 0);
    _ = std_gfx.gfxEndFrame(g);
    std_gfx.gfxClose(g);
}
```

Build no-CRT for Win9x (see QUICK_REF for the full recipe):

```sh
DUMP_TARGET="-osw" \
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" \
EXTRA_CSRC="$PWD/sf/src/include/zig_gfx_wndproc.c" \
  bash scripts/win32_cross/cross_nocrt.sh <zig1> <entry.zig> <work> <out.exe>
```

`EXTRA_CSRC` supplies the stdcall WndProc trampoline (Z98 cannot define a
stdcall callback). The exe imports `DDRAW.DLL`, `GDI32.DLL`, `USER32.DLL`, and
`KERNEL32.DLL`, never `MSVCRT.DLL`, and passes
`check_win9x_imports.sh <exe> 9x`.

## API

### Types

```zig
pub const Color = u8;
pub const Theme = enum(u8) { white, solarized, dark };
pub const GfxError = error{ OpenFailed, OutOfMemory, SurfaceFailed, ClipboardFailed };
pub const Gfx = struct { opaque: *GfxState };            // opaque
pub const EventKind = enum { key_down, key_up, mouse_move, mouse_down,
    mouse_up, wheel, resize, close };
pub const Event = struct {
    kind: EventKind,
    ch: u8,        // key char (unmodified for Ctrl chords, e.g. 's')
    code: u16,     // VK_* code
    x: u32, y: u32, // cell coordinates for mouse events
    button: u8,    // 0 = left
    wheel: i32,    // lines (3 per notch)
    cols: u32, rows: u32,
    mods: u8,      // bit0 Shift, bit1 Ctrl
};
```

### Gfx lifecycle

**`gfxOpen(title, cols, rows) GfxError!*Gfx`** — create a window + primary +
offscreen surface + glyph atlas (ASCII 32..126, `SYSTEM_FIXED_FONT`, metrics
from `GetTextMetricsA`). Opens fail closed if any DDraw step fails.

**`gfxOpenMemory(cols, rows) GfxError!*Gfx`** — backend-free cell grid. No
window, no DDraw, no clipboard. It exists so headless `--dump-grid` / save-byte
tests are deterministic; drawing updates the same cells the windowed path uses.

**`gfxSetTitle(g, title) bool`** — additive P4-M3 helper: update the real
window title (`z9edit` uses it to keep the dirty `*` current). Returns `false`
for a memory Gfx.

**`gfxSetTheme(g, theme) bool`** — P4-M4: switch the active palette. A windowed
Gfx rebuilds all 16 brushes **and** the glyph atlas (the atlas bakes the
palette colors); the new resources are built before the old ones are released,
so a failed rebuild returns `false` and keeps the old theme. A memory Gfx has no
window or atlas: the call **succeeds, records the theme for `gfxGetTheme`, and
leaves the cell grid unchanged** (cells are ASCII with no color payload).

**`gfxGetTheme(g) Theme`** — the active theme (`white` by default).

**`gfxClose(g) void`** — release surfaces, atlas, brushes, and the window.

### Themes

The three 16-entry RGB tables live in `std_gfx_pal` and are selected by
`Theme`; **white is the default** so a fresh window opens light. A theme change
does not touch the cell grid or the surface geometry — it releases the old
color/mask atlases and brushes and builds the new ones (keeping the old theme
on allocation failure). The PAL mask atlas always uses a stock white brush for
its background, independent of the palette's index 15, because the white
theme's bright is black.

### Frame + primitives

**`gfxBeginFrame(g) bool`** — `GetDC` the offscreen and select the fixed font.
Call before drawing; `false` means no surface/DC.

**`gfxEndFrame(g) bool`** — `ReleaseDC`, compute the 1:1 client blit, and
`Blt` to the primary. Logs `present 1:1 client=WxH back=WxH dest=(x,y)` when the
present geometry changes.

**`gfxClear(g, bg)`** — clear the whole grid and fill the offscreen.

**`gfxFillRect(g, x, y, w, h, fg, bg)`** — fill a cell rectangle (`bg`) with a
one-pixel `fg` frame. Rectangles are clipped to the grid.

**`gfxDrawText(g, x, y, s, fg, bg)`** — draw a byte string at a cell. Bytes
outside 32..126 render as `?`. The windowed path uses the glyph atlas
(mask `SRCAND` + color `SRCPAINT`); the memory path only updates cells.

**`gfxCharSize(g, *w, *h)`** — per-cell pixel metrics.

**`gfxBufferSize(g, *w, *h)`** — pixel size of the `cols x rows` cell area.

**`gfxDumpGrid(g) []u8`** — row-major ASCII snapshot with trailing spaces
trimmed and one `\n` per row. Works in memory mode; used by the golden test.

### Events

**`gfxPollEvent(g, ev) bool`** — pump + dequeue one event. `WM_KEYDOWN` with a
character defers until `WM_CHAR` so `ch` is the typed byte; non-character keys
(arrows, PgUp/PgDn, Home/End) deliver `code` with `ch = 0`. Ctrl chords deliver
`ch` as the unmodified lowercase character and `mods` bit1 set. `WM_SIZE` becomes
a `resize` event with `cols`/`rows`; `WM_CLOSE`/`WM_QUIT` become `close`.
`WM_MOUSEWHEEL` is mapped to lines (3 per notch) by `gfxWheelLines`.

**`gfxWheelLines(raw_delta) i32`** — the exact raw-delta → lines mapping used by
the pump (`+120 → +3`, `-240 → -6`).

**`gfxTestResize(g, cols, rows) bool`** — test affordance: resize the real
window so the production `WM_SIZE` path runs, or the memory grid directly.

### Clipboard

**`gfxClipboardSet(g, s) bool`** — Win32 `CF_TEXT` (`GlobalAlloc`/`SetClipboardData`).
Returns `false` in memory mode or if the clipboard cannot be opened.

**`gfxClipboardGet(g, arena) ?[]u8`** — Win32 `CF_TEXT` copy into the arena, or
`null` when empty/unavailable. Apps keep an internal fallback buffer so headless
tests stay deterministic.

## Headless `grid.txt` recipe

The gfx tier builds the exe, then runs the real binary under Wine with
`--smoke N --dump-grid`: `gfxOpenMemory` paints the same cells and
`gfxDumpGrid` writes `grid.txt`, compared byte-for-byte with a committed golden.
This is the deterministic gate; the Xvfb window run is evidence, not a pixel
gate.

## Xvfb + Wine window smoke (evidence)

```sh
Xvfb :77 -screen 0 1024x768x24 -nolisten tcp &
export DISPLAY=:77 WINEPREFIX=/tmp/z9/wineprefix WINEARCH=win32
wineboot -i
wine ./z9edit.exe --smoke in.z98 out.tmp &   # app prints flushed READY
import -window root shot.png                 # after READY + ~0.5 s
wineserver -k; kill %1
```

Pixel output is Wine/font-specific and is **not** a pass/fail gate; real
hardware fidelity is the operator's Win98 session. The app exits 0 and the
save-byte golden is the actual gate.

## Phase 5 reuse note

Phase 5 consumes this layer's window/message-pump/COM-vtable pattern directly
rather than forking it. The v1 drawing contract is intentionally
editor-minimal (clear, fill-rect, text-at-cell, present-blit, metrics); Phase 5
does its own D3D rendering and extends `std_gfx` as needed. Exclusive/fullscreen
DirectDraw is out of scope here.

## Limits

- ASCII 32..126 only; other bytes render as `?`.
- One window, one fixed-pitch font, 16 palette indices, three fixed themes.
- No general offscreen-bitmap API, no line/curve primitive, no scrollbar widget.
- The clipboard is `CF_TEXT` (ANSI) only.
- Win9x is the only backend; Wine is the Linux story.
