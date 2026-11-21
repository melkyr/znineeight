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

Import table of the real exe (current):

```
DLL DDRAW.DLL   DirectDrawCreate
DLL GDI32.DLL   BitBlt CreateBitmap CreateCompatibleBitmap CreateCompatibleDC
                CreateSolidBrush DeleteDC DeleteObject GetStockObject
                GetTextMetricsA SelectObject SetBkMode SetTextColor TextOutA
DLL KERNEL32.DLL (existing kernel32 set + clipboard GlobalAlloc/GlobalFree/
                GlobalLock/GlobalSize/GlobalUnlock)
DLL USER32.DLL  AdjustWindowRect ClientToScreen CloseClipboard CreateWindowExA
                DefWindowProcA DestroyWindow DispatchMessageA EmptyClipboard
                FillRect GetClientRect GetClipboardData GetDC GetKeyState
                LoadCursorA OpenClipboard PeekMessageA PostQuitMessage
                RegisterClassA ReleaseDC SetClipboardData SetForegroundWindow
                SetWindowPos ShowWindow TranslateMessage UnregisterClassA
                UpdateWindow
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

## Fix round 1

Status: **DONE**. Base for this round: `41dca492`.
- Code fix commit: `422dfa92` (WM_CHAR + wheel-lines + event init +
  WM_SIZE/glyph cache).
- Report commit: `docs(sdd): P4-M1 fix round 1 report` (this file).
- `b83df7e9` / `41dca492` were not amended.

### Findings addressed

1. **WM_CHAR typed character (Critical 1).** `pollEvent` now waits for
   `WM_CHAR` for character-producing VKs (letters/digits/punctuation/space/
   enter/tab/backspace/delete/escape), so `ch` is the actual typed character
   (uppercase/shifted punctuation included). Ctrl+letter takes the VK base
   character immediately (`Ctrl+S -> 's'`, mods bit1). Non-character keys
   (arrows/F-keys) emit `key_down` with `ch=0`. A deferred key_up covers the
   no-WM_CHAR case.
2. **Wheel lines (Critical 2).** `wheelLines(raw_delta)` returns
   `(delta / WHEEL_DELTA) * 3`; `WM_MOUSEWHEEL` uses it. Exposed as
   `gfxWheelLines` and exercised by `--smoke` (`gfxWheelLines(120)`) and a
   `--selftest` (`120 -> 3`, `-240 -> -6`). Z98 lowers signed `/` through an
   unsigned divisor, so the helper does the negative case on the positive
   magnitude (comment in the PAL).
3. **RawEvent init (Critical 3).** Every return path zeroes all `RawEvent`
   fields (`zeroRaw`), including deferred key-up and close/resize/wheel events;
   all `Event` fields are copied. No undefined payload reaches the app.
4. **ReleaseDC (Critical 4).** `gfxClose` uses
   `surfaceVtbl(st.back).ReleaseDC(...)` (never Win32 `ReleaseDC` on the
   surface DC).
5. **WM_SIZE resize (Important 5).** `WM_SIZE` calls `resizeBack` (releases and
   recreates the offscreen `CreateSurface(resize)`), updates `st.cols/rows`,
   and `gfxPollEvent` resizes the cell grid. (Round 1 used posted `WM_SIZE`;
   round 2 replaces that with the real sent-message WndProc path and
   `gfxTestResize`.)
6. **Glyph cache (Important 6).** Built once at `gfxOpen`: a 95x16 color atlas
   plus a monochrome mask atlas (GDI offscreen bitmaps, `SYSTEM_FIXED_FONT`,
   ASCII 32..126 x palette rows). `drawText` presents each cell with
   `BitBlt(SRCAND mask)` + `BitBlt(SRCPAINT color)`. `gfxOpenMemory` builds no
   atlas. Logs `glyph-atlas built ...` once and `glyph-atlas present active`
   when the first atlas cell is presented.
7. **HRESULT evidence (Important 7).** Windowed `gfxOpen`/`gfxEndFrame` log
   `DirectDrawCreate`, `QueryInterface(IID_IDirectDraw7)`,
   `SetCooperativeLevel(DDSCL_NORMAL)`, primary/offscreen `CreateSurface`, and
   every present `Blt` (plus resize/atlas/clipper lines). The tier asserts the
   six required `hr=0x00000000` lines.
8. **Brushes before failure-close (Important 8).** All 16 brush slots are
   null-initialized before window creation, so the `CreateWindowExA` failure
   path cannot `DeleteObject` garbage. Brush creation failures now fail open.

Minors:
- `Gfx` is opaque: `pub const Gfx = struct { opaque: *GfxState }` with the
  private `GfxState` holding the cells/dump/PAL state.
- All unused vtable slots are `extern "stdcall" fn() void`.
- `close` uses `DestroyWindow` + `UnregisterClassA` (no stale window/class).
- Clipboard NUL scan is bounded by `GlobalSize`.
- `GetTextMetricsA`, `CreateSolidBrush`, `SetCooperativeLevel`,
  `SetClipper`/`SetHWND` results are checked/logged.
- `gfxBeginFrame`/`gfxEndFrame` failures now exit the demo nonzero.
- Tier checks the `--dump-c89` RSS probe rc and records Wine-hosted runtime
  RSS; it asserts the atlas/HRESULT/resize/wheel evidence.
- `.gitignore` now has
  `!examples/z98/gfx_demo/tests/golden/grid.txt` (no `git add -f`).

### Fix-round evidence (two deterministic tier runs)

Run A (`/tmp/gfx_fix_tier_a.log`) and run B (`/tmp/gfx_fix_tier_b.log`) both
rc 0, **18 passed / 0 failed**, `TIER_GFX PASS`.

```
ok   - Z98 compile max RSS < 16 MB (6160 kB / 6028 kB)
ok   - check_win9x_imports.sh 9x PASS
       DLL DDRAW.DLL / GDI32.DLL / KERNEL32.DLL / USER32.DLL
       IMPORT GATE PASS (9x): /tmp/gfx_tier/gfx_demo.exe
