# undersanded M9 — pixel tier — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The art-mode renderer plus a playable `under.exe`: `std_gfx_px` (16bpp 565 over the shared `std_gfx_pal` window/pump), bitmap font atlas, bars with dotted red zone + inline numerics, dirty-rect widget rendering, surface-lost recovery — dock/map/node stay cell-rendered, a fight renders in art mode, and the whole loop is playable in one window with a <16bpp all-cell fallback.

**Architecture:** `std_gfx_px` is split: **`sf/src/std_gfx_px_core.zig`** is pure (no Windows includes; Surface/fill/blit/LUT/clip/dirty merge/bar math/framebuffer dump **+ the memory-target API**) and is the native gate; **`sf/src/std_gfx_px.zig`** re-exports those symbols and adds the thin Windows path over `std_gfx_pal` (spec §23.1 is literal: it shares `std_gfx`'s window/pump; `std_ddraw_pal.zig:199-301` is only the typed-signature source). `std_gfx` gains one accessor, `gfxNativeState(g) *pal.State` (cell contract untouched); `under.exe` opens `std_gfx` once and `gfxPxAttach(cell)` borrows that window/clipper/pump for the 16bpp surface — one window total. `std_gfx_pal.zig:435-462` `Lock`/`Unlock`/`BltFast` are `fn() void` placeholders and must be typed before use (z9edit goldens byte-identical is the acceptance test). Cell screens are the existing 80×30 `render_term` Screens; the fight presents px on the same window and switches only at fight boundaries. `render_art.zig` implements §27 over `Widget[64]`; sprites arrive M10 — M9 draws with rectangles + font glyphs.

**Tech Stack:** Z98 → C89 `-fsafe`; DirectDraw7 windowed (`DDSCL_NORMAL`), 16bpp 565 `DDSCAPS_SYSTEMMEMORY` offscreen, per-sprite 256-entry u16 LUT; px-only GDI `StretchDIBits` fallback (24-bit DIB); bitmap font 95 glyphs 8×16 (1bpp rows; period ROM, public domain).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §23.1 (px API, module split, present/depth contract, G7/G8), §26 (mode table, one window, --perf), §27 (render engine), §28 (Event.px/py hit-testing), §29 (tween), §33 (errors.log), §34 (z9edit row), §35 (perf target), §36 (M9 row), §38 P27.

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m08-t1-content-plan.md`. NEXT: `2026-11-12-undersanded-m10-assets-pipeline-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** native drivers + `undtool.nix` are the FAST gate; art framebuffer goldens are **core** framebuffer dumps; Wine/DD7/px probe/`tier_edit_gui.sh` are SLOW evidence only, never the gate; operator hardware is M16-only. `<windows.h>` never enters a native test TU.

As prior. std changes confined to `sf/src/std_gfx_px_core.zig`, `sf/src/std_gfx_px.zig` **plus** the smallest additions to `sf/src/std_gfx_pal.zig` (typing `Lock`/`Unlock`/`BltFast`, a px-surface helper, fixed-size window sizing) — the cell contract, themes, glyph atlas, `gfxDumpGrid` untouched. **Depth fallback cascade:** desktop <16bpp (incl. 256-colour 8bpp) → refuse art mode → all-cell terminal mode; px GDI `StretchDIBits` covers DD-present failure at ≥16bpp only. Query `GetPixelFormat` masks at open (565 vs 555 skew). `DDERR_SURFACELOST` → `Restore()` → re-lock → **full widget repaint**. Software clip before locked-pixel writes. COM calls through `extern "stdcall"` fn-pointer types; slot order copied from `std_ddraw_pal.zig`'s typed table, unused slots preserved (wrong order fails silently). **Present contract (spec §23.1):** `Blt` to primary — never `BltFast` — dest rect in screen coords (`ClientToScreen`), clipper on primary, `DDBLT_WAIT`; Blit/Fill require held lock, Present requires unlocked. Offscreen = 16bpp 565 `DDSCAPS_SYSTEMMEMORY`. **New data/atlas code uses explicit `[N]T{...}` literals and no array-returning APIs (D24/D25).** Allowlist additions (`StretchDIBits`, `SetWindowLongA` only if used) are recorded in NOTES and gated by `check_win9x_imports.sh`.

## File Structure

- `sf/src/std_gfx_px_core.zig` — pure pixel core: `Surface`, `Sprite` conversion math, fill/blit/blitPart with clip, dirty-rect merge, bar geometry, framebuffer dump, **memory-target API** (`gfxPxOpenMemory`, `gfxPxDump`, memory `gfxPxFill/Blit/BlitPart`). Native gate.
- `sf/src/std_gfx_px.zig` — Windows wrapper: re-exports the core memory symbols, adds `gfxPxOpen/Attach/Close/Lock/Unlock/Present/PollEvent/WaitEvent`, `Sprite`/`Surface`/`PxError`, `gfxPxTestRestore`.
- `sf/src/std_gfx.zig` — one addition: `pub fn gfxNativeState(g: *Gfx) *pal.State` (used only by `gfxPxAttach`; cell contract untouched).
- `sf/src/std_gfx_pal.zig` — typed `Lock`/`Unlock`/`BltFast`; px 16bpp surface helper; fixed-size window sizing; `GetPixelFormat` used.
- `examples/z98/undersanded/render_art.zig` — Widget system, layout, bars, hit-test rects, art modal/help, screen-shake hook (M12 uses it).
- `examples/z98/undersanded/font8x16.zig` — 95 glyphs, 1bpp 8×16 rows, order ASCII 32..126.
- `examples/z98/undersanded/tween.zig` — `tweenAdvance` (§29 raw-tick accumulator, TWEEN_MS 180).
- `examples/z98/undersanded/render_term.zig` — export `msgLine` (parity), add `blitToGfx(g, screen)` (80×30 cells).
- `examples/z98/undersanded/input.zig` — add `keyFromEvent(ev) ?Key` (same mapping as stdin).
- `examples/z98/undersanded/nav.zig` — add `navRunGfx(g, s)`: gfx events, cell screens, art fight at fight boundaries.
- `examples/z98/undersanded/app.zig` + `main.zig` — `--perf`, mode select/depth fallback, call `navRunGfx`.
- `examples/z98/undersanded/tests/px_core_test.zig`, `tests/px_test.zig`, `tests/art_test.zig`, `tests/tier_m9_px.sh`, `tests/run_px_probe.sh` (pattern after z9gb `run_ddraw_probe.sh`), `tests/fixtures/art_fight.golden` (565 dump checksum), `tests/fixtures/perf_log.golden` (shape only).

## Review Focus

- COM slot order wrong → silent failure on real hardware, may pass under Wine → typed table copied from `std_ddraw_pal.zig`, minimal blit probe first.
- px surface lost/restored but widgets not repainted → force `gfxPxTestRestore` in tier and assert full repaint.
- Bar math at empty/full and `max <= 0` (boss Resolve) → clamp, dotted border + inline numeric in every bar, coupling tags only when live.
- Mode switch at fight boundaries corrupts one renderer's surface/palette → one window, explicit mode owner per frame, cell and px never present the same frame.
- Dirty coalescing wrong → merged rects must cover union, overflow → full-frame, pitch-padded surface.
- Hidden SPD leak in art (`journal_mask`/Sonar) and art modal/help/tool-status parity with `render_term`.

---

### Task 0: Preflight

- [ ] Baseline: `tier_m8_content.sh` PASS and `z9edit/tests/tier_edit.sh` PASS (lexer md5) saved. Record in NOTES: P27 rulings, the pal surface to extend, `Lock`/`Unlock`/`BltFast` placeholder lines, the exact allowlist delta actually needed, D24/D25 guard, and `render_term` art facts (six M8 items). Commit `example(undersanded): M9 preflight`.

### Task 1: Pure px core + memory target (native gate)

**Interfaces:** `Surface{pixels:[*]u8,pitch:i32,w:u32,h:u32}`; `Sprite{w,h,idx,lut,key}`; `pxCoreFill(sf,x,y,w,h,px)`; `pxCoreBlit(sf,dx,dy,s)`; `pxCoreBlitPart(sf,dx,dy,s,sx,sy,sw,sh)`; `pxCoreBar(width,value,max,margin) struct{fill,red}`; `pxCoreDump(sf,out)` (pitch-tight rows); plus the memory-target API `gfxPxOpenMemory(w,h) PxError!*Gfx`, `gfxPxDump(g) []const u8`, `gfxPxFill/Blit/BlitPart` operating on the memory Gfx. All pure, no gfx/pal imports; native tests compile THIS module directly (the Windows wrapper does not exist yet).

- [ ] Native tests: exact 565 LUT values at palette anchors, key skip, negative/partial clip, pitch > w*2, dump row order, bar 0/half/max with margins 10/25, red-zone clamp, `max<=0` guard. Golden: one 320×200 core framebuffer checksum. Commit `feat(std): px core + headless memory target`.

### Task 2: Windows binding — open/lock/fill/present

**Interfaces:** spec §23.1 signatures. `gfxPxOpen(title,640,480)` = standalone fixed 640×480 window (AdjustWindowRect; no resize/scale); `gfxPxAttach(cell:*std_gfx.Gfx) ?*Gfx` borrows the open cell window via `std_gfx.gfxNativeState` and creates the 16bpp 565 SYSTEMMEMORY offscreen + px clipper; types `GetPixelFormat` and follows 565/555. `gfxPxLock` returns `Surface`; `gfxPxUnlock`; `gfxPxFill`; `gfxPxPresent(x,y,w,h)` = `Blt` primary, screen-coord dest, clipper, `DDBLT_WAIT`; `gfxPxPollEvent/WaitEvent` delegate to `pal.pollEvent/waitEvent` (same `Event` incl. `px/py`/focus). px GDI fallback = 24-bit DIB + `StretchDIBits` at ≥16bpp only; <16bpp returns OpenFailed (caller falls back to cell). `pxClose`.

- [ ] Type `std_gfx_pal` `Lock`/`Unlock`/`BltFast`; add px surface helper/fixed-size sizing and `GetPixelFormat`; add only the allowlist symbols used (`StretchDIBits`, `SetWindowLongA` if required) and record them. `run_px_probe.sh`: standalone open, ramp fill, present; native gate = Task 1 core tests; Wine run recorded as evidence. PASS also requires `tier_edit.sh` byte-identical lexer md5. Commit `feat(std): px window binding`.

### Task 3: Sprites, LUT blit, surface-lost

- [ ] `gfxPxBlit/BlitPart` index→565 via 256-entry u16 LUT, key skip, software clip; `pxRestore` on `DDERR_SURFACELOST`; `gfxPxTestRestore` seam for the tier; re-lock and full repaint after restore. Unit tests (core) + forced restore in Task 6. Commit `feat(std): px blit + surface-lost recovery`.

### Task 4: Art fight frame (font, widgets, bars, tween)

**Interfaces:** `Widget{x,y,w,h,kind,dirty,a,b,c,text_off,sprite}` flat; `layoutFight(s:*GameState)` (§27: HUD 32, sprite+stats 200, log 140, buttons 56); `renderDirty(g,s)` mark→lock→repaint dirty→unlock→present coalesced (max 32, merge overlap/touch, overflow full frame); bar helpers per §27; `tweenAdvance(tw,now,freq)` per §29 using `std_time.highRes` (u64 locals only).

- [ ] Font `font8x16.zig`: 95 glyphs, 1bpp 8×16 rows, ASCII 32..126, source/licence line in NOTES.
- [ ] Art fight must render the six M8 facts: hidden `SPD ??` unless journal bit or active Sonar (reveal paths shared with `render_term.speedRevealed`), full tool status line (`TOOL <name> <kind> charge N broken/active`, 80-col safe), mid-fight `?` help (art overlay, or documented terminal fallback), `max_res==0` boss bar guarded, art subdue modal (`SCREEN_SUBDUE`/`_POST`) with same key semantics, `msgLine` exported and shared with a parity test (no duplicated copy table).
- [ ] Tests: bar geometry incl. zero-max, dotted 1px border + inline numeric present, dirty area bounds after one action (~15%, area not count), coalescing order/overflow, pitch-padded, tween equal samples no-advance, message parity. Golden: art fight core framebuffer checksum. Commit `example(undersanded): art fight frame`.

### Task 5: `under.exe` playable loop (cell screens + art fight + fallback)

**Interfaces:** `input.keyFromEvent(ev)*?Key` reuses existing mapping; `render_term.blitToGfx(g,screen)` draws the 80×30 `Screen` through `gfx.gfxDrawText`; `nav.navRunGfx(g,s)` runs the same `navStep` state machine driven by `gfxPollEvent/gfxWaitEvent`, cell-presenting dock/map/node/journal/help and switching to px only while `expedition.isInFight` (and art subdue modal). Mouse `px/py` hit-tests the four fight buttons → same Action. Depth <16bpp → all-cell mode (log reason). `--perf` appends p50/p95/p99 to `errors.log`.

- [ ] `under.exe` opens `std_gfx` once (80×30), `gfxPxAttach` it, and keeps one window for the whole session (`gfxPxAttach` null → all-cell fallback). Keep behaviour identical to `navRun` (keys, pending settle, quit prompt, help overlay owning a key, mid-fight `J` inert). Art mode does not init RNG or advance phases. README documents art/terminal/fallback and `--perf`.
- [ ] Native walk test: scripted event stream dock→map→node→fight→settle→dock renders no crash and matches state; `--perf` writes the pinned shape. Commit `example(undersanded): playable under.exe loop`.

### Task 6: `tier_m9_px.sh` + goldens

- [ ] Tier (native, cwd-independent, nests `tier_m8_content.sh`): `px_core_test` + `art_test` + loop walk; art framebuffer golden (core dump checksum) byte-exact; terminal `--dump-grid --screen fight|dock|map|node|lore|menu|journal|help` **byte-identical to M8**; `tier_edit.sh` byte-identical lexer md5; forced surface-lost full-repaint case; `--perf` shape; any Wine/probe/`tier_edit_gui.sh` runs are SLOW evidence with loud skip. Non-vacuity: mutate a copy of the art golden → tier fails. PASS. Commit `example(undersanded): M9 pixel tier`.

**Gate:** fight renders in art mode; dock→fight→dock playable in `under.exe`; terminal + z9edit goldens byte-identical; surface-lost repaint exercised.

### Task 7: Next-milestone amendment review (M10)

- [ ] Read `2026-11-12-undersanded-m10-assets-pipeline-plan.md`; judge `Sprite`/LUT/`gfxPxBlit` shape vs `.ZSP` decode (§30) — decoder must produce exactly `Sprite` + core-decoded pixels. Amendment or "no amendment needed" in NOTES.md.
