# undersanded M7 — save system — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Text saves with CRC32 integrity, `version=2`/`data_version=2`, the mandatory rollback write path, two slots, first-run lore page, and the save UX rules — proven by round-trip goldens and an exercised rollback.

**Architecture:** `persist.zig` serializes `World` (including the P25 `FieldRecord`/`LastRun`/score structs) + `Expedition` (including `pending_cond`) to the §32 section grammar with a **save-local scanner and section vocabulary** (same `key=value` family as `data.z98`, but never `data.zig`'s §25.10 parser), computes crc32 over everything above `[crc32]`, and implements the 6-step write path with step-6 rollback. `save_ux.zig` handles Esc-menu Save availability (blocked mid-fight **or while a subdue choice is pending**, P25/R1), quit prompt, start menu, the two error surfaces, and the first-run page-1 flow.

**Tech Stack:** Z98 → C89 `-fsafe`; std_file (M1: open/readAll/writeAll/rename/remove), `std_crypto.crc32` (M1 one-shot), `data.parseI32` + `std_parse.parseUint`.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §20 (first run), §32 (save format, load checks, write path, slots, UX, data dir), §33 (fatal messages), §38 P10 (grudge mask in save), §36 (M7 row + §34 save rows).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m06-data-loader-plan.md`. NEXT: `2026-11-12-undersanded-m08-t1-content-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. **No autosave, ever.** `version` mismatch and `data_version` mismatch both go to the save-error screen with fresh / backup slot / quit options — **no auto-migration** (T3). Save contents include every §19/coreid-list field: cycle/phase/location, expedition state + hold (**the persistent dock parts store — write it at dock too**, P22.4) **+ `tool`/`tool_charge`/`tool_broken`/`pending_cond`**, hull, boat axes, tools owned/equipped, **refined materials (`World.materials[10]`, P22)**, money, cosmetics owned/unlocked, journal bits, seen array, per-zone per-species cooldowns, release counts + bonuses + wary flags, lockouts, grudge mask (cleared at run boundary — P10), expertise, **`rng_state`**, boss kills, `boss_variants_seen` mask, **and the P25 `FieldRecord` / `LastRun` / lifetime score counters**. `pending_cond` lives in `Expedition` from M7 on (it is reset at `depart`, set by rough-sleep Rest, consumed at fight start). Saves are blocked mid-fight and while a Release/Sell choice is pending (P25/R1).

## File Structure

- `examples/z98/undersanded/persist.zig` — save-local scanner/parser, serialize/load/validate CRC, 6-step write path with rollback, slot management (`save0.dat` + `save.bak`; `save1.dat` manual), `errors.log` append helper.
- `examples/z98/undersanded/save_ux.zig` — availability rules, quit prompt, start menu, save-error screen, first-run flow (manual page 1 full-screen text → `[Enter] Begin` → world init: 0 coins, 0 journal entries, dock).
- `examples/z98/undersanded/nav.zig` — new screen ids `NAV_LORE` / `NAV_MENU` / `NAV_SAVE_ERR`, Esc→Save entry and boot routing hooks.
- `examples/z98/undersanded/render_term.zig` — page-1 text screen, start menu, save-error screen, greyed Save line.
- `examples/z98/undersanded/undtool.zig` — `--dump-grid --screen lore|menu`, `--save-roundtrip <file>`.
- `examples/z98/undersanded/app.zig`, `game.zig`, `paths.zig` — boot routing (options.cfg → slot choice → load/menu/first-run), initial-save creation, save path resolution.
- `examples/z98/undersanded/tests/persist_test.zig`, `tests/bind_test.zig` additions, `tests/tier_m7_save.sh`, `tests/fixtures/save_v1_bad.sav`.

## Review Focus

- Rollback step 6 never exercised (the most dangerous silent gap) → inject rename failure at step 5 in the test and assert `save0.dat` restored from `.bak`.
- CRC computed over the wrong range (must exclude the `[crc32]` section itself; include everything above it) → tamper test flips one byte below/above the boundary.
- A load that fails a check must leave the in-memory world untouched → parse into a zeroed temp `World`/`Expedition` and commit only on success; test every failure class against a poisoned state.
- Save during forbidden states (mid-fight **or pending Release/Sell**, P25/R1) must grey with reason → UX state tests.
- Partial writes on FAT32: save.tmp must be flushed + re-read + CRC-verified **before** any rename → order test with a mock failing flush.
- Fresh-install init drifting from §20 (must be world init, not an autosave; 0 coins; page 1 shown once; no menu on first run) → first-run golden.

---

### Task 0: Preflight

- [ ] Freeze the save grammar in NOTES.md (§32): header `version=2` / `data_version=2`; save-local sections `[world] [boat] [cooldowns] [journal] [expedition] [score] [options] [crc32]`; **one scalar `key=value` per line**, arrays **one line each** as `name=i,i,i`; `[crc32] hash=0x…` last with nothing after it; unknown key = `Damaged` except inside the reserved `[options]` section (skipped, M12 fills it). Line buffer **8192 B** (worst-case `ready[672]`), whole file cap **64 KiB**. **`save_slot` lives only in `options.cfg`** beside the saves, read at boot before any save; M7 adds a read-only parser (`save_slot=0|1`, default 0 when absent/damaged), M12 owns writing it.
- [ ] List the complete persisted field set as a checklist (every item must appear in Task 1): cycle/phase, `ready[672]`, `seen_mask[2]`, `journal_mask[2]`, `tooltip_shown`, `field_phases`, `hull`, `release_bonus[12]`, `lockout_until[12]`, `family_overkill_mask`, `wary_mask[2]`, **`rng_state`**, `boat[5]`, `money`, `expertise[10]`, `materials[10]`, `tools_owned`, `tool_selected`, `cosmetics_owned`, `cosmetics_unlocked`, `field_record_written`, `boss_variants_seen`, `boss_kills`, **P25 `FieldRecord` + `LastRun` + `score_*` counters**, and the expedition `active/zone/fight_index/seed/hold[14]/hold_n/tool/tool_charge/tool_broken/**pending_cond**`.
- [ ] Record the P25 rulings verbatim in NOTES (R1 settle-state Save block; R2 score structs now; R3 fresh install follows §20 with no menu; R4 New Game confirm) and the M6 handoff facts: load-order `def_index` order `[1,2,4,18,19,5,7,8,9,10,3,6,11,12,13,14,15,16]`, M8's Derelict appends at index 18, `BadId` validates against `creatures.defCount()` never `CreatureDef.id`, `manual.1` is authored by M6 and only **consumed** here, `data_version` compares to the installed `Tables.content_version` (`def.content_override` else 2).
- [ ] Freeze the two error surfaces and the log helper: §33 fatal screen (full-screen text, `[Enter] Quit`) for content/crash failures; save-error screen (`[F]resh  [B]ackup slot  [Q]uit`) for load-check failures. `errors.log` append helper writes recovery/warning lines to the writable dir.
- [ ] Record the baseline gate (`TIER_M6 PASS 90/0` on `/tmp/seed151_build/zig1_5_clean`) and the exact file list this milestone touches.
- [ ] Note the D18 hazard: `FieldRecord.boat[i]` / `FieldRecord.expertise[i]` and other nested array-field writes must go through a pointer or a whole-struct assignment — nested indexed writes silently miscompile (D18).

### Task 1: Serialize + load + CRC

**Interfaces (consumed by M11/M12 score+options):** `pub const SaveErr = error{ Missing, BadVersion, BadDataVersion, BadHash, BadId, Damaged, Io };` `pub fn saveWrite(path: []const u8, w: *const World, exp: *const Expedition) SaveErr`; `pub fn saveRead(path: []const u8, w: *World, exp: *Expedition) SaveErr` (**symmetric** — `exp.active` says whether an expedition is live; a node-save carries the active expedition + hold and must round-trip; blocked states are enforced in `save_ux`, not here); `pub fn crcOf(prefix: []const u8) u32`. `Io` catch-maps `FileError` (R15 superset, same mapping table as M6).
- [ ] Implement `persist.zig` reusing **only** `data.parseI32` for i32 scalars/array elements and `data.parseRowKV` for comma-free, non-empty scalar lines; use `std_parse.parseUint` for every `u32` (`rng_state`, masks, `tools_owned`, `cosmetics_*`, `boss_variants_seen`) and a hex parser for `[crc32] hash=0x…`. Write a save-local line scanner (`\n`, strip one trailing `\r`), a save-local array parser (`name=v[,v...]`), and the save section vocabulary. Do **not** use `data.sectionId`, `data.classifyLine`'s `format=2` header rule, the `[text]` continuation logic, `validateAll`, or `buildFallback`.
- [ ] Load is **all-or-nothing**: zero a temp `World` + `Expedition`, parse and check into it, then commit on success — a failed load leaves the caller's state untouched. Checks in §32 order: exists → `version` → `data_version` vs `if (def.content_override) |t| t.content_version else 2` → CRC over the prefix ending before `[crc32]` → IDs. Reject trailing content after `[crc32]`.
- [ ] Validate ranges, not just IDs: `phase` 0/1, `hull` 0..`HULL_TABLE[boat[HULL]]`, `boat[i]` 0..3, `expertise` 0..5, `materials`/`money` ≥ 0, `tool_selected` 0..7, `hold_n` 0..14, and every mask bit < `creatures.defCount()`.
- [ ] Unit tests: round-trip byte-compare (write → read → write identical); CRC tamper → BadHash; `version=1` → BadVersion; `data_version=1` → BadDataVersion; unknown creature id in cooldowns → BadId; failed load leaves a poisoned target state untouched; `ready[672]` worst-case line accepted; pending-settlement fields (`outcome`/`def_index`) are **not** saved (blocked in UX). PASS. Commit `example(undersanded): save serialize/load + CRC`.

### Task 2: Rollback write path + slots

**Interfaces:** 6 steps per §32 **as amended P17** (serialize→save.tmp; flush+close; re-read verify CRC; **remove stale `save.bak` if present, then** `save0.dat`→`save.bak` — the delete is MANDATORY: `std_file.rename` = `MoveFileA` which fails when the dest exists (std_file.zig:393–401); POSIX rename(2) overwrites so Linux tests cannot see this bug; z9gb precedent examples/z98/z9gb/save.zig:185 removes bak first; save.tmp→`save0.dat`; any failure at 5 → `save.bak`→`save0.dat`). **Startup recovery:** `save0.dat` missing + `save.bak` present → restore it (log via the `errors.log` helper); delete stale `save.tmp`; run recovery **before** any first-run/fresh-install decision. `pub fn saveBackupSlot(path)` writes `save1.dat` manually (never auto).
- [ ] Unit tests: happy path leaves `save0.dat` + `save.bak`; **2nd consecutive save succeeds with pre-existing `.bak`** (the Win9x bug regression); injected failure at step 5 restores `save0.dat` (assert exists + CRC valid); step-3 verify failure aborts with originals untouched; **startup-recovery tests**: missing save0 + present bak → restored (and logged); stale tmp deleted; recovery precedes fresh-install. Fault injection seam: module-level plain fn field (`fs_rename`/`fs_remove` defaults = std_file, swapped in tests — R4: plain fn fields, no `?fn` call-throughs). Implement. PASS. Commit `example(undersanded): save rollback path + slots`.

### Task 3: Save UX + first run

**Interfaces:** `pub fn canSave(g: *const GameState) ?[]const u8` (returns the greyed reason; blocked mid-fight **and while a Release/Sell choice is pending**, P25/R1); quit prompt `"Save before quitting? [Y] [N] [Cancel]"` when unsaved; save-error screen for load failures (`[F]resh  [B]ackup slot  [Q]uit`); first run: no `save0.dat` → full-screen text manual page 1 read from the **installed tables** (`manual.1`; M6 authors it, M7 only consumes) → `[Enter] Begin` → init World (0 coins, 0 journal, expertise 0) → create initial save (**world initialization, not autosave**) → dock (P25/R3: no menu on first run). Treat the stored page as literal text: `\n` line break, `\n\n` paragraph break; render them, never re-wrap. Save path comes from `paths.zig` (exe dir, writability fallback).
- [ ] Add the screens in `nav.zig` + `render_term.zig` (`NAV_LORE`, `NAV_MENU`, `NAV_SAVE_ERR`, Esc→Save entry with greyed reason) and the `options.cfg` read-only reader in `paths.zig`/`save_ux.zig`; `undtool --dump-grid --screen lore|menu` produces deterministic frames.
- [ ] UX tests: canSave matrix (dock ok / **node ok — expedition + hold + `pending_cond` round-trip golden** / fight blocked / **pending Release/Sell blocked**); quit-prompt golden; save-error screen golden for `version=1`; first-run golden (`--dump-grid` of page 1 + fresh save file created with `field_record_written=0`, `boss_variants_seen=0`, no menu). Implement `save_ux.zig`. PASS. Commit `example(undersanded): save UX + first run`.

### Task 3b: Start menu + boot routing

- [ ] Boot order: recovery (Task 2) → `options.cfg` slot → save exists ? start menu : first-run flow (§20, P25/R3). Start menu: `Continue` (load slot → dock), `New Game` (confirm `Erase this save? [Y] [N]` → world init without page 1, P25/R4), `Options` greyed until M12, `Quit`. Menu never appears on a fresh install; first-run goes page 1 → world init → dock. PASS. Commit `example(undersanded): start menu + boot routing`.

### Task 4: `--save-roundtrip` + `tier_m7_save.sh`

- [ ] `undtool --save-roundtrip save0.dat` (spec §26 tooling): loads, re-saves, byte-compares, exit 0/1; works with no `data.z98` beside the tool (content version falls back to 2) and never installs content. Tier: Tasks 1–3 tests + `lore`/`menu` screen goldens + roundtrip golden + rollback injection + v1 fixture → save-error screen + first-run golden + boot routing + **nested `tier_m6_data.sh`**. Non-vacuous (mutate a golden/expectation and see it fail). Run PASS. Commit `example(undersanded): M7 save tier`.

**Gate:** save round-trip golden passes; rollback path exercised; v1→v2 error path proven; settle-state and mid-fight Save blocks proven; first-run shows page 1, initializes exactly to §20, and shows no menu; the second boot shows the start menu.

### Task 5: Next-milestone amendment review (M8)

- [ ] Read `2026-11-12-undersanded-m08-t1-content-plan.md` and judge, recording "amendment required (items…)" or "no amendment needed" in NOTES: (a) `[text]` capacity vs the full T1 set (19 journal entries, `manual.2..8`, legends, zone flavor, error copy) against `MAX_TEXT_KEYS=256` / `MAX_TEXT_BYTES=48 KB`; (b) M8's Task 1/2/3 wording is stale — M6 already ships 18 rows, names, masks, §14.4 drops, tools/upgrades/cosmetics/encounters, zone D and `manual.1`; M8 only adds the Derelict boss row (**appended at load-order index 18**), the remaining §14.3 rule encoding, `manual.2..8`, journal/legend/flavor text and the non-content error copy; (c) the Derelict's 5 kill drop lines still exceed `MAX_DROP_LINES=4` (§39 TBD — resolve at M8/M11); (d) `manual.1` ownership stays M6-author/M7-consume, and M7 owns only the save/crash error copy.
