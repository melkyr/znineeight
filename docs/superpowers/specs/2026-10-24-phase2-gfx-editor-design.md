# Phase 2 Project 4 — Minimal GUI Layer + `z9edit` — Design

**Status:** approved for planning (operator, 2026-10-24).
**Blueprint:** `examples/projects_phase2.txt` §Project 4; `examples/roadmap.txt:28`.
**Scope:** Project 4 only. Project 3 (debugger) is governed by
`2026-10-24-phase2-z98-debugger-design.md`; the umbrella map is
`2026-10-24-phase2-toolchain-design.md`.

---

## 1. Ground truth (verified in the tree, 2026-10-24)

- **No GUI code exists anywhere** in `sf/src` or `examples` — no DirectDraw, no GDI,
  no `CreateWindow`/`RegisterClass`. Win32 windowing is greenfield.
- `sf/src/std_os.zig` is thin (args/env/cwd/exit); its PAL
  (`std_os_pal.zig:17`) already proves `extern "stdcall"` Win32 declarations.
  `std_net.zig:42-72` proves a full `extern "stdcall"` binding surface works.
- Function-pointer types carry a calling convention (`extern "stdcall" fn(...)`),
  and the use-site-cast rule (QUICK_REF §"Calling convention (Win9x)") is the
  sanctioned way to call through them — **the COM vtable path is feasible in Z98
  today**: an `IDirectDraw`-style struct of `extern "stdcall"` fn-ptrs, called at
  the use site with the convention-qualified cast. This is the D3D6 rehearsal.
- The two-backend pattern is established: `examples/z98/z9play/platform/` ships
  `console.zig` (contract) + `console_linux.zig` + `console_win9x.zig` + `*_pal.zig`.
  P4 uses the same shape for `std_gfx` but ships **one** backend (Win9x).
- `sf/src/diagnostics.zig` carries the `ERR_30xx` code enum; messages live with the
  reporters. This is the seed source for the editor's `error[NNNN]` table.
- Std inventory is 46 `std_*.zig` + `std.zig` (QUICK_REF §"Std-module inventory").
  A new `std_gfx` grows the archive `lib/` payload → **the seed rotates even if the
  self-emission fixed point does not move** (rotation protocol, QUICK_REF).
- Dev box: **wine 8.0 + i386 present**; **no DISPLAY, no Xvfb**. GUI smoke under
  Wine needs `xvfb` installed or falls back to operator Win98 hardware.
- Harnesses that already exist: `scripts/win32_cross/cross_build_run.sh`,
  `check_win9x_imports.sh 9x` (QUICK_REF §"Windows (`-osw`) build"), and the
  z9play tier-script convention (`examples/z98/z9play/tests/tier_*.sh`).

## 2. Why

The user writes Z98 programs **on the Win98 box**. Today the only editing story is
notepad. The blueprint's mandate (roadmap line 28) is larger than convenience: the
editor is *"a stress test for your DirectDraw layer"* and forces the string/memory
layer to be ergonomic — it is the 2D rehearsal for the Phase 5 D3D6 game. So this
project ships **two things in order**: the minimal windowed GUI layer first (it must
exist as its own artifact — "we must ensure that"), then the editor built on it.

## 3. Goals

1. **G1 — `std_gfx`, a minimal windowed GUI layer.** Win32 window class + message
   pump, windowed DirectDraw (`DDSCL_NORMAL`, blit to the client area), back buffer,
   glyph cache (ASCII 32..126, fixed pitch), key/mouse/wheel events. A standalone
   demo (`examples/z98/gfx_demo/`) proves the layer **before the editor exists**.
   The COM/`extern "stdcall"` vtable pattern it establishes is reused by Phase 5.
2. **G2 — `z9edit`, a single-file source editor** with the Notepad++ baseline:
   syntax colors, declared-identifier colors, bracket-balance awareness, selection,
   undo, save. Exact feature set in §7.2.
3. **G3 — honest test story.** Editor core (buffer/lexer/match/undo/file) is pure
   logic and gates **native on Linux** (compiled Z98 binaries, no GUI). GUI shell
   gates run under **Wine** (decision `ef95c21b`): launch/paint/input-loop smoke +
   import gate; interactive fidelity is verified on operator Win98 hardware.
4. **G4 — era performance.** Keystroke→screen < 16 ms on a Pentium II-class target;
   open a 100 KB file < 100 ms. Measured and recorded, not waved at (§8.2).

## 4. Non-goals