ok   - no MSVCRT.DLL import
ok   - wheel mapping helper 120->3, -240->-6 (real wheelLines)
       WHEELMAP 120=3 -240=-6
       WHEELMAP OK
ok   - runtime RSS recorded (Wine-hosted, includes Wine): 17128 kB / 17208 kB
ok   - grid.txt written (md5 ef5f8632fa1212a792020cbe1352e0f5, 377 bytes)
ok   - grid.txt matches golden byte-for-byte
ok   - screenshot saved: (mean/stddev/colors: 0.0485363 0.177475 124)
ok   - windowed --smoke 30 exited 0
ok   - DDraw HRESULT log present (create/QI/coop/surfaces/Blt all 0x0)
ok   - glyph atlas built once at open and used for per-cell present
ok   - WM_SIZE resize delivered through the pump (70x22 cells)
```

Windowed HRESULT log (verbatim):

```
DirectDrawCreate hr=0x00000000
QueryInterface(IID_IDirectDraw7) hr=0x00000000
SetCooperativeLevel(DDSCL_NORMAL) hr=0x00000000
CreateSurface(primary) hr=0x00000000
CreateSurface(offscreen) hr=0x00000000
glyph-atlas built (95x16 GDI color+mask)
glyph-atlas present active
CreateClipper hr=0x00000000
SetHWnd(clipper) hr=0x00000000
SetClipper(primary) hr=0x00000000
Blt(primary<-offscreen) hr=0x00000000
...
CreateSurface(resize) hr=0x00000000
RESIZE 70x22 px=560x352
```

The headless run prints `RESIZE 64x20 px=512x320` for the scripted resize, but
the golden md5 is unchanged (`ef5f8632...`): the memory path keeps the fixed
64x20 grid so the deterministic payload is stable. `git diff --check` is clean.

### Fix-round notes / concerns

- The glyph cache is materialized as two GDI offscreen atlases (color + mask)
  rather than a DirectDraw surface: per-cell present is a GDI `BitBlt` into the
  offscreen DC that is already acquired, which avoids `Blt`-while-DC-acquired
  undefined behavior. This still satisfies the binding cache requirement (built
  once at open, per-cell present from the atlas).
- Runtime RSS is Wine-hosted (includes Wine's own footprint), so it is recorded
  rather than gated; the Z98 compile RSS is the gated <16 MB number.
- `gfxTestResize` is a test-only additive affordance used by `--smoke` to
  drive the real `WM_SIZE` path; the binding API is otherwise unchanged.

## Fix round 2

Status: **DONE**. Base for this round: `20e2b1d7`.
- Code fix commit: `b9583012` (WM_SIZE via WndProc + 1:1 client blit).
- Report commit: `docs(sdd): P4-M1 fix round 2 report` (this file).
- `b83df7e9` / `41dca492` / `422dfa92` / `20e2b1d7` were not amended.

### Open Important 5 — WM_SIZE via WndProc

`WM_SIZE` is SENT, so the poll loop can never see it in `PeekMessageA`. Z98
cannot define a `stdcall` callback (`extern "stdcall" fn` with a body is treated
as an extern declaration; `export fn` is cdecl), so the callback lives in a
small C shim:

- `sf/src/include/zig_gfx_wndproc.c` owns `z98_gfx_wndproc` (stdcall). It
  records `WM_SIZE` client `width/height` + `resize_pending` and
  `WM_CLOSE`/`WM_DESTROY` in C globals, then forwards every message to the
  default-proc address installed by the PAL. It references no user32 symbol
  itself, so non-GUI no-CRT programs gain no import.
- `cross_nocrt.sh` gained an additive `EXTRA_CSRC` hook (default empty) that
  compiles the shim with the same flags and links its object. Existing callers
  are unchanged when unset. The GUI tier sets
  `EXTRA_CSRC=sf/src/include/zig_gfx_wndproc.c`.
- `std_gfx_pal.zig` installs the WndProc via
  `z98_gfx_wndproc_addr()` / `z98_gfx_set_defproc(DefWindowProcA)` at
  `gfxOpen`; `gfxPollEvent` takes the pending client size, recreates the
  offscreen surface, updates `cols/rows`, and emits the resize Event.
- **Real-resize proof:** `gfxTestResize` calls `AdjustWindowRect` +
  `SetWindowPos` on the actual window (no posted `WM_SIZE`). `--smoke` performs
  two real resizes; Windows SENDs `WM_SIZE` to the WndProc each time.

Window log (verbatim):

```
RESIZE 79x28 px=632x453        <- real WM_SIZE during CreateWindowEx
present 1:1 client=632x453 back=632x453 dest=(4,23)
RESIZE 70x22 px=560x352        <- real SetWindowPos resize #1
present 1:1 client=560x352 back=560x352 dest=(4,23)
RESIZE 100x37 px=800x592       <- real SetWindowPos resize #2
present 1:1 client=800x592 back=800x592 dest=(4,23)
```

### New Important — 1:1 client present

`endFrame` now uses `GetClientRect` plus `ClientToScreen`, passes a destination
rect in **screen coordinates**, and a source rect of the back-buffer client
region (`0,0..client`). The old NULL/NULL `Blt` (which stretched the resized
back across the primary) is gone. The log line above records the client→back
identity.

Screenshot evidence from the tier:

```
shot.png  : full 1024x768, mean/stddev/colors 0.08258 / 0.170868 / 124
            non-black trim bbox = 560x352+4+23
