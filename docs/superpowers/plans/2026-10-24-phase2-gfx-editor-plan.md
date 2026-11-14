# Phase 2 Project 4 — Minimal GUI Layer + `z9edit` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `std_gfx` (minimal windowed DirectDraw GUI layer, Win9x, COM via `extern "stdcall"` vtables) with a standalone demo proving it, then `z9edit` — a single-file Z98 source editor with syntax colors, declared-identifier colors, bracket balance, selection, and undo.

**Architecture:** One graphics backend (Win9x: Win32 window + windowed DirectDraw, system-memory offscreen surface, glyph cache). Layer-first: `std_gfx`/`std_gfx_pal` (std modules, PAL-split like `std_file`) + `gfx_demo` prove the layer; `z9edit` splits into a headless core (gap buffer, per-line lexer, ident scan, bracket match, undo, error table — native Linux testable) and a thin `ui.zig` shell that consumes `std_gfx` events. GUI shell CI coverage = `--smoke` scripted events through the same app handler + a headless `grid.txt` golden + a Wine/Xvfb window+screenshot evidence tier; interactive fidelity is operator Win98 hardware.

**Tech Stack:** Z98 (`sf/src/std_gfx.zig`, `sf/src/std_gfx_pal.zig`, `examples/z98/gfx_demo/`, `examples/z98/z9edit/`); existing `extern "stdcall"` use-site-cast convention (QUICK_REF); `std_arena`, `std_file`, `std_str`, `std_mem`, `std_time`; no-CRT mingw build via `scripts/win32_cross/cross_nocrt.sh`; Xvfb + Wine for the bonus window tier.

**Spec:** `docs/superpowers/specs/2026-10-24-phase2-gfx-editor-design.md` (binding; §7 contracts, §12.1 settlements, §13 decisions). Umbrella: `docs/superpowers/specs/2026-10-24-phase2-toolchain-design.md` (P4 tags). **T0-pre evidence:** `.superpowers/sdd/2026-10-24-phase2-gfx-editor-plan/t0-pre-report.md` (Win32+DDraw+GDI window/screenshot smoke, 2026-10-27) — its findings are already folded into the constraints below.

## Global Constraints

