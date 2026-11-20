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
- `examples/z98/undersanded/items.zig`, `text_scan.zig` — quality cut: single owners for tool/material ownership + text/path primitives.
- `examples/z98/undersanded/tests/quality_smells.sh` — grep/LOC gates wired into the tier (Task 8).

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

**Interfaces:** `loop_gfx.zig` (Windows-only) holds `keyFromEvent(ev)*?Key`, `blitScreen(g,screen)`, `navRunGfx(g,px,s,perf_on)` and the gfx boot driver; `nav.zig` exposes pure `bootDraw`/`bootKey` (shared with the stdout `boot` driver), a shared `navIntercept` for help/dock/quit keys, and `drawScreen(g,st,*Screen)` (shared with `drawCurrent`); the four art button rects come from `render_art.zig`. `perf.zig` is pure percentile math/format. Boot menu/lore/save-error render in the window; art only for fight/subdue.

- [ ] `under.exe` opens `std_gfx` once (80×30), `gfxPxAttach` it, keeps one window (`null` → all-cell fallback; `<16bpp` logged). Keys/filters match the console (`input.filterKey` shared: 10/13/space dropped for nav, raw for lore). Mouse `px/py` hit-tests the four fight buttons → same hotkey/Action. Result/tooltip text on cell row 29; art notices in the art frame. Art mode never init RNG or advances phases. `--perf` appends one `perf frames=N p50=..ms p95=..ms p99=..ms` line to `errors.log` on exit. README documents art/cell fallback/controls/`--perf`.
- [ ] **Authorized fix-round scope (review Important):** `tests/tier_m1_std.sh` SLOW `under.exe` evidence is updated to launch → assert window (`xwininfo`) → kill (loud skip without Wine/Xvfb); the old "self-exit" expectation is obsolete because the loop waits for events. Test-only, no product behaviour.
- [ ] Native walk test: scripted event stream dock→map→node→fight→settle→dock renders no crash and matches state; `--perf` writes the pinned shape. Commit `example(undersanded): playable under.exe loop` (fix commit `fix(undersanded): px loop key filter + M1 tier evidence`).

### Task 6: `tier_m9_px.sh` + goldens

- [ ] Tier (native, cwd-independent, nests `tier_m8_content.sh`): `px_core_test` + `art_test` + loop walk; art framebuffer golden (core dump checksum) byte-exact; terminal `--dump-grid --screen fight|dock|map|node|lore|menu|journal|help` **byte-identical to M8**; `tier_edit.sh` byte-identical lexer md5; forced surface-lost full-repaint case; `--perf` shape; any Wine/probe/`tier_edit_gui.sh` runs are SLOW evidence with loud skip. Non-vacuity: mutate a copy of the art golden → tier fails. PASS. Commit `example(undersanded): M9 pixel tier`.

**Gate:** fight renders in art mode; dock→fight→dock playable in `under.exe`; terminal + z9edit goldens byte-identical; surface-lost repaint exercised; quality cut (Tasks 8–9) green with all goldens unchanged.

### Task 7: Next-milestone amendment review (M10)

- [ ] Read `2026-11-12-undersanded-m10-assets-pipeline-plan.md`; judge `Sprite`/LUT/`gfxPxBlit` shape vs `.ZSP` decode (§30) — decoder must produce exactly `Sprite` + core-decoded pixels. Amendment or "no amendment needed" in NOTES.md.

### Task 8: Quality cut — smell removal (mechanical, golden-identical)

**Scope:** no behaviour/output change; every existing golden stays byte-identical. This is the tech-debt cut before M10/M13 extend the same surfaces.

- [ ] **ID registry:** move every `NAV_*`, `SCREEN_*`, `MSG_*`, `OUT_*`, `TOOL_*`, `UNLOCK_*` and `NO_FIGHT` constant into `def.zig`; update all users; delete duplicates in `fight.zig`, `creatures_t1.zig`, `tables_t1.zig`, `nav.zig`. A `tests/quality_smells.sh` check forbids those ids being defined outside `def.zig`.
- [ ] **Ownership owners:** new `items.zig` (`toolOwned`, `toolKind`, `isRigged`, material/part helpers) consumed by `dock.zig`, `expedition.zig`, `tools.zig`, `fight.zig`; delete `dock.toolOwned`, `expedition.toolOwned/toolKind`, and `fight.TOOL_*` copies. Gate: no `fn toolOwned` / `fn toolKind` outside `items.zig`.
- [ ] **Path/text primitives:** one `paths.join` (platform separator) used by `persist.zig` + `save_ux.zig` (`pathJoin83` stays for assets); new `text_scan.zig` owns `stripCR`/`trimSpaces`/`findEq` and one append-int/text helper used by nav/perf/undtool/persist. Gate: no `fn stripCR`/`fn findEq`/`fn join(` outside the owner modules.
- [ ] **Dead/alias sweep:** drop `tables_t1` re-export aliases once imports point at `def.zig` (keep only names still needed), remove `activeSavePath`/`mem_only`/stale comments, fold the duplicated boss line out of `defs_boss_golden`.
- [ ] **Ownership map:** short appendix in NOTES (allowed deps: domain ↛ render; ids only in `def`; content source = Task 9; owners list). `quality_smells.sh` runs from `tier_m9_px.sh`; full nested tier + all goldens byte-identical. Commit `refactor(undersanded): single-source ids, ownership, primitives`.

### Task 9: Quality cut — structural refactor (golden-identical)

**Scope:** no behaviour/output change (goldens byte-identical; any drift = STOP). This is the extension-risk cut: content authored twice, god files, and the view→domain ripple.

- [ ] **Content single-source:** `undtool --emit-fallback` regenerates the compiled fallback rows (`creatures_t1.zig` defs/rules + `tables_t1.zig` tool/upgrade/cosmetic/encounter rows) from `data.z98`; the checked-in output is byte-equal to today's values (content/bind tests stay green). Tier adds `--emit-fallback | cmp` (drift gate). M13 then authors rows once (data file only).
- [ ] **God-file splits:** `render_text.zig` (msgLine/help/modal/copy) out of `render_term.zig`; `fight_rules.zig` + `fight_tools.zig` out of `fight.zig`; `data_scan.zig`/`data_load.zig`; `save_scan.zig`/`save_io.zig`. Behaviour and goldens identical; soft cap ~600 LOC/file.
- [ ] **Render decoupling:** `render_term`/`render_art` stop importing `dock`/`economy`/`save_ux`/`journal`/`data`; `nav` builds a prepared view struct (screen id + rows/bars/notice text) and renderers consume it. This is the ripple-stopper before M10/M11 grow the view. Keep the terminal stdout bytes and art golden identical.
- [ ] Deferred (not M9): `tests/harness.zig` consolidation; `std_gfx_pal`/`std_ddraw_pal` de-duplication.
- [ ] Full nested tier green + all goldens byte-identical + `quality_smells.sh` green. Commit `refactor(undersanded): split render/fight/data/save + decouple view`.
