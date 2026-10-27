# Task 1 report — P4-M1 `std_gfx` + `std_gfx_pal` + `gfx_demo`

- Date: 2026-10-27
- Repo: `/workspace/znineeight`, branch `zig1_improvements`, BASE `60e3a916`
- Status: **DONE**

## Plan

1. Write `examples/z98/gfx_demo/tests/tier_gfx.sh` first; run it RED (missing sources /
   missing `EXTRA_LIBS` support).
2. Add the additive `EXTRA_LIBS` hook to `scripts/win32_cross/cross_nocrt.sh`.
3. Add closed-world `DDRAW_ALL` / `GDI32_ALL` / `USER32_ALL` to
   `scripts/win32_cross/check_win9x_imports.sh` (seed from T0-pre, then trim/extend
   to exactly what the real exe imports).
4. Implement `sf/src/std_gfx.zig` (contract types, cell grid, glyph/cell dump,
   headless memory mode) and `sf/src/std_gfx_pal.zig` (Win32 window + pump,
   DirectDraw7 windowed path, hand-written COM vtables, clipboard).
5. Implement `examples/z98/gfx_demo/main.zig` (`--smoke N`, `--dump-grid`).
6. Add both std files to the two seed copy lists + comment blocks (no seed
   rotation).
7. Build the compiler from the committed seed, build the demo no-CRT, run the
   import gate, generate + inspect the headless golden, run Xvfb/Wine screenshot
   evidence, record compile RSS.
8. `git diff --check`, code commit, report commit.

## RED evidence (before implementation)

```
== (a) no-CRT build + import gate ==
       Z98 Compiler 2026 (map: off)
       error: could not read input file
       XRUNRC=DUMPFAIL
FAIL - no-CRT build failed (rc=1; see /tmp/gfx_tier/build.log)
TIER_GFX FAIL
```

## Implementation notes

- **DDraw7 only.** `DirectDrawCreate` returns v1, then
  `QueryInterface(IID_IDirectDraw7)` (local 16-byte GUID, so `-ldxguid` is not
  needed at link time) and all calls go through hand-written
  `IDirectDraw7` / `IDirectDrawSurface7` vtables. Unused slots preserve the
  ddraw.h indices (IDirectDraw7 at `:1798`, Surface7 at `:2503`, clipper at
  `:1335`).
- **Windowed path:** `DDSCL_NORMAL`; 640x480 `DDSCAPS_OFFSCREENPLAIN`; GDI
  `GetDC` + `SYSTEM_FIXED_FONT` + `TextOutA`; `Blt(primary, NULL, back, NULL,
  DDBLT_WAIT, NULL)`. No Flip/back buffer/`CoInitialize`. A best-effort clipper
  (`CreateClipper` + `SetHWnd` + `SetClipper`) is created but never gates the
  build (T0-pre proved the unclipped path).
- **Z98 COM gotcha found during implementation:** Z98 `?*void` is a two-word
  `{has_value, value}` representation, NOT a C `void*`. Passing `&opt` to a COM
  out-parameter wrote into `has_value` and broke `DirectDrawCreate` /
  `QueryInterface`. All COM out-params are `**void` with plain `*void`
  variables. This is why the first windowed run failed `gfxOpen`; after the fix
  it passes.
- **Contract shapes:** `Color = u8`; `EventKind` enum in the binding order;
  `Event` exactly `{kind, ch, code, x, y, button, wheel, cols, rows, mods}`
  (mods bit0 Shift / bit1 Ctrl). `gfxCharSize(g, *w, *h)` and
  `gfxBufferSize(g, *w, *h)` are out-param metrics; `gfxDumpGrid` is one line
  per row, '\n' after every row, with trailing padding spaces trimmed (so
  `git diff --check` stays clean); leading spaces keep cell columns. Bytes
  outside 32..126 render as `?`. All coordinates are cells.
- **Headless:** `gfxOpenMemory` never calls PAL; the cell grid is the dump
  source. `--dump-grid` therefore never creates a window / never needs X.
- **No-CRT:** no `msvcrt.dll` import and no new `zig_nocrt.c` shim was needed.
  `READY` is printed through `std_io.write` (PAL stdout), not `printf`.
- **Seed lists:** `std_gfx.zig` + `std_gfx_pal.zig` added to both copy lists and
  comment blocks; no seed archive rotation here (Task 3 rotates).
- **Import gate:** `DDRAW_ALL`, `GDI32_ALL`, `USER32_ALL` seeded from T0-pre and
  then adjusted to exactly the real exe's imports. `KERNEL32_9X` gained
  `GlobalAlloc/GlobalFree/GlobalLock/GlobalUnlock` (clipboard, imported by the
  exe); no `msvcrt` entry was added to 9x.

## PASS evidence

Compiler rebuilt from the committed seed:

```
bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz /tmp/p4_t1_build
[seed] two-hop closure OK: hop1 == hop2 == 2fc64ffedb3ba5f4e8adf35896729e54
```

Demo build (fresh compiler lib contains both new std files):

```
EXTRA_LIBS="-luser32 -lgdi32 -lddraw" bash scripts/win32_cross/cross_nocrt.sh \
  /tmp/p4_t1_build/zig1_5_clean examples/z98/gfx_demo/main.zig \
  /tmp/p4_t1_work /tmp/p4_t1_work/gfx_demo.exe
dump: rc=0 error_brk=0 panic=0 c=9 no-crt link ok
XRUNRC=0
```

