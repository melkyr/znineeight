# undersanded M8 — Tier-1 content authoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** All Tier-1 content authored into `data.z98` — 17 creature rows + 2 flex (Anemoniacus, Freezing Perch = M2/M3 sim rares now placed in Z2/Z3 tables), 7 tools, Z1–Z3 encounter tables, 19 journal entries, manual pages 1–8 (7 authored here, page 1 at M7), Legends (2), zone flavor (4), error copy (6) — demo content-complete in terminal.

**Architecture:** Pure authoring + wiring: rows move from `tables_t1.zig` fixtures to the real `data.z98`; behaviors from spec §14.3 are expressed as §25.6 rule rows plus the named fields (`discharge_*`, `armor_below_*`, `speed_below_*`, `atk_below_*`, `flee_*`, `grudge_*`); text goes in the `[text]` section. The journal system keys non-boss entries on first-fight-end (P12), boss on first kill; `?` serves embedded manual pages (P12).

**Tech Stack:** Z98 → C89 `-fsafe`; M6 loader, M7 save (journal bits persist), M2 fight, M4 loop.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §10 (tools), §11 (cosmetics), §12–13 (zones/encounters), §14 (all four roster tables), §15 (Derelict row placeholder — boss fight is M11), §18 (manual/journal/tooltips), §38 P12 (journal trigger, `?` pages), §40 (authoring checklist), §36 (M8 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m07-save-system-plan.md`. NEXT: `2026-11-12-undersanded-m09-pixel-tier-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Stats/drops/respawn values copied **verbatim** from spec §14.2/§14.4 — no tuning in this milestone (balance is M15's job; M3 levers only via STOP-present). Journal voice: first-person, past tense, observational, never instructs (§18). Tooltip strings exact (§18). Sale prices §14.2 (10–70 range). Subdue chances 95/80/60/−1 exact.

## File Structure

- `examples/z98/undersanded/data.z98` — full T1 content (creatures 1–19 incl. flex, rules, tools, upgrades, cosmetics, encounters Z1–Z3, zones, text).
- `examples/z98/undersanded/journal.zig` — entry unlock logic (P12 triggers), "New entry" indicator flag, seen mask.
- `examples/z98/undersanded/help.zig` — `?` key → embedded manual page per screen; tooltips (two strings, first-occurrence only).
- `examples/z98/undersanded/tests/tier_m8_content.sh`, updated goldens (`defs_golden.txt`, screen goldens).

## Review Focus

- Stat transcription drift (HP/Res/Spd/Atk/subdue/sale/respawn) — every value must match spec §14.2 byte-for-byte → generated diff test: dump from loader vs a checked-in copy of the spec table.
- Behavior encoding errors (one-shot vs persistent timing per §14.3: discharge one-shot; armor/speed/attack-below persistent) → per-creature behavior tests asserting the exact effect and timing.
- Drop table order and keystone drops (Mileel Hooked Barbel ×1 only on subdue; Tunisteel Steel Fins ×2 only on subdue) → per-creature drop goldens.
- Journal voice drift into "now do X" → review step; tooltip appearing more than once → counter test.
- Encounter weights transcription (Z1–Z3 day/night exact) → loader golden of encounter arrays.

---

### Task 0: Preflight

- [ ] Print spec §14.2 and §14.4 into the working notes as the transcription source. Confirm the §40 checklist scope for M8 (everything except boss-flavor/cosmetic-description/field-record lines = M11). Note the flex rares (Anemoniacus, Freezing Perch) are the new Z2/Z3 encounter rows from spec §13.

### Task 1: Creature rows + behavior rules

**Interfaces (consumed by M13 — the schema is the contract):** 19 `[creatures]` rows as **M6 KV rows** (order-free `key=value` fields — §25.2 names; there is no column order); `[rules]` rows encoding §14.3 per creature (Mystic Eel: Despair regen override +8; Electric Eel: Thrash +8 + discharge {stat RES, th 50, dmg 8} one-shot; Mileel: Despair +10 + flee{kind SINGLE_HIT, th 30% max, **strict `>`**, fires **next turn**} + grudge{EEL, RES, 30}; (a hit of exactly 24 on HP 80 must NOT flee); Steel Tuna: persistent armor 60% (Plate negates) + speed_below{30, +4}; Rust Tuna: armor 80% + flee{HP_BELOW 30, strict `<`, next turn}; Tunisteel: armor 50% (grudge → 30) + speed_below{30, +6}; Kelp Crab: Thrash +6; Brine Jelly: Despair +10; Barnacle: armor_below{50, 70} + stationary; Anemone: discharge{HP, 50, 10} one-shot + stationary; Anemoniacus (flex): Thrash +10 + discharge{HP, 50, 10} one-shot; Freezing Perch (flex): Despair +8 + flee{SINGLE_HIT, th 20% max (21), strict, next turn}; Coral Crab: `resist_restrain_pct=50` (Shell; Brine Net tool check) + Thrash +12; Lantern-Jelly: `blind_chance=50` + rule SET_BLIND {stat RES, th 50} (fires while below, §8.7 persistent-while-true; Lure tool check) + Despair +12; Ghost-Ray: phasing flag F_PHASING (floor((r-1)/2)%2, lock Phase <30%; when solid `resist_restrain_pct=50` — "Solid: Restrain 50%"); Squid: ink every 3 rounds + speed_below{RES 50, +6}; Angler: decoy round 1 + atk_below{50, **+50**} (`*_below_pct` = pp added to 100 — spec §9.5 accumulate example: 100+50+25; NEVER +150); Wrasse: armor_below{30, 50} + speed_below{30, +4}; Derelict: boss sentinel row only).
- [ ] Transcription diff test (Review Focus #1) + per-creature behavior tests. Implement rows. PASS. Commit `example(undersanded): T1 creature rows + behavior rules`.

### Task 2: Drops, tools, upgrades, cosmetics, encounters

- [ ] `data.z98`: §14.4 drop rows exactly (subdue/kill/overkill, keystones on subdue only); tools/upgrades/cosmetics tables (M5 fixtures → real file, §10–§11 verbatim incl. prices 150/175/200 and unlock milestones); Z1–Z3 encounter rows exactly §13; Z4–Z8 stubs; Derelict zone D (boss flag, travel 5, gate 6-seen, telegraph string). Goldens updated. Commit `example(undersanded): T1 drops, tools, tables, encounters`.

### Task 3: Journal + help + tooltips

**Interfaces:** `pub fn journalOnFightEnd(w: *World, def) void` (non-boss: first fight end any outcome); `pub fn journalOnBossKill(w: *World)`; `pub fn helpPage(screen) ?[]const u8` (8 manual pages + page 1 embedded); `pub fn tooltip(kind) ?[]const u8` (exactly 2 kinds, each once per fresh install).
- [ ] Author 19 journal entries (3 sentences, §18 voice; boss entry "after the first kill", Derelict referred to as "a signal, not a machine" pre-kill), manual pages 1–8 (one mechanic per page, worked examples — spec §18 list), Legends 2 entries (Mileel, Tunisteel: "unconfirmed sightings", no locations/stats/tips), zone flavor 4 paragraphs, error copy 6 messages (§33 verbatim — authored here per §40's list; M7 consumes the keys: §40 listed them under M7, resolved as content-authored-M8 / runtime-consumed-M7). Unit tests: trigger matrix (fight end→entry once; flee counts; boss kill gate); help per screen; tooltip once (`tooltip_shown` bits persist via M7 save set); H4 wiring: `journalOnFightEnd` sets the `spd_revealed` bit → fight screen flips `SPD ??` to exact Speed (M2 render reads the bit). PASS. Commit `example(undersanded): T1 journal, manual, legends, copy`.

### Task 4: `tier_m8_content.sh` — demo content-complete

- [ ] Tier: Tasks 1–3 tests + full-loop scripted golden **start → Z1–Z3 fights → boss node shows lock/telegraph at 6-seen** (Anemoniacus/Freezing Perch rows loadable + fightable) (boss fight itself M11) + journal bits persist through save round-trip + `?` pages golden. Non-vacuous. Run PASS. Commit `example(undersanded): M8 content tier`.

**Gate:** demo content-complete in terminal: every §40 M8 item authored, the full T1 loop playable to the boss gate, all goldens green.

### Task 5: Next-milestone amendment review (M9)

- [ ] Read `2026-11-12-undersanded-m09-pixel-tier-plan.md`; judge render-asset needs vs text content (log line lengths, screen copy for art layout). Amendment or "no amendment needed" in NOTES.md.