- Z98 subset; **no compiler-pipeline change at all** — P4 is user-side code plus two new std modules. `z9dbg` (P3) untouched.
- One backend: **Win9x DirectDraw windowed (`DDSCL_NORMAL`)**; no Linux GUI backend (Wine is the Linux story, decision `ef95c21b`); no exclusive/fullscreen mode.
- **T0-pre-pinned DirectDraw interface:** `DirectDrawCreate` returns the **v1 `IDirectDraw`**; the layer must `QueryInterface(IID_IDirectDraw7)` (link `-ldxguid`) and use `IDirectDraw7`/`IDirectDrawSurface7`. Passing a 124-byte `DDSURFACEDESC2` to v1 `CreateSurface` fails `E_INVALIDARG 0x80070057` (confirmed on Wine). Present = `Blt(primary <- offscreen, DDBLT_WAIT)`; **no `Flip`, no `DDSCAPS_BACKBUFFER`**. Do **not** call `CoInitialize` (not needed).
- v1 feature set is exactly spec §7.2: single file, colors incl. declared-identifier + `error[NNNN]` status message, bracket match + `unbalanced <ch> from line N`, selection by drag, Ctrl+S save, Ctrl+Z undo (**no redo**), click-to-cursor, wheel = 3 lines/notch (**no scrollbar**), CRLF/LF preserved. **Clipboard is IN** (operator ruling 2026-10-24): Ctrl+C/Ctrl+X/Ctrl+V (Win32 `CF_TEXT` + internal copy-buffer fallback, spec §7.2), Shift+arrows selection extension, Ctrl+A select-all, type-over-selection (typing/Backspace/Delete with an active selection replaces it). **No** tabs, no completion, no search, no compile-from-editor.
- Small additive helpers in `sf/src/std_str.zig` / `sf/src/std_mem.zig` are **allowed** when a gap bites (operator ruling 2026-10-24) — additions only, no rewrites.
- `std_gfx` API (binding): `Color = u8` (0..15 app-palette indices, tuned dark palette; cell coordinates everywhere); `EventKind` = `key_down, key_up, mouse_move, mouse_down, mouse_up, wheel, resize, close`; `Event` = `{ kind, ch: u8, code: u16 (VK_*), x: u32, y: u32, button: u8 (0=left), wheel: i32, cols: u32, rows: u32, mods: u8 }` (`mods` bit0 = Shift, bit1 = Ctrl; for `key_down` with modifiers `ch` carries the unmodified character, e.g. `Ctrl+S` → `ch='s'`, `mods=0b10`); functions `gfxOpen(title, cols, rows) GfxError!*Gfx`, `gfxPollEvent(g, ev) bool`, `gfxBeginFrame`/`gfxEndFrame`, `gfxClear(bg)`, `gfxFillRect(x,y,w,h,fg,bg)`, `gfxDrawText(x,y,s,fg,bg)`, `gfxCharSize(w,h)`, `gfxBufferSize(cols,rows)`, `gfxClipboardSet(g, s) bool`, `gfxClipboardGet(g, arena) ?[]u8`, `gfxClose(g)`. **Test-surface additions:** `gfxOpenMemory(cols, rows) GfxError!*Gfx` (backend-free cell grid, no window) and `gfxDumpGrid(g) []u8` (row-major ASCII snapshot) — these two exist only to make the headless `grid.txt` golden deterministic. Drawing primitives otherwise stay exactly clear, fill-rect, text-at-cell, present-blit, metrics (spec §12.1). PAL calls COM only through hand-written vtable structs with the convention use-site cast.
- **16 MB applies to BOTH** the editor runtime and the compile of it (operator 2026-10-27). Consequence: `z9edit` must `@import` `std_gfx.zig` (and each std module) **directly** — never `@import("std")` / the `std.zig` barrel (barrel is 13 modules and would balloon the compile graph). Measure (a) compile max RSS of `z9edit/main.zig` and (b) editor runtime RSS; both target **< 16 MB**. Hard runtime ceiling stays `ulimit -v 32768`.
- **GUI build = no-CRT.** Local `gfx_demo`/`z9edit` binaries are built with `scripts/win32_cross/cross_nocrt.sh` (`-nostdlib -DZIG_NO_CRT`; links emitted `zig_runtime.c`, `zig_pal.c`, `zig_nocrt.c`, `c_exit.c`), so the 9x gate sees **no `msvcrt.dll`** and no MinGW-CRT KERNEL32 `*W`/DBCS imports. Shipped static-CRT scripts (`build_target_crt.bat`, `build_owc_crt.bat`) remain operator-run. If a needed libc symbol is missing from `zig_nocrt.c`, add it additively (T0-pre report "Symbols/DLLs").
- **Import gate:** extend `scripts/win32_cross/check_win9x_imports.sh` with closed-world `DDRAW_ALL` (`DirectDrawCreate`), `GDI32_ALL`, `USER32_ALL`, seeded from the T0-pre probe: GDI32 = `GetStockObject SelectObject SetBkMode SetTextColor TextOutA`; USER32 = `CreateWindowExA DefWindowProcA DispatchMessageA FillRect LoadCursorA PeekMessageA PostMessageA PostQuitMessage RegisterClassA SetForegroundWindow ShowWindow TranslateMessage UpdateWindow`. After the real binaries build, add **only** the symbols they actually import (verify with `i686-w64-mingw32-objdump -p`). Never add `msvcrt.dll` to the 9x profile. Run `check_win9x_imports.sh <exe> 9x` on every `-osw` binary.
- **Xvfb bonus tier (evidence, not a gate):** `lin_bin/instructions.txt` lists the X packages. Run the real window under `Xvfb :77 -screen 0 1024x768x24 -nolisten tcp` + Wine; key off a flushed `READY` sentinel, wait ~0.5 s, `import -window root` (window lands at 0,0; crop `640x480+0+0`), then let the app exit and `wineserver -k` before killing Xvfb (avoids the harmless `X connection broken` lines). Pixel output is Wine/font-specific — **not** a pass/fail gate.
- Headless core gates run **native on Linux** (QUICK_REF recipe); GUI gates run under Xvfb+Wine where installed, else an explicit `operator-hardware` line in the report — **never silently skipped**.
- Declared-ident table rebuilds at load, at save, and after ≥ 2 s edit-idle (`std_time.now_ms` in the event loop) — never on the keystroke path.
- **Gates per task (minimal; no compiler-source change):** T1 `tier_gfx.sh` (headless `grid.txt` golden + import gate + Xvfb bonus); T2 `tier_edit.sh` (six core tests, 3× determinism); T3 `tier_edit_gui.sh` (`--smoke` save-byte golden + import gate + Xvfb bonus + operator-hardware checklist). **Closeout only:** `verify_stdlib.sh` + `run_crosscheck.sh` + examples 26/26 sanity. **No corpus / goldens / 8 pins / markers re-run** (no compiler source changed).
- Seed model: reference compiler rebuilt per `release/seed/`; rotate at closeout via `scripts/seed/archive_seed.sh`. **P4 adds no compiler source change**, but the fixed point is **already moved** relative to seed v123: the leaf-tail cleanup `60e3a916` (`sf/src/lower.zig`, −953 lines) postdates v123 `b95467b0`. Verified on a fresh build: `hop1 == hop2 == 2fc64ffedb3ba5f4e8adf35896729e54`. **P4 rotation is std-payload + that pending cleanup**: `lib/` 47 → **49** (`std_gfx.zig`, `std_gfx_pal.zig`), self-emission fixed point recorded as **`2fc64ffe…`** (not `a567926c…`). The copy lists in `scripts/seed/build_from_seed.sh:146` and `scripts/seed/archive_seed.sh:162` (plus their comment blocks `archive_seed.sh:40-44`, `:319-333`) must gain the two files; `archive_seed.sh:167` computes `LIB_COUNT` dynamically. Seed era **v123 → v124**.
- Commits: `feat(std_gfx): … (Phase2 P4-Mn)` / `example(z9edit): … (Phase2 P4-Mn)` / `test(tier): … (Phase2 P4-Mn)` / `docs(std_lib|manuals): …` / `chore(seed): rotate (Phase2 P4)` / `docs(sdd): …`. No push; `run.err` untouched.
- STOP-present on any contract change or ambiguity.