`tier_gfx.sh` final run (`/tmp/gfx_tier_final.log`), rc 0:

```
ok   - no-CRT build produced gfx_demo.exe
ok   - Z98 compile max RSS < 16 MB (6244 kB)
ok   - file: PE32 executable (console) Intel 80386, for MS Windows, 7 sections
ok   - check_win9x_imports.sh 9x PASS
       IMPORT GATE PASS (9x): /tmp/gfx_tier/gfx_demo.exe
ok   - DLL imports include DDRAW.DLL + GDI32.DLL + USER32.DLL
ok   - no MSVCRT.DLL import
ok   - headless --smoke 30 --dump-grid exited 0
ok   - grid.txt written (md5 ef5f8632fa1212a792020cbe1352e0f5, 377 bytes)
ok   - grid.txt matches golden byte-for-byte
ok   - Xvfb up on :77
ok   - READY sentinel seen
ok   - screenshot saved: /tmp/gfx_tier/shot/shot.png
       (mean/stddev/colors: 0.0320801 0.144761 119)
ok   - windowed --smoke 30 exited 0
== tier_gfx summary: 13 passed, 0 failed ==
TIER_GFX PASS
```

Import table of the real exe:

```
DLL DDRAW.DLL   DirectDrawCreate
DLL GDI32.DLL   CreateSolidBrush DeleteObject GetStockObject GetTextMetricsA
                SelectObject SetBkMode SetTextColor TextOutA
DLL KERNEL32.DLL (existing kernel32 set + clipboard GlobalAlloc/GlobalFree/
                GlobalLock/GlobalUnlock)
DLL USER32.DLL  CloseClipboard CreateWindowExA DefWindowProcA DispatchMessageA
                EmptyClipboard FillRect GetClipboardData GetDC GetKeyState
                LoadCursorA OpenClipboard PeekMessageA PostMessageA
                PostQuitMessage RegisterClassA ReleaseDC SetClipboardData
                SetForegroundWindow ShowWindow TranslateMessage UpdateWindow
```

No `MSVCRT.DLL`. `check_win9x_imports.sh 9x` PASS.

### Golden

`examples/z98/gfx_demo/tests/golden/grid.txt` generated once from the verified
headless run, inspected, then committed:

```
md5 ef5f8632fa1212a792020cbe1352e0f5   (377 bytes, 20 lines, trailing
padding trimmed)
```

First lines (the `X` at row 8 is the cursor after the scripted click at
cell 20,8; the last line is frame 29's status after wheel +3 / resize / q):

```
 z98 gfx demo | DirectDraw7 + GDI
 ESC quit | wheel=3 lines | click moves cursor
  std_gfx: cell grid + GDI text + DDraw7 Blt
  ABCDEFGHIJKLMNOPQRSTUVWXYZ
  abcdefghijklmnopqrstuvwxyz
  0123456789 !"#$%&'()*+,-./:;<=>?@[\]^_`{|}~
                    X
   fill-rect exercised
  scripted: click, wheel +3, resize, q
 click=(20,8) clicks=1 wheel=3 frame=29 resize=64x20
```

### Compile RSS

- Z98 `--dump-c89` of `examples/z98/gfx_demo/main.zig`: **6244 kB** max RSS
  (`/usr/bin/time -v`), under the 16 MB target.
- The tier measures the Z98 compile, not the host gcc phase; the gcc-of-C build
  itself is a host tool phase (its own RSS is not the product compile cost).

### Xvfb/Wine window evidence (bonus, non-pixel)

- Isolated prefixes only; the headless prefix is not reused for the window
  (a wineserver started with no X keeps a no-display environment, so the tier
  kills it and uses `$OUT/wineprefix_x`).
- `READY` seen, `import -window root` saved a 1024x768 PNG, mean 0.0320801,
  stddev 0.144761, 119 colors (palette colors from the demo's fill/text path).
- Windowed `--smoke 30` exited 0. This is a smoke signal (Wine != Win98), not a
  pixel gate.

## Gates / non-goals

- `git diff --check` clean.
- No corpus/pins/markers touched (no compiler source change).
- `run.err`, `docs/sf/QUICK_REF.md` (pre-existing modification), and the
  plan/spec files were not staged/committed.
- No seed rotation (`release/seed/` untouched).

## Concerns / notes

1. The windowed tier deliberately uses a second isolated Wine prefix so the
   no-X headless pass cannot poison the wineserver's display driver. That is an
   environment fix inside the tier, not a product change.
2. `gfxFillRect` fills with `bg` and draws a 1-pixel `fg` border when the rect
   is at least 3x3, so both color arguments are observable without adding a
   general line primitive. This is a builder choice within the binding contract.
3. `gfxOpenMemory` is headless in the Windows/no-window sense (no HWND, no
   DirectDraw, no X); the std modules still carry Win32 externs, so native
   Linux rendering is not a v1 target (design: Wine only).
4. During an early manual smoke I let Wine create its default `$HOME/.wine`
   prefix before switching to the isolated recipe; all final/tier runs use
   isolated prefixes. No repo artifact is affected.
