# undersanded M9 — pixel tier — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The art-mode renderer: `std_gfx_px` (16bpp 565 windowed sibling module), bitmap font atlas, bars with dotted red zone + inline numerics, dirty-rect widget rendering, surface-lost recovery — a full fight rendered in art mode with terminal/z9edit goldens unchanged.

**Architecture:** `std_gfx_px` (in `sf/src/`, the one std exception beyond M1) shares std_gfx's window/pump but never touches the cell contract. **Vtable truth = the typed ddraw vtable in `sf/src/std_ddraw_pal.zig:199-301`** (Lock :277, Unlock :284, Restore :279, Blt :257 typed) — the z9gb *probe* has no vtables. `std_gfx_pal.zig:435-462` `Lock`/`Unlock`/`BltFast` are `fn() void` placeholders and **must be typed before sharing** (spec §23.1: sibling module, not a fork — z9edit goldens byte-identical is the acceptance test). `render_art.zig` implements the §27 layout (640×480 fixed) over `Widget[64]` with dirty rects; sprites arrive M10 — this milestone draws with `gfxPxFill` rectangles + font glyphs as stand-ins.

**Tech Stack:** Z98 → C89 `-fsafe`; DirectDraw7 windowed (`DDSCL_NORMAL`), offscreen 16bpp 640×480, per-sprite 256-entry u16 LUT; GDI `StretchDIBits` fallback; bitmap font 95 glyphs 8×16 (period ROM, public domain).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §23.1 (px tier API + PAL notes incl. present contract), §26 (presentation modes), §27 (render engine: widgets, bars, text, layout), §28 (Event.px/py hit-testing), §29 (tween accumulator — visual only), §34 (z9edit golden row), §35 (perf target), §36 (M9 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m08-t1-content-plan.md`. NEXT: `2026-11-12-undersanded-m10-assets-pipeline-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. std changes confined to `sf/src/std_gfx_px.zig` **plus** the smallest possible additions to shared headers — the cell contract, themes, glyph atlas, `gfxDumpGrid` untouched. **Depth fallback cascade:** desktop <16bpp (incl. 256-colour 8bpp) → refuse art mode → terminal mode; GDI `StretchDIBits` (24-bit DIB) covers DD-present failure at ≥16bpp only. Query `GetPixelFormat` masks at open (565 vs 555 skew). `DDERR_SURFACELOST` → `Restore()` → re-lock → **full widget repaint** (VRAM content gone). Software clip before locked-pixel writes. COM calls through `extern "stdcall"` fn-pointer types with convention-qualified casts; slot order copied from `std_ddraw_pal.zig`'s typed table, unused slots preserved (wrong order fails silently — spec §37 risk). **Windowed present contract (spec §23.1, binding):** `Blt` to primary — **never `BltFast`** (it ignores clippers; `std_ddraw_pal.zig:9-11` bans it) — dest rect in screen coords (`ClientToScreen`, `std_ddraw_pal.zig:636-654`), clipper on primary, `DDBLT_WAIT`. Blit/Fill require held lock; Present requires surface **unlocked** (`DDERR_SURFACEBUSY` otherwise). Offscreen = `DDSCAPS_SYSTEMMEMORY` (never VRAM — 4 MB cards).

## File Structure

- `sf/src/std_gfx_px.zig` — API exactly spec §23.1 (`gfxPxOpen/Lock/Unlock/Blit/BlitPart/Fill/Present`, `Sprite`/`Surface`, `PxError`).
- `examples/z98/undersanded/render_art.zig` — Widget system (§27), bars, layout, hit-test rects, screen shake hook (M12 uses it).
- `examples/z98/undersanded/font8x16.zig` — glyph atlas data (95 glyphs).
- `examples/z98/undersanded/tween.zig` — `tweenAdvance` (§29 raw-tick accumulator, TWEEN_MS 180).
- `examples/z98/undersanded/tests/px_test.zig`, `tests/tier_m9_px.sh`, `tests/run_px_probe.sh` (pattern after z9gb `run_ddraw_probe.sh`).

## Review Focus

- COM vtable slot order wrong → silent failure on real hardware, maybe not under Wine → minimal blit probe first (Task 1) and slot list copied from `ddraw.h` with review.
- Surface-lost path never triggered in CI → `gfxTestFocus`-style injection or forced `Restore()` exercise in the tier (spec §34 row).
- Bar math off-by-one at empty/full (fill width `hp*bar_w/max_hp`, red zone `clamp((25-margin)*bar_w/max_hp,0,bar_w)`) → pixel-level unit tests on the widget draw helpers.
- Color-blind safety regressions (red zone must keep 1px dotted border **and** inline numeric `HP 42/70`) → golden asserts both markers present in the bar widget.
- Tween accumulator using `delta_ms` division (never advances on short intervals) → unit test with equal `highRes()` samples.

---

### Task 0: Preflight

- [ ] Run z9edit tiers green as baseline (byte-diff goldens saved). Copy the vtable slot discipline from **`sf/src/std_ddraw_pal.zig:199-301`** (typed, proven); type the `std_gfx_pal.zig` Lock/Unlock/BltFast placeholders as part of Task 1.

### Task 1: `std_gfx_px` open/lock/fill/present (blit probe)

**Interfaces:** exactly spec §23.1 signatures. `gfxPxOpen(title, 640, 480)`; `gfxPxLock` → `Surface{pixels, pitch, w, h}`; `gfxPxFill(x,y,w,h,rgb565)`; `gfxPxPresent(x,y,w,h)` (contract above); plus **headless memory target** `gfxPxOpenMemory()` → draw helpers operate on a plain `Surface` with no window — ALL unit tests and goldens run through it (native, the gate).
- [ ] Minimal probe (`run_px_probe.sh`): open, lock, fill a 640×480 test pattern (ramp 0→15 columns), present, exit. PASS on host software path (gate) + Wine run recorded as evidence only; slots reviewed against `std_ddraw_pal.zig`. Commit `feat(std): std_gfx_px open/lock/fill/present`.

### Task 2: Blit + LUT + surface-lost

**Interfaces:** `Sprite{w,h,idx,lut,key}`; `gfxPxBlit`/`gfxPxBlitPart` convert indexed→565 via 256-entry u16 LUT at blit; key byte skipped; software clip. Handle `DDERR_SURFACELOST` → `Restore()` → re-lock (expose `pub fn pxRestore(g) bool`).
- [ ] Unit tests: LUT conversion (index→565 exact values from palette anchors), key skip, clip edges (negative dx/dy), partial blit rect. Forced-restore exercise in tier. PASS. Commit `feat(std): std_gfx_px blit + surface-lost recovery`.

### Task 3: Font + bars + widgets (`render_art.zig`)

**Interfaces:** `Widget{x,y,w,h,kind,dirty,a,b,c,text_off,sprite}` flat (R1); `pub fn layoutFight(s: *GameState) void` (§27 geometry: HUD 32, sprite+stats 200, log 140, buttons 56); `pub fn renderDirty(g, s)` — mark → lock → repaint dirty rects only → unlock → present coalesced; bar draw helpers per §27 (fill, red zone with **1px dotted border**, inline numerics, coupling tags only when live); `tweenAdvance` per §29.
- [ ] Unit tests: bar widths at hp=0/half/max with margin 10/25; red-zone clamp; dotted border present (golden of a bar widget dump); dirty-rect **area** after one action ≈15% of screen (assert area bounds — not rect count); coalescing = bounded rect list (max 32, merge when bounding boxes overlap/touch, overflow → full-frame present); pitch-padded surface case (pitch > w*2) covered; tween equal-samples no-advance. Implement. PASS. Commit `example(undersanded): art widgets, bars, font, dirty rects`.

### Task 4: Art fight screen + hit-testing + mode fallback

- [ ] Wire art fight screen (fill-rect stand-ins for the M10 sprite slot), mouse `Event.px/py` hit-tests on button rects → same Action as hotkeys (§28), `gfxSetFixedSize(640,480)` (G7), `gfxPxPresent` per coalesced rect (G8). Desktop depth <16bpp → terminal fallback (log reason). GDI fallback path builds 24-bit DIB + `StretchDIBits` (≥16bpp present failure only). Commit `example(undersanded): art fight screen + hit-testing`.

### Task 5: `tier_m9_px.sh` + goldens

- [ ] Implement `--perf`: when enabled, append frame-timing percentiles to `errors.log` (consumed by M16). PASS. Commit `example(undersanded): --perf timing log`.
- [ ] Tier: px unit tests + `--dump-grid` terminal goldens **byte-identical to M8** + z9edit `tier_edit.sh`/`tier_edit_gui.sh` **byte-identical** + surface-lost exercise + **art frame golden = pre-present in-memory framebuffer dump checksum** (software compose, native — never post-present readback) + probe harness run as SLOW evidence. Non-vacuous. Run PASS. Commit `example(undersanded): M9 pixel tier`.

**Gate:** fight renders in art mode; terminal + z9edit goldens unchanged (acceptance for the std work); dirty-rect path exercised.

### Task 6: Next-milestone amendment review (M10)

- [ ] Read `2026-11-12-undersanded-m10-assets-pipeline-plan.md`; judge `Sprite`/LUT shape vs `.ZSP` decode (§30) — decoder must produce exactly `Sprite`. Amendment or "no amendment needed" in NOTES.md.