## Review Focus

1. **Wine/Xvfb smoke is not hardware proof** — tier output and every report must separate `wine:` evidence from `operator-hardware` (checklist, "not measured" honesty). Test: Task 3 Step 3 report lines.
2. **DDraw interface version** — a v1/v7 mix fails silently or with `E_INVALIDARG`. Test: `gfx_demo --smoke`/Xvfb logs `QueryInterface(IID_IDirectDraw7) hr=0x00000000` and `CreateSurface hr=0x00000000` (Task 1 Step 3).
3. **COM vtable slot order** — a wrong slot misbehaves silently. Test: `gfx_demo --smoke` feeds events that exercise clear, text, fill, resize, close through real vtable calls (Task 1 Step 2).
4. **CRLF/LF byte preservation** — load→save with no edits must be byte-identical; inserts use the file's ending. Tests: `buffer_test` `crlf_preserved_noedit`, `lf_preserved`, `crlf_preserved_after_insert` (Task 2 Step 3).
5. **Lexer cross-line state** — block comment / multi-line string spanning lines must color the next lines correctly. Tests: `lexer_test` `block_comment_state_carry`, `multiline_string_state_carry` (Task 2 Step 4).
6. **Undo inverse with multi-byte deletes** — undo restores exact prior bytes; empty stack returns false. Tests: `undo_test` `undo_delete_inverse`, `undo_empty_false` (Task 2 Step 5).
7. **No msvcrt / no barrel** — the built exe passes `check_win9x_imports.sh 9x` with no `msvcrt.dll`; `z9edit` compile max RSS < 16 MB. Tests: T1/T3 gate output + the RSS line in the report.

---

### Task 1: P4-M1 — `std_gfx` layer + `gfx_demo`

