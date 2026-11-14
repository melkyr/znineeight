# undersanded M7 — save system — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Text saves with CRC32 integrity, `version=2`/`data_version=2`, the mandatory rollback write path, two slots, first-run lore page, and the save UX rules — proven by round-trip goldens and an exercised rollback.

**Architecture:** `persist.zig` serializes `World` + expedition + score to the §32 section grammar (same key=value family as `data.z98`, reusing M6 scalar parsers), computes crc32 over everything above `[crc32]`, and implements the 6-step write path with step-6 rollback. `save_ux.zig` handles Esc-menu Save availability (not mid-fight), quit prompt, and the first-run page-1 flow.

**Tech Stack:** Z98 → C89 `-fsafe`; std_file (M1: open/readAll/writeAll/rename/remove), `crc32` (M1 std_bits).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §20 (first run), §32 (save format, load checks, write path, slots, UX, data dir), §33 (fatal messages), §38 P10 (grudge mask in save), §36 (M7 row + §34 save rows).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m06-data-loader-plan.md`. NEXT: `2026-11-12-undersanded-m08-t1-content-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. **No autosave, ever.** `version` mismatch and `data_version` mismatch both go to the error screen with fresh / backup slot / quit options — **no auto-migration** (T3). Save contents include every §19/coreid-list field: cycle/phase/location, expedition state + hold, hull, boat axes, tools owned/equipped/charge/broken, money, cosmetics owned/unlocked, journal bits, seen array, per-zone per-species cooldowns, release counts + bonuses + wary flags, lockouts, grudge mask (cleared at run boundary — P10), expertise, boss kills, `boss_variants_seen` mask, score stats, Field Record + Last Run.

## File Structure

- `examples/z98/undersanded/persist.zig` — serialize/load/validate CRC; 6-step write path with rollback; slot management (`save0.dat` + `save.bak`; `save1.dat` manual).
- `examples/z98/undersanded/save_ux.zig` — availability rules, quit prompt, first-run flow (manual page 1 full-screen text → `[Enter] Begin` → world init: 0 coins, 0 journal entries, dock).
- `examples/z98/undersanded/tests/persist_test.zig`, `tests/tier_m7_save.sh`, `tests/fixtures/save_v1_bad.sav`.

## Review Focus

- Rollback step 6 never exercised (the most dangerous silent gap) → inject rename failure at step 5 in the test and assert `save0.dat` restored from `.bak`.
- CRC computed over the wrong range (must exclude the `[crc32]` section itself; include everything above it) → tamper test flips one byte below/above the boundary.
- Save during forbidden states (mid-fight) must grey with reason → UX state tests.
- Partial writes on FAT32: save.tmp must be flushed + re-read + CRC-verified **before** any rename → order test with a mock failing flush.
- Fresh-install init drifting from §20 (must be world init, not an autosave; 0 coins; page 1 shown once) → first-run golden.

---

### Task 0: Preflight

- [ ] Freeze the save grammar in NOTES.md (§32 section list + one key=value line per scalar, arrays as `name=i,i,i`; `[crc32] hash=0x…` last). Reserve an optional `[options]` section (M12 fills it with volume, keybinds, colourblind — parser must accept the section from day one; **save_slot lives only in `options.cfg`** beside the saves, read at boot before any save). List the complete persisted field set (above) as a checklist — every item must appear in Task 1.

### Task 1: Serialize + load + CRC

**Interfaces (consumed by M11/M12 score+options):** `pub fn saveWrite(path: []const u8, w: *World, exp: *Expedition) SaveErr`; `pub fn saveRead(path, w: *World, exp: *Expedition) SaveErr` (**symmetric** — `exp.active` says whether an expedition is live; a node-save carries the active expedition + hold and must round-trip; saves blocked only mid-fight) (errors: `Missing, BadVersion, BadDataVersion, BadHash, BadId, Damaged, Io` — `Io` catch-maps `FileError`, R15 superset, same mapping table as M6); `pub fn crcOf(text: []const u8) u32`.
- [ ] Unit tests: round-trip byte-compare (write → read → write identical); CRC tamper → BadHash; `version=1` → BadVersion; `data_version=1` → BadDataVersion; unknown creature id in cooldowns → BadId. Implement `persist.zig` with M6 parsers. PASS. Commit `example(undersanded): save serialize/load + CRC`.

