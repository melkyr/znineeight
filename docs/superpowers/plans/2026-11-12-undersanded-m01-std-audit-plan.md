# undersanded M1 — stdlib audit + gaps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Correct std gap table against the real `sf/src/` surface; close the gaps the game needs (G2–G5, G10, G11, G13); game-side writability probe (G14); two no-CRT link configs (G15 scaffold); trap handler wired; acceptance exe that opens a window, reads a text file, writes a file.

**Architecture:** Audit-first (spec §23: "do not assume"). Minimal std patches, each with unit tests in the std test convention. A skeleton `examples/z98/undersanded/` app proves the platform plumbing before any game code exists.

**Tech Stack:** Z98 (zig1 seed → C89, `gcc -m32`, `-fsafe`), `sf/src/` std modules, Win32 (GDI32/USER32/KERNEL32 only), std_gfx cell tier.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §22 (constraints), §23 (gaps G1–G16 + pixel-tier note), §24 (rules R1–R15), §33 (crash notes), §36 (M1 row).

**Sequence:** PREVIOUS: none. NEXT: `2026-11-12-undersanded-m02-fight-core-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

- Spec is binding; all numbers/tables live there. Example code only in `examples/z98/undersanded/`; std changes only when the spec G-table demands them (M1: G2–G5/G10/G11/G13/G17; M9: `std_gfx_px` + typing `std_gfx_pal` placeholders; M12: `std_audio`) — everything else example-only; compiler defects → STOP-present, minimal workaround, record in `examples/torrent_example_defects.md`).
- Z98 rules R1–R15 (spec §24). Build `-fsafe`, `-W` clean. Capacities fixed at spec §25.1 (`MAX_CREATURES 56`, `MAX_ZONES 12`, …) — never resize in any later milestone.
- Two link configs: `under.exe` (`WINDOWS_GUI`) + `undtool.exe` (`WINDOWS_CUI`), both no-CRT, both pass `check_win9x_imports.sh <exe> 9x` (imports limited to GDI32/USER32/KERNEL32).
- z9edit goldens (`examples/z98/z9edit/tests/tier_edit.sh`, `tier_edit_gui.sh`) must stay byte-identical after any `std_gfx` change — that is the acceptance test for G4/G5/G13.
- Frequent commits; no push. All prior gates stay green forever (regression rule).

## File Structure

- `examples/z98/undersanded/main.zig` — skeleton: init args/cwd/env, trap handler, writability probe, open window (std_gfx cell), read a text file, write a file, exit.
- `examples/z98/undersanded/paths.zig` — exe-dir resolution + writability probe + fallback dir (G14, game-side).
- `examples/z98/undersanded/NOTES.md` — the corrected G-table (Task 1 deliverable) + build recipe.
- `examples/z98/undersanded/build.sh` — two link configs (GUI/CUI), no-CRT.
- `examples/z98/undersanded/tests/tier_m1_std.sh` — acceptance tier.
- `sf/src/std_str.zig`, `sf/src/std_bits.zig`, `sf/src/std_gfx.zig`, **`sf/src/std_gfx_pal.zig`** (the pump/WndProc lives here — `Event.px/py`, focus events, `gfxWaitEvent` cannot be done in `std_gfx.zig` alone), `sf/src/std_os.zig` (audit-driven) — std patches.

## Review Focus

- Silent std_gfx vtable/event breakage: z9edit goldens drift even though tests "look" green → byte-compare goldens in Task 5's step and in the tier.
- Writability probe on a read-only dir: probe must not leave `probe.tmp` behind and must fall back to `C:\WINDOWS\TEMP\UNDERSAN\` exactly (spec §32) → tier runs the probe against `chmod -w` dir.
- `-fsafe` overflow in crc32/table code: use `u32` shifts/XOR only, `i32` for indices → crc32 unit vectors test (known-value check).
- 8.3 path validation: long names rejected, lowercase enforced (spec §30 filename rule) → unit tests for the validator.
- Import surface creep: KERNEL32 extras sneak in via helpers → `check_win9x_imports.sh` in the tier, both exes.

---

### Task 0: Preflight

- [ ] Read `docs/sf/AGENTS.md` + `docs/sf/QUICK_REF.md`; confirm the seed-compiler invocation and std test convention. Run `examples/z98/z9edit/tests/tier_edit.sh` as the green baseline; record the compiler seed id in `NOTES.md`.

### Task 1: Gap audit (G1–G16 vs real `sf/src/`)

- [ ] Inventory `sf/src/` for `std_file`, `std_str`, `std_mem`, `std_bits`, `std_gfx`, `std_os`, `std_debug`, `std_dsound` public surfaces. Rewrite the spec §23 gap table as the **corrected G-table** in `examples/z98/undersanded/NOTES.md`: each G row marked CLOSED-ALREADY / PARTIAL (what's missing) / REAL GAP / GAME-SIDE, with the exact function names found. Confirm G1 closed and G3's true status. Commit `example(undersanded): M1 std gap audit`.

### Task 2: `std_str` gaps (G2)

**Interfaces (consumed by M6 parser):** note: `sf/src/std_parse.zig` already has compiler-internal `parseInt`/`parseUint`/`itoa` — export or game-surface-twin them (G17: M6/M7 need int↔text both ways). `pub fn parseInt(buf: []const u8) ?i32` (decimal, optional leading `-`, `null` on garbage/empty); `pub fn splitOnce(s: []const u8, sep: u8) ?[2][]const u8` (first-separator split, `null` if no separator; if the optional-of-array return shape fails to compile, use a 2-field out-param struct — verify shape first).
- [ ] Unit tests: `parseInt` ("42"→42, "-7"→-7, ""→null, "4x"→null, overflow→null); `splitOnce` (split, no-sep→null, sep-at-edges). Implement in `sf/src/std_str.zig`. PASS. Commit `feat(std): str parseInt/splitOnce`.

### Task 3: `crc32` (G11) + 8.3 path validation (G10)

**Interfaces:** `pub fn crc32(data: []const u8) u32` in `sf/src/std_bits.zig` (256-entry module table, u32 shifts/XOR only — R7-safe). Game-side `paths.zig`: `pub fn pathJoin83(dir: []const u8, name: []const u8, out: []u8) ?[]u8` and `pub fn is83Name(name: []const u8) bool` (lowercase, no spaces, 1–8 + optional 1–3, spec §30 filename rule).
- [ ] Unit tests: crc32 known vectors ("123456789" → 0xCBF43926); `is83Name` ("bg_a.zsp" ok, "fig_mermaid.zsp" reject, "BG_A.ZSP" reject, "a b.zsp" reject); `pathJoin83` truncation guard. Implement. PASS. Commit `feat(std): crc32; example(undersanded): 8.3 path helpers`.

### Task 4: std_gfx wait/focus/pixel-coords (G4, G5, G13)

**Interfaces (consumed by main loop + M9 art mode):** `pub fn gfxWaitEvent(g: *Gfx, timeout_ms: u32) bool` (blocks up to timeout, `true` if an event arrived; `MsgWaitForMultipleObjectsEx` under the existing pump); `Event` gains `px: u32, py: u32` (client-pixel mouse coords); `pub const EventKind.focus_lost` / `focus_gained`; `pub fn gfxTestFocus(g: *Gfx, focused: bool) void` (test hook that synthesizes the transition).
- [ ] Extend `sf/src/std_gfx_pal.zig` (pump/WndProc/event source) and `sf/src/std_gfx.zig` (API/surface). This task also amends `scripts/win32_cross/check_win9x_imports.sh`'s USER32 allow-list to include `MsgWaitForMultipleObjectsEx` (record the amendment in NOTES.md). Unit-level test via existing gfx test harness: event injection yields px/py; `gfxTestFocus(g,false)` produces `focus_lost` and `gfxWaitEvent(g, 250)` blocks without spinning (assert idle CPU not measurable in CI — assert instead that wait returns only on event/timeout via counter). PASS. Commit `feat(std): gfxWaitEvent, Event px/py, focus events`.
- [ ] Acceptance: `examples/z98/z9edit/tests/tier_edit.sh` + `tier_edit_gui.sh` green **and goldens byte-identical** (no golden regeneration allowed). Commit `test(std): z9edit goldens unchanged after gfx event work`.

### Task 5: Writability probe + data directory (G14, game-side)

**Interfaces (consumed by M6/M7/M16):** `pub fn resolveDataDir(out: []u8) []u8` (exe dir via `std_os` module-path helper — add `pub fn modulePath(out: []u8) ?[]u8` to `std_os` if the audit found it missing; strip filename); `pub fn probeWritable(dir: []const u8) bool` (create+delete `probe.tmp`); `pub fn dataDirOrFallback(out: []u8) []u8` (on probe fail: `C:\WINDOWS\TEMP\UNDERSAN\`, create it, return it — mutable files only go there, `data.z98` stays in exe dir per spec §32).
- [ ] Unit test: `probeWritable` true on tmp dir, false on `chmod -w` dir; fallback path string exact; probe leaves no residue. Implement `paths.zig`. PASS. Commit `example(undersanded): writability probe + data dir`.

### Task 6: Two link configs + skeleton main (G15 scaffold) + trap handler

- [ ] `build.sh`: compile Z98→C89→link `under.exe` (`WINDOWS_GUI`, no-CRT) and `undtool.exe` (`WINDOWS_CUI`, no-CRT). `main.zig`: `std.debug.setTrapHandler` with a **pre-allocated** backtrace buffer (spec §32), resolve data dir, open a std_gfx window titled `UNDERSANDED`, read `data.z98`-style test text file from exe dir, write `probe_out.txt`, draw one line of text, exit 0. Commit `example(undersanded): dual link configs + skeleton main`.

### Task 7: `tier_m1_std.sh` acceptance

- [ ] Tier asserts: game-side unit tests run via **native Linux drivers** (`zig1` host build — the gate); the `.exe` CUI run is evidence-only; window-open proof is Wine/operator evidence (spec M1 exit kept, honestly labeled). Both exes build `-fsafe` `-W` clean; `check_win9x_imports.sh under.exe 9x` and `... undtool.exe 9x` pass; skeleton runs headless-safe (CUI path) and writes the file; writability fallback exercised against a read-only dir; crc32/parseInt/splitOnce/8.3 unit tests all green; z9edit goldens unchanged. Non-vacuous. Run PASS. Commit `example(undersanded): M1 acceptance tier`.

**Gate:** `tier_m1_std.sh` green; corrected G-table in NOTES.md; both exes import-clean; z9edit goldens byte-identical.

### Task 8: Next-milestone amendment review (M2)

- [ ] Read `2026-11-12-undersanded-m02-fight-core-plan.md`. Judge whether the std surfaces M2 consumes (`game.zig` purity, rng, consts) are satisfied by M1's actuals. If an amendment is required, STOP-present it; else record "no amendment needed" in NOTES.md.