**Files:**
- Create: `sf/src/std_gfx.zig` (contract types + glyph cache + cell layout; backend-free; includes `gfxOpenMemory`/`gfxDumpGrid`)
- Create: `sf/src/std_gfx_pal.zig` (Win9x: window class/pump + DirectDraw7 windowed setup + vtable structs + clipboard)
- Create: `examples/z98/gfx_demo/main.zig` (`--smoke N` scripted-event demo; headless grid dump when no window)
- Create: `examples/z98/gfx_demo/tests/tier_gfx.sh` (no-CRT build + import gate + headless grid golden + optional Xvfb window smoke)
- Create: `examples/z98/gfx_demo/tests/golden/grid.txt` (generated once from a verified run, then committed)
- Modify: `scripts/win32_cross/check_win9x_imports.sh` (`DDRAW_ALL`/`GDI32_ALL`/`USER32_ALL` whitelists)
- Modify: `scripts/win32_cross/cross_nocrt.sh` (additive `EXTRA_LIBS` env appended to the link line; GUI tier passes `-luser32 -lgdi32 -lddraw`; default empty keeps every existing caller byte-identical)
- Modify: `scripts/seed/build_from_seed.sh:146`, `scripts/seed/archive_seed.sh:162` (+ comment blocks) — add `std_gfx.zig`, `std_gfx_pal.zig`

**Interfaces:**
- Consumes: `extern "stdcall"` fn-ptr use-site-cast rule (QUICK_REF); `std_arena`; PAL split pattern of `std_file`/`std_file_pal`; `scripts/win32_cross/cross_nocrt.sh`.
- Produces (binding, consumed by Task 3): `std_gfx` API exactly as in Global Constraints — `Color`, `EventKind`, `Event`, `GfxError`, `Gfx` (opaque), `gfxOpen`, `gfxOpenMemory`, `gfxPollEvent`, `gfxBeginFrame`, `gfxEndFrame`, `gfxClear`, `gfxFillRect`, `gfxDrawText`, `gfxCharSize`, `gfxBufferSize`, `gfxDumpGrid`, `gfxClipboardSet`, `gfxClipboardGet`, `gfxClose`. Cell coordinates; `gfxDrawText` handles chars 32..126, other bytes render as `?`.

- [ ] **Step 1: Write `examples/z98/gfx_demo/tests/tier_gfx.sh` (RED).** POSIX sh: build `gfx_demo` with `cross_nocrt.sh` (fresh work dir); assert `check_win9x_imports.sh 9x` passes on the exe and that the DLL list contains `DDRAW.DLL`/`GDI32.DLL`/`USER32.DLL` and **no `MSVCRT.DLL`**; run `gfx_demo.exe --smoke 30 --dump-grid` and compare `grid.txt` byte-for-byte to `tests/golden/grid.txt`; if `Xvfb`+`wine` present, run the windowed smoke (READY sentinel → `import -window root` → screenshot saved under the work dir) and assert exit 0, else print an `operator-hardware` line (never a silent skip). Run — FAIL (no sources / no flags).
- [ ] **Step 2: Implement `std_gfx.zig` + `std_gfx_pal.zig` + `gfx_demo`.** `std_gfx`: opaque `Gfx` holding PAL state + glyph cache (ASCII 32..126, `SYSTEM_FIXED_FONT`, metrics from `GetTextMetrics`); the cell grid and `gfxDumpGrid` work with `gfxOpenMemory` (no window). `std_gfx_pal`: `RegisterClassA`/`CreateWindowExA`/`PeekMessageA` pump + DirectDraw **7** path (`DirectDrawCreate` → `QueryInterface(IID_IDirectDraw7)` → `SetCooperativeLevel(DDSCL_NORMAL)` → primary + offscreen + clipper → GDI text into the offscreen DC → `Blt(primary, ..., DDBLT_WAIT)`); every COM call through a hand-written vtable struct + convention use-site cast; no `CoInitialize`. `gfx_demo`: window `z98 gfx demo`, text grid + fill-rects + software mouse cursor; `--smoke N` feeds a scripted `Event` sequence (click at a cell, wheel +3, `resize`, key `q`) through the **same** app handler the pump uses, paints N frames, prints `READY` once (flushed), `gfxClose`, exits 0.
- [ ] **Step 3: Run `tier_gfx.sh` — PASS.** Generate `tests/golden/grid.txt` once from the verified run and commit it. Record verbatim: build rc, import-gate output (DLL list + no msvcrt), `grid.txt` md5, Xvfb output (`QueryInterface hr=0x00000000`, `CreateSurface hr=0x0`, `READY`, screenshot path/mean/stddev/colors) or the explicit `operator-hardware` line, and compile/run RSS (`< 16 MB` target).
- [ ] **Step 4: Minimal gates.** `git diff --check` clean. No corpus/pins/markers (no compiler source change). Closeout battery is Task 3.
- [ ] **Step 5: Commit** `feat(std_gfx): minimal DirectDraw GUI layer + demo (Phase2 P4-M1)` (layer + demo + gate + seed-script edits + tier in one code commit) + `docs(sdd): P4-M1 report`.