- No completion popup (operator: color identifiers only), no tabs, no multi-file.
- No scrollbar widget (operator: click-to-cursor + wheel; wheel is one
  `WM_MOUSEWHEEL` handler — cheap, so in).
- No compile-from-editor, no `error[NNNN]` fixing assistance beyond the status bar.
- No fullscreen/exclusive-mode DirectDraw (Phase 5's problem), no D3D, no audio.
- No native Linux graphics backend (X11 etc.) — Wine is the Linux story until a
  user asks (`ef95c21b`).
- No plugin bundle (vim/nano syntax files) — the Z98 editor **is** the convenience
  deliverable.
- No redo (undo only, minimal), no search/find, no print, no multiple cursors.

## 5. Constraints

- Z98 subset (AGENTS.md §1.3); no new language features; no compiler-pipeline
  change at all. P4 adds **user-side** code only (`sf/src/std_gfx*.zig` +
  `examples/z98/{gfx_demo,z9edit}/`), plus **small additive helpers** in
  `sf/src/std_str.zig`/`sf/src/std_mem.zig` when a gap bites (operator ruling
  2026-10-24 — additions only, no rewrites; `verify_stdlib` + crosscheck stay in
  the battery).
- One graphics backend: **Win9x DirectDraw**, windowed. The `gfx` contract is drawn
  so a second backend *could* exist later (z9play pattern) but none is built.
- `std_gfx` is a std module (`sf/src/std_gfx.zig` + `sf/src/std_gfx_pal.zig`),
  PAL-split like `std_file`, installed into `lib/` by the seed scripts like every
  other std module.
- Editor RAM budget: 16 MB target / 32 MB hard ceiling (`ulimit -v 32768`).
  Gap buffer ≈ 1.02× file size; glyph cache and token arrays are fixed/small.
- Debuggee-style build flags for GUI test binaries: `-osw` (mingw) and, where Wine
  runs them, the same `-g -O0 -fno-omit-frame-pointer -m32` story as P3 where
  applicable; the editor itself needs no debug info.
- Seed rotates at closeout (P4 closeout = v120 → **v121**; see umbrella §2).

## 6. Architecture

```
   examples/z98/z9edit/               examples/z98/gfx_demo/
   main.zig  ui.zig                   main.zig  (layer proof, ships first)
   core: buffer lexer idents          |
   match undo errtab                  |
        \                             |
         \_______ std_gfx (contract + glyph cache + layout) ______
                              |
                    std_gfx_pal.zig (Win9x DirectDraw + Win32 window)
                              |
              ddraw.dll / user32 / gdi32 via extern "stdcall" fn-ptrs
```

- **Layer first (M1):** `std_gfx` + PAL + `gfx_demo` — window opens, text grid
  paints from the glyph cache, mouse moves a cursor, wheel scrolls, quit clean.
- **Headless core (M2):** gap buffer, per-line lexer with cross-line state, declared-
  identifier scan, bracket matcher, undo op log, load/save. Zero GUI imports;
  every gate runs as a native Linux binary.
- **Shell (M3):** `ui.zig` wires core to `std_gfx`; paint/scroll/selection/status
  bar; Wine smoke + import gate + battery + docs + seed rotation.

## 7. Contracts (binding)

### 7.1 `std_gfx` layer

- Window: resizable top-level window; back buffer resized on `WM_SIZE`; title
  `z9edit — <basename>` for the editor, `z98 gfx demo` for the demo.
- Rendering model: lock back buffer → draw → unlock → blit to the client area.
  Drawing primitives are the contract; exact surface formats are builder choices.
- Glyph cache: ASCII **32..126**, fixed-pitch font (`SYSTEM_FIXED_FONT`), built
  once at startup as one logical atlas (the Win9x backend uses color+mask
  planes); per-cell metrics come from `GetTextMetrics` at startup
  (self-consistent even when the font differs).
- Color model: **16-color palette indices 0..15** (tuned dark-theme app palette;
  the DirectDraw surfaces are 32-bit) as the layer's color type; which index
  maps to keyword/string/etc. is a builder choice (tests assert token *kinds*,
  never pixels).
- Events delivered to the app: key down/up (char + code), mouse move/down/up,
  wheel (delta in lines), resize, close. Struct shapes are builder choices.
- COM discipline: `IDirectDraw`/`IDirectDrawSurface` style interfaces are structs
  of `extern "stdcall"` fn-ptrs; calls go through the convention use-site cast.
  The layer must never leak a raw vtable to the app — `std_gfx` is the seam.

### 7.2 `z9edit` UX (minimal set — anything not listed is out of v1)

- `z9edit <path>` opens (or creates on save) **one file**. Close box / `Ctrl+Q`
  quits (unsaved = exit without save prompt in v1 — title shows `*` for dirty).
- Save: `Ctrl+S`. Undo: `Ctrl+Z` (no redo). Clipboard (operator ruling
  2026-10-24 — "basic for an editor"): `Ctrl+C` copy, `Ctrl+X` cut, `Ctrl+V`
  paste; `Shift`+arrows extend selection; `Ctrl+A` select-all; typing or
  `Backspace`/`Delete` with an active selection replaces it (type-over). Win32
  `CF_TEXT` via `std_gfx` (`gfxClipboardSet`/`gfxClipboardGet`); copy/cut also
  fill an internal copy buffer, and paste falls back to it when the Win32
  clipboard is empty — this keeps `--smoke` save-byte checks deterministic.
  Navigation: arrows, `PgUp/PgDn`, `Home/End`. Mouse: click-to-cursor,
  drag-select (selection = `(anchor, cursor)`, inverted background),
  **wheel scrolls 3 lines/notch**.
- Syntax colors per line: keyword, builtin (`@`-prefixed), `error[NNNN]`, string,
  comment (incl. multi-line state carry), number, type name, identifier. Line
  numbers gutter. Tab display width 8; file's CRLF vs LF ending is **preserved**.
- Declared-identifier coloring: identifiers matching any `const`/`var`/`fn` name
  declared in the file get a distinct color (file-scope + in-function decls).
- Bracket awareness: cursor adjacent to `()[]{}` inverts the matching pair (cross-
  line ok); unbalanced → status bar `unbalanced <ch> from line N` (N = first
  unmatched opener, 1-based).
- `error[NNNN]` under cursor → status bar shows the human-readable message from a
  hand-maintained const table (seeded from `sf/src/diagnostics.zig` codes).
- Status bar: `line,col` (1-based) + the warnings above. Window title as in §7.1.

### 7.3 Reuse boundary

`std_gfx` ships **before** the editor and is demo-proven standalone. Phase 5
consumes `std_gfx`'s window/input/COM pattern directly; the editor must not fork
it. `z9dbg` (P3) is a terminal UI and is untouched by P4.

## 8. Testing

1. **Headless core (native Linux):** gap insert/delete/line-index invariants; lexer
   category + state-carry cases (block comment, multi-line string, nested brackets);
   identifier scan; bracket cases (unbalanced opener/closer, cross-line, nested);
   undo inverse property; CRLF/LF byte-preservation on load/save; `error[NNNN]`
   table lookup. 3× deterministic where output is compared.
2. **GUI smoke (Wine + xvfb, where installed):** `gfx_demo` opens, paints, handles
   one wheel + one click, exits 0; `z9edit` launches on a fixture file and exits 0
   on close. `check_win9x_imports.sh 9x` on both binaries. If xvfb is missing,
   these gates are operator-hardware and say so in the report (never silently
   skipped).
3. **Cost/perf (recorded):** keystroke→screen and open-100KB numbers on the test
   box; RSS for both binaries under `ulimit -v 32768`.
4. **Standing battery** (P4 touches std payload, not compiler source): full
   `verify_stdlib.sh` + crosscheck; corpus frozen subset + goldens + 8 pins
   **re-measured unchanged** (lib payload rotation precedent: v103, QUICK_REF);
   examples 26/26; `git diff --check` clean.
5. **Hardware:** interactive session (edit, select, undo, save) on real Win98 is
   operator-owned, same honesty rule as P3's Win98 backend.

## 9. Risks

- **R1 Wine ≠ Win98.** Windowed DirectDraw fidelity under Wine is a smoke signal,
  not proof; real proof is the operator's machine. Mitigation: keep the layer's
  surface usage boring (system-memory back buffer + `Blt`), record both results.
- **R2 COM through Z98 fn-ptrs.** First consumer of the use-site-cast rule on real
  vtables. Wrong slot order = silent misbehavior; mitigation: the PAL calls only
  through hand-checked vtable structs, and `gfx_demo` exercises every primitive.
- **R3 Font metrics drift.** `SYSTEM_FIXED_FONT` differs across machines; the cache
  is rebuilt from `GetTextMetrics` per run, so layout is self-consistent.
- **R4 Pentium II latency.** Full-file re-lex on edit would blow the 16 ms budget;
  M2's lexer contract is **per visible line** with cross-line state, ident scan on
  load + on demand only.
- **R5 xvfb absent on CI box.** GUI gates degrade to operator hardware with an
  explicit report line; headless gates carry CI.
- **R6 std payload rotation.** New `std_gfx` rotates the seed for `lib/` alone;
  fixed point must be recorded as UNCHANGED (v103 precedent) to keep the report
  honest.

## 10. Docs / honesty plan

- New page `sf/docs/std_lib/gfx.md` (layer API + COM discipline) and
  `sf/docs/std_lib/z9edit.md` (usage, key map, limits).
- QUICK_REF: `-osw` gfx build/run recipe + xvfb/Wine smoke recipe + the P4 perf
  numbers once measured.
- Manuals: only truth-up pages that claim a GUI/editor does not exist (checked at
  M4-of-P3 style closeout; the debugger-manual honesty work is P3's).

## 11. Milestones (one plan, sequential)

- **M1** — `std_gfx` + PAL + `gfx_demo`: window/pump/back buffer/glyph cache/input,
  standalone proof, Wine smoke + import gate.
- **M2** — `z9edit` headless core: gap buffer, lexer, idents, bracket match, undo,
  load/save; native Linux gates.
- **M3** — `z9edit/ui.zig` shell on `std_gfx`: paint/selection/status bar/scroll,
  Wine + hardware checks, battery, docs, seed rotate v120 → v121, closeout.

## 12. What's left to the builder

Exact `std_gfx` event/primitive struct shapes, the editor's internal module split,
the palette role mapping, the undo log's arena reset policy, and the scripted
harness details are builder choices within §7. Everything else here is binding.

## 12.1 Builder-check settlements (2026-10-24)

- **Drawing primitives (v1)** = editor-minimal set: clear, fill-rect,
  text-at-cell, present-blit, char/buffer metrics. Coordinates are **cells**.
  No general offscreen-bitmap API in v1 — Phase 5 consumes the window/input/COM
  pattern and does its own D3D rendering, extending `std_gfx` as needed (an
  expected later std/seed change, not a v1 gap).
- **Perf (G4) is recorded, not gated.** Headless core runs under
  `ulimit -v 32768`; GUI/Wine RSS recorded where measurable; Pentium II numbers
  come from operator hardware and say "not measured" when unavailable.
- **Declared-ident freshness:** table rebuilt at load, at save, and after
  ≥ 2 s of edit-idle (checked in the event loop via `std_time.now_ms`) — never
  on the keystroke path (R4 budget).
- **CI testing of GUI shell:** `gfx_demo --smoke` and `z9edit --smoke` feed a
  scripted `Event` sequence through the **same** app handler the real pump uses,
  then exit 0 — input-path coverage without Win32 injection; window/paint
  fidelity under Wine is a smoke signal only (R1).

## 13. Decisions log (operator)

1. The editor's real mandate is the **minimal DirectDraw/GUI layer** (roadmap:28);
   the layer ships as its own milestone with its own gates — it must not be
   absorbed into the editor.
2. Linux story = **Wine only** (`.opencode/memory` `ef95c21b`); no native Linux
   graphics backend until a user requests a Linux-native editor.
3. Feature bar = Notepad++ minimum: reserved-word colors, **declared-identifier
   colors only** (no completion popup), bracket-balance awareness.
4. **Click-to-cursor + wheel** (wheel only because it is cheap); **no scrollbar**;
   "again minimal now".
5. Single-file, tabs/multi-file out; undo without redo; no compile-from-editor.
6. `error[NNNN]` messages come from a hand-maintained const table in the editor,
   seeded from `sf/src/diagnostics.zig` — no compiler coupling.
7. The plugin-bundle idea (vim/nano syntax files) is **dropped**; the Z98 editor
   is the convenience deliverable.
8. `std_gfx` is a std module (PAL-split like `std_file`), so Phase 5 reuses it and
   the seed rotates on the `lib/` payload change alone (v103 precedent).
9. **Clipboard family is in v1** (operator, 2026-10-24): `Ctrl+C/X/V`,
   `Shift`+arrows selection, `Ctrl+A` select-all, type-over-selection — "we need
   those commands and clipboard working that is basic for an editor".
10. **Small `std_str`/`std_mem` additions are allowed** (operator, 2026-10-24)
   when a gap bites — additive helpers only; the blueprint's "forces std.str/
   std.mem ergonomic" mandate is thereby satisfiable.