shot2.png : full 1024x768, mean/stddev/colors 0.199762 / 0.187578 / 124
            non-black trim bbox = 800x592+4+23
```

The non-black bbox exactly equals the client size (560x352 and 800x592) at the
client screen origin (4,23): no stretch. (The demo paints the whole client with
palette index 8 so the bbox is observable; this does not change the ASCII
golden.)

### Minors

- Numpad VKs `0x60..0x69 -> '0'..'9'`; `0x6A..0x6F -> '*','+','-','-','.','/'`
  in `virtualToChar`, and the range is in `isCharKey`.
- The report import-table block was updated to the real current imports
  (`BitBlt`, `CreateBitmap`, `CreateCompatibleBitmap`, `CreateCompatibleDC`,
  `DeleteDC`, `GlobalSize`, `DestroyWindow`, `UnregisterClassA`,
  `AdjustWindowRect`, `ClientToScreen`, `GetClientRect`, `SetWindowPos`; no
  `PostMessageA`).
- `cross_nocrt.sh` keeps empty-default `EXTRA_CSRC`/`EXTRA_LIBS`, so the hello
  no-CRT build still links/imports exactly as before (rechecked: `TIER` import
  gate PASS, KERNEL32 only).

### Fix-round 2 evidence (two deterministic tier runs)

Run A and run B: both rc 0, **20 passed / 0 failed**, `TIER_GFX PASS`.

```
Z98 compile max RSS < 16 MB (6180 kB / 5896 kB)
check_win9x_imports.sh 9x PASS (no MSVCRT.DLL)
wheel mapping 120->3, -240->-6
runtime RSS (Wine-hosted): 17212 kB / 17324 kB
grid.txt md5 ef5f8632fa1212a792020cbe1352e0f5 (unchanged)
real window resizes SEND WM_SIZE -> 70x22/560x352 and 100x37/800x592
1:1 client present after both resizes (client==back, screen dest)
screenshot 1 (560x352) mean/stddev/colors 0.08258 / 0.170868 / 124
screenshot 2 (800x592) mean/stddev/colors 0.199762 / 0.187578 / 124
```

`git diff --check` is clean. The golden was not regenerated (ASCII cell output
did not change). The `--smoke` `RESIZE 64x20 px=512x320` line in the headless
run is the memory-mode synthetic resize; the window run uses only real WM_SIZE
events.

### Fix-round 2 concerns

- The C WndProc shim is a build dependency for std_gfx consumers: the GUI link
  now needs `EXTRA_CSRC=sf/src/include/zig_gfx_wndproc.c` in addition to
  `EXTRA_LIBS`. This is the only way to define a stdcall callback without
  changing the compiler emitter (which would rotate the seed fixed point).
- The 800x600 request lands at 800x592 client under Wine's window metrics
  (100x37 cells); the actual client size is what the tier and report record.
- Runtime RSS remains Wine-hosted and recorded, not gated.