### Task 2: P4-M2 — `z9edit` headless core

**Files:**
- Create: `examples/z98/z9edit/buffer.zig`, `lexer.zig`, `idents.zig`, `match.zig`, `undo.zig`, `errtab.zig`
- Create: `examples/z98/z9edit/tests/buffer_test.zig`, `lexer_test.zig`, `idents_test.zig`, `match_test.zig`, `undo_test.zig`, `errtab_test.zig`
- Create: `examples/z98/z9edit/tests/tier_edit.sh` (builds + runs all six, 3× determinism on the lexer dump, prints compile max RSS)
- Modify (only if a gap bites): `sf/src/std_str.zig`, `sf/src/std_mem.zig` — small additive helpers (operator ruling 2026-10-24), additions only

**Interfaces:**
- Consumes: Task 1 nothing (core is GUI-free by contract); `std_arena`, `std_file`, `std_str`, `std_mem`, `std_time`.
- Produces (binding, consumed by Task 3):
  - `buffer.zig`: `BufError = error{ReadFailed, WriteFailed, OutOfMemory, TooLarge}`; `GapBuffer` (opaque); `bufInit(arena, cap) BufError!*GapBuffer`; `bufLoad(arena, path) BufError!*GapBuffer`; `bufSave(b, path) BufError!void`; `bufLen(b) usize`; `bufUsesCrlf(b) bool`; `bufDirty(b) bool`; `bufInsert(b, pos, bytes) BufError!void`; `bufDelete(b, pos, count) BufError!void`; `bufByteAt(b, pos) u8`; `bufCopy(b, pos, count, out) usize`; `bufLineCount(b) usize`; `bufLineRange(b, line, start: *usize, len: *usize) void` (content without EOL); `bufOffsetOf(b, line, col) usize`; `bufLineColOf(b, pos, line: *usize, col: *usize) void`. `bufSave` clears dirty and preserves `bufUsesCrlf` for every emitted ending.
  - `lexer.zig`: `TokKind = enum(u8){ plain, keyword, builtin, errcode, string, comment, number, type_name, ident, punct }`; `Token = struct{ kind: TokKind, start: u32, len: u32 }`; `LexState` (opaque; in-block-comment + in-multiline-string flags); `lexInitState() LexState`; `lexLine(st, line, out: []Token) usize` (token count; state updated across calls); `lexErrCodeAt(line, col) u32` (0 when col is not inside `error[NNNN]`).
  - `idents.zig`: `IdentSet` (opaque); `identScan(arena, b) BufError!*IdentSet` (collects `const`/`var`/`fn` declaration names); `identHas(set, name) bool`.
  - `match.zig`: `Unbalance = struct{ ch: u8, line: usize }` (1-based line); `matchPairAt(b, pos, mate: *usize) bool`; `matchUnbalanced(b, out: *Unbalance) bool`.
  - `undo.zig`: `Undo` (opaque); `undoInit(arena) *Undo`; `undoRecordInsert(u, pos, bytes) BufError!void`; `undoRecordDelete(u, pos, bytes) BufError!void` (caller passes bytes via `bufCopy`); `undoApply(u, b) bool` (applies the inverse of the top record; false when empty).
  - `errtab.zig`: `errtabMessage(code: u32) ?[]const u8` (const table seeded from `sf/src/diagnostics.zig` codes 3000..3076+; unknown → `null`).