### Task 2: Rollback write path + slots

**Interfaces:** 6 steps per §32 **as amended P17** (serialize→save.tmp; flush+close; re-read verify CRC; **remove stale `save.bak` if present, then** `save0.dat`→`save.bak` — the delete is MANDATORY: `std_file.rename` = `MoveFileA` which fails when the dest exists (std_file.zig:393–401); POSIX rename(2) overwrites so Linux tests cannot see this bug; z9gb precedent examples/z98/z9gb/save.zig:185 removes bak first; save.tmp→`save0.dat`; any failure at 5 → `save.bak`→`save0.dat`). **Startup recovery:** `save0.dat` missing + `save.bak` present → restore it (logged); delete stale `save.tmp`. `pub fn saveBackupSlot(path)` writes `save1.dat` manually (never auto).
- [ ] Unit tests: happy path leaves `save0.dat` + `save.bak`; **2nd consecutive save succeeds with pre-existing `.bak`** (the Win9x bug regression); injected failure at step 5 restores `save0.dat` (assert exists + CRC valid); step-3 verify failure aborts with originals untouched; **startup-recovery tests**: missing save0 + present bak → restored; stale tmp deleted. Fault injection seam: module-level plain fn field (`fs_rename`/`fs_remove` defaults = std_file, swapped in tests — R4: plain fn fields, no `?fn` call-throughs). Implement. PASS. Commit `example(undersanded): save rollback path + slots`.

### Task 3: Save UX + first run

**Interfaces:** `pub fn canSave(state) ?reason` (blocked mid-fight only, with reason string for the greyed menu entry); quit prompt `"Save before quitting? [Y] [N] [Cancel]"` when unsaved; first run: no `save0.dat` → full-screen text manual page 1 (embedded `[text]` from data.z98) → `[Enter] Begin` → init World (0 coins, 0 journal, expertise 0) → create initial save (**world initialization, not autosave**). Persisted set includes `journal_mask`, `tooltip_shown: u32` bits (once-per-fresh-install UX, M8), `field_phases` + `[options]` reserved section; line buffer 4096 covers `ready[672]` array lines; save dir comes from `paths.zig` (M1 G14: exe dir, writability fallback).
- [ ] UX tests: canSave matrix (dock ok / **node ok — expedition + hold round-trip golden** / fight blocked); quit-prompt golden; first-run golden (`--dump-grid` of page 1 + fresh save file created with `field_record_written=0`, `boss_variants_seen=0`). Implement `save_ux.zig`. PASS. Commit `example(undersanded): save UX + first run`.

### Task 3b: Start menu + boot routing

- [ ] Build the start menu (Continue / New Game / Options greyed until M12 / Quit) and route boot through it; fresh install still goes page 1 → start menu → New Game → dock. PASS. Commit `example(undersanded): start menu + boot routing`.

### Task 4: `--save-roundtrip` + `tier_m7_save.sh`

- [ ] `undtool --save-roundtrip save0.dat` (spec §26 tooling): loads, re-saves, byte-compares, exit 0/1. Tier: Tasks 1–3 tests + roundtrip golden + rollback injection + v1 fixture → error screen path + first-run golden. Non-vacuous. Run PASS. Commit `example(undersanded): M7 save tier`.

**Gate:** save round-trip golden passes; rollback path exercised; v1→v2 error path proven; first-run shows page 1 and initializes exactly to §20.

### Task 5: Next-milestone amendment review (M8)

- [ ] Read `2026-11-12-undersanded-m08-t1-content-plan.md`; judge `[text]` section capacity vs the full T1 text set (17 journal entries, 8 manual pages, legends, flavor, 6 error messages) — capacity is data-side, but the `MAX_LOG`/text-key table may need a documented size. Amendment or "no amendment needed" in NOTES.md.