- [ ] **Step 1: RED — write `tier_edit.sh` + the six test files' assertions.** Each test binary prints `ok - <case>` / `FAIL - <case>` per case and exits non-zero on any failure. Cases (names binding): `buffer_test`: `insert_delete_roundtrip`, `line_index_after_insert`, `offset_linecol_roundtrip`, `crlf_preserved_noedit`, `lf_preserved`, `crlf_preserved_after_insert`, `load_missing_error`; `lexer_test`: `keyword_string_comment_number`, `block_comment_state_carry`, `multiline_string_state_carry`, `builtin_and_type`, `errcode_token`, `errcode_at_col`; `idents_test`: `decl_const_var_fn_collected`, `use_without_decl_not_collected`; `match_test`: `pair_simple`, `pair_cross_line`, `nested_ok`, `unbalanced_opener_line`, `unbalanced_closer`; `undo_test`: `undo_insert_inverse`, `undo_delete_inverse`, `undo_empty_false`; `errtab_test`: `known_code_message`, `unknown_null`.
- [ ] **Step 2: Run `tier_edit.sh` — FAIL** (missing modules).
- [ ] **Step 3: Implement `buffer.zig`** per the Produces signatures; run `buffer_test` — PASS (including the three CRLF/LF cases from Review Focus 4).
- [ ] **Step 4: Implement `lexer.zig` + `idents.zig`**; run `lexer_test` + `idents_test` — PASS (cross-line state cases green).
- [ ] **Step 5: Implement `match.zig` + `undo.zig` + `errtab.zig`**; run `match_test` + `undo_test` + `errtab_test` — PASS (undo inverse cases green; `errtabMessage` seeded from `sf/src/diagnostics.zig`, one table entry per `ERR_30xx` member).
- [ ] **Step 6: Run full `tier_edit.sh` 3×** — all PASS, byte-identical where output compared (lexer dump md5 3×). Confirm zero GUI imports in any core module (grep `std_gfx`/`gfx` = empty in the six modules). Record compile max RSS of a tiny driver that imports the six modules (`< 16 MB` target).
- [ ] **Step 7: Commit** `example(z9edit): headless editor core (Phase2 P4-M2)` (six modules + tests + tier) + `docs(sdd): P4-M2 report`.

### Task 3: P4-M3 — `z9edit` shell on `std_gfx` + closeout

**Files:**
- Create: `examples/z98/z9edit/main.zig`, `examples/z98/z9edit/ui.zig`
- Create: `examples/z98/z9edit/tests/tier_edit_gui.sh` (no-CRT build + import gate + `--smoke` save-byte check + Xvfb window smoke)
- Create: `examples/z98/z9edit/tests/fixtures/edit_smoke.z98` + `edit_smoke.expected` (committed input/expected pair)
- Create: `sf/docs/std_lib/gfx.md`, `sf/docs/std_lib/z9edit.md`
- Modify: `docs/sf/QUICK_REF.md` (§-osw no-CRT gfx recipe + Xvfb/Wine smoke recipe + recorded perf/RSS), manuals truth-up pages if any claim no GUI/editor exists
- Rotate: `release/seed/` v123 → **v124** (std-payload-only: `lib/` 47 → 49, manifest regenerates, fixed point **UNCHANGED** `hop1 == hop2 == 2fc64ffe…`)

**Interfaces:**
- Consumes: Task 1 `std_gfx` API; Task 2 core signatures verbatim.
- Produces: `z9edit` binary; `ui.zig` shell API `UiError = error{OutOfMemory, SaveFailed}`, `UiState` (opaque), `uiInit(arena, g, b, path) UiError!*UiState`, `uiStep(st, ev: *const Event) bool` (false = quit requested), `uiPaint(st) UiError!void`; `main.zig` CLI `z9edit <path>` and test affordance `z9edit --smoke <in> <out>` (load `<in>`, feed the scripted `Event` sequence through `uiStep`, Ctrl+S writes `<out>`, exit 0). **Import `std_gfx.zig` directly — never the `std` barrel.**

- [ ] **Step 1: RED — write `tier_edit_gui.sh` + fixtures.** Assert: `z9edit --smoke edit_smoke.z98 out.tmp` exit 0 and `out.tmp` byte-identical to `edit_smoke.expected`; `check_win9x_imports.sh 9x` on `z9edit.exe` with no `msvcrt.dll`; Xvfb+Wine window smoke (`z9edit.exe edit_smoke.z98` opens, runs the scripted close, exits 0; screenshot saved) when `Xvfb` present, else explicit `operator-hardware` line. Scripted sequence covers: click-to-cursor at a known cell, type chars (declared-ident + keyword coloring exercised in paint), drag-select + delete, `Ctrl+Z` undo, clipboard round-trip (Shift+arrows extend select, `Ctrl+C`, `Ctrl+X`, `Ctrl+V`, `Ctrl+A` select-all, type-over-selection), `Ctrl+S` save. Run — FAIL (no shell yet).
- [ ] **Step 2: Implement `ui.zig` + `main.zig`.** Event map: `code` VK_LEFT/UP/RIGHT/DOWN 0x25..0x28, VK_PRIOR/NEXT 0x21/0x22, VK_HOME/END 0x24/0x23; `Ctrl+S` save, `Ctrl+Q`/close quit, `Ctrl+Z` undo, `Ctrl+C`/`Ctrl+X`/`Ctrl+V` clipboard (`gfxClipboardSet`/`gfxClipboardGet` + internal copy buffer per spec §7.2), `Ctrl+A` select-all, `Shift`+arrows extend selection (`mods` bit0), type-over-selection replaces the selection; wheel = 3 lines; click/drag select (inverted `(anchor,cursor)`); paint = visible lines only via `lexLine` state carry; gutter line numbers; tab display width 8; status bar `line,col` + `unbalanced <ch> from line N` + `error[NNNN]` message via `lexErrCodeAt` + `errtabMessage`; title `z9edit — <basename>` with `*` when dirty; ident table per the 2 s idle rule (Global Constraints). Print `READY` once (flushed) for the Xvfb runner.
- [ ] **Step 3: Run `tier_edit_gui.sh` — PASS** (2× deterministic on `out.tmp`). Record `wine:` evidence and the `operator-hardware` checklist (interactive edit/select/undo/save on real Win98) separately in the report per Review Focus 1.
- [ ] **Step 4: Closeout battery + cost record.** `verify_stdlib.sh` + `run_crosscheck.sh`; examples 26/26; `git diff --check`. Record: `z9edit` compile max RSS and runtime RSS (`< 16 MB` both targets), open-100 KB wall time, keystroke→screen estimate on the test box; era numbers marked `not measured` unless the operator box ran them.
- [ ] **Step 5: Docs.** `sf/docs/std_lib/gfx.md` (API + DDraw7/QueryInterface discipline + COM vtable discipline + Phase 5 reuse note); `sf/docs/std_lib/z9edit.md` (usage, key map, v1 limits per spec §7.2); QUICK_REF recipes + measured numbers; grep manuals for claims that no GUI/editor exists and truth-up any hits (sidecar-map honesty pages are P3's).
- [ ] **Step 6: Seed rotate v123 → v124** via `scripts/seed/archive_seed.sh … --update-changelog` after confirming the two `lib/` copy lists carry `std_gfx.zig`/`std_gfx_pal.zig`; record `LIB_COUNT` 49, new archive/zip md5s, manifest md5, and **fixed point `2fc64ffedb3ba5f4e8adf35896729e54`** (moved by the pre-P4 leaf-tail cleanup `60e3a916`; P4 adds no compiler change) in the changelog + report; verify `build_from_seed.sh` reproduces the archived binary.
- [ ] **Step 7: Commit** `example(z9edit): UI shell on std_gfx (Phase2 P4-M3)`, `test(tier): z9edit GUI tier (Phase2 P4-M3)`, `docs(std_lib): gfx + z9edit pages`, `chore(seed): rotate (Phase2 P4)`, `docs(sdd): P4-M3 closeout report`.

### Task 4: P4-M4 — Theme system (white default, solarized, dark; config + F2)

**Files:**
- Modify: `sf/src/std_gfx.zig` (`Theme` enum + `gfxSetTheme`/`gfxGetTheme`)
- Modify: `sf/src/std_gfx_pal.zig` (three 16-RGB palettes; `setTheme` rebuilds the glyph atlas + brushes; `getTheme`; default white)
- Modify: `examples/z98/z9edit/main.zig` (read `z9edit.ini`/`z9edit.cfg`; `F2` cycles)
- Modify: `examples/z98/z9edit/ui.zig` (bracket highlight readable on light; any role fixes)
- Modify: `examples/z98/gfx_demo/main.zig` (default white; title color)
- Modify: `examples/z98/z9edit/tests/tier_edit_gui.sh` (theme tests)
- Modify: `examples/z98/gfx_demo/tests/tier_gfx.sh` (theme screenshots/evidence)
- Modify: `sf/docs/std_lib/gfx.md`, `sf/docs/std_lib/z9edit.md`, `docs/sf/QUICK_REF.md`
- Rotate: `release/seed/` v125 → **v126** → **v127** (v127 is the shipped seed after the C1 light-theme fix; std payload; fixed point stays `2fc64ffe…`, `lib/` 49)

**Interfaces:**
- Consumes: Task 1 `std_gfx`/PAL; Task 3 `ui.zig`/`main.zig`.
- Produces: `pub const Theme = enum(u8) { white, solarized, dark };`
  `pub fn gfxSetTheme(g: *Gfx, theme: Theme) bool;` (rebuilds the atlas; false on failure, keeps the old theme)
  `pub fn gfxGetTheme(g: *Gfx) Theme;`
  Config: `theme=white|solarized|dark` (case-insensitive; unknown/missing → white), file `z9edit.ini` then `z9edit.cfg` next to the exe (fallback CWD).
  `F2` cycles white→solarized→dark→white (session-only; does not rewrite the config).

- [ ] **Step 1: RED — theme tests.** `tier_edit_gui.sh`: (a) default (no config) starts white; (b) `z9edit.ini` `theme=solarized` starts solarized; (c) `theme=dark` starts dark; (d) `F2` cycles through all three and back; (e) malformed/unknown config → white, no crash; (f) save-byte golden `974243c9…` unchanged in every theme. Screenshots for white/solarized/dark under Xvfb+Wine. Run — FAIL.
- [ ] **Step 2: Implement the std theme API + PAL palettes.** `std_gfx.zig` passes through; `std_gfx_pal.zig` holds three 16-entry RGB tables (white/solarized/dark), an active theme, `setTheme` releases the old glyph atlas and brushes, rebuilds both for the new palette, and returns false on failure; default white. Keep the 16 role indices.
- [ ] **Step 3: Editor + demo.** `main.zig` reads `z9edit.ini`/`z9edit.cfg` (exe dir, then CWD; `theme=` case-insensitive; unknown/missing → white) at open, applies it, and binds `F2` to cycle. `ui.zig`: bracket-highlight text uses `COL_BG` (index 0; readable on all three); verify status/gutter/cursor/selection on all three palettes. `gfx_demo` uses the default white and adjusts its title color.
- [ ] **Step 4: Run `tier_gfx.sh` + `tier_edit.sh` + `tier_edit_gui.sh` 2× — PASS.** Record screenshots for the three themes; save golden unchanged; import gate no msvcrt; compile RSS <16 MB.
- [ ] **Step 5: Docs.** `gfx.md` (Theme API, palettes, atlas rebuild), `z9edit.md` (config file + F2), QUICK_REF recipe.
- [ ] **Step 6: Seed v125 → v126 → v127** via `scripts/seed/archive_seed.sh … --update-changelog --win9x-zip`; record archive/zip md5s, `lib` 49, manifest md5, fixed point `2fc64ffe…` (unchanged); verify `build_from_seed.sh` reproduces it; update CHANGELOG/QUICK_REF/README/STD_README seed refs. (v126 was superseded by the C1 light-theme fix; v127 is the shipped seed.)
- [ ] **Step 7: Commit** `feat(std_gfx): theme system (white default, solarized, dark) (Phase2 P4-M4)`, `example(z9edit): config theme + F2 cycle`, `test(tier): theme coverage`, `docs(...)`, `chore(seed): rotate v126/v127`, `docs(sdd): P4-M4 report`.
