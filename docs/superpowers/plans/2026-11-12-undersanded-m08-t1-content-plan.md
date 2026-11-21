# undersanded M8 — Tier-1 content authoring — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Tier-1 content and its remaining wiring: append **one** Derelict row (load-order index 18) and wire the four deferred behaviours (blind, ink, decoy, phasing) plus Lure/Sonar; author journal 19, manual pages 2–8, Legends 2, zone flavour 4, and the journal/help UI. M6 already shipped the other 18 rows, stats, drops, tools/upgrades/cosmetics, Z1–Z3 encounters, zone D and `manual.1` — M8 verifies those, it does not re-author them.

**Architecture:** Pure authoring + wiring. Named fields and `[rules]` rows already encode most of §14.3; M8 adds the Derelict row, the three missing behaviour rules (`SET_BLIND`, `SET_INK`, `MISS_STRIKE`), and the one flag-driven algorithm (phasing). Text lives in `[text]` (keys `manual.* journal.* legend.* zone.*`). Journal unlocks are `World.journal_mask` bits (first fight end, any outcome); a persisted `journal_viewed` mask drives the "New entry" indicator; exact Speed is hidden until the journal bit exists (Sonar overrides).

**Tech Stack:** Z98 → C89 `-fsafe`; M6 loader, M7 save (journal bits + additive `journal_viewed`), M2 fight, M4 loop, M5 tools.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §8.7–8.8, §10 (tools), §11 (cosmetics), §12–13 (zones/encounters), §14 (roster tables), §15 (Derelict row only — boss fight is M11), §18 (manual/journal/tooltips/zone flavour), §25.2 (behaviour drivers), §25.10 (`zone.*`), §32 (additive keys), §38 P12/P26, §40 checklist, §36 M8.

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m07-save-system-plan.md`. NEXT: `2026-11-12-undersanded-m09-pixel-tier-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` + native drivers are the FAST gate; Wine/DD7/DSound are SLOW evidence only, never the gate. No Python.

Values are copied **verbatim** from spec §14.2/§14.4 — no tuning (balance is M15). Subdue 95/80/60/−1 and surge restore 25% are spec-fixed. **Rule thresholds are absolute precomputed integers** (e.g. 50% of 130 HP = `cond_a=65`), matching the landed T1 rows; never store a percentage in `cond_a`. `*_below_pct` values are pp added to 100. D17/D18 still apply.

**Behaviour drivers (spec §25.2, binding — one live driver each):**

| Behaviour | Live driver |
| :--- | :--- |
| Coupling regen | `thrash_regen`/`despair_regen` fields |
| Discharge | `[rules]` `HULL_DMG` one-shot (`discharge_*` = pin) |
| Armor / armor-below | `armor_pct`/`armor_below_*` fields |
| Speed-below / attack-below | `speed_below_*`/`atk_below_*` fields |
| Flee on hit | `flee_kind`/`flee_th` fields (strict `>`) |
| Flee on threshold (Rust) | `[rules]` `SET_FLEE` `HP_BELOW 24` |
| Grudge | `grudge_*` fields |
| Shell/resist | `resist_restrain_pct` (+ `F_SHELL`) |
| Blind (Lantern) | `[rules]` `SET_BLIND` `RES_BELOW 65`, `effect_b=50`, persistent |
| Ink (Squid) | `[rules]` `SET_INK` + `ROUND_MOD(3,0)`, persistent (`F_INK` = pin) |
| Decoy (Angler) | `[rules]` `MISS_STRIKE` + `FIRST_ROUND`, one-shot (`F_DECOY` = pin) |
| Phasing (Ghost-Ray) | `F_PHASING` + state machine — **sole VM exception** (no phase op) |

Every §25.6 effect op executes (incl. `ADD_SPEED`/`MULT_ATK`); no effect is a silent no-op.

## File Structure

- `examples/z98/undersanded/def.zig` — msg ids 18–23; `ROLE_BOSS=4`/`FAMILY_BOSS=13`; `journal_viewed: [2]u32` in `World`; zeroing hooks.
- `examples/z98/undersanded/creatures_t1.zig` — boss row appended + role/family consts; fallback drop arrays width 6.
- `examples/z98/undersanded/data.z98` — Derelict row + 5-line kill/2-line overkill drops; one `SET_BLIND` rule; `journal.*`, `manual.2..8`, `legend.*`, `zone.*` text.
- `examples/z98/undersanded/data.zig` / `validate.zig` — drop-key width 6; boss exemptions (`role<=4`, `family<=13`, `sale>=0`, `resolve>=0` for boss); `zone.*` vocabulary.
- `examples/z98/undersanded/fight.zig` — blind/ink/decoy/phasing wiring, Lure/Sonar constants + effects, `peekCreatureAction` extension, new msg ids.
- `examples/z98/undersanded/journal.zig` — unlock + viewed logic.
- `examples/z98/undersanded/help.zig` — `helpPage(screen)` + `tooltip(kind)`.
- `examples/z98/undersanded/nav.zig` — `NAV_JOURNAL`/`NAV_HELP`, `J`/`?` routing, dock "New entry" line.
- `examples/z98/undersanded/render_term.zig` — journal/help screens, node zone-flavour line, `SPD ??` + Sonar override, msgLine cases.
- `examples/z98/undersanded/persist.zig` — additive optional `journal_viewed`.
- `examples/z98/undersanded/game.zig` — zero `journal_viewed`.
- `examples/z98/undersanded/tests/{journal_test,help_test}.zig`, extended `fight_test`/`content_test`/`persist_test`; `tests/tier_m8_content.sh`; goldens (`defs_golden.txt`, journal/help/zone screens, save round-trip).
- `examples/z98/undersanded/README.md` — `J`/`?`.

## Review Focus

- Behaviour double-encoding drift (field and rule disagreeing) — assert the pin equals the live driver for every creature.
- Threshold units (absolute vs percent) — the 275%-class bug; every `cond_a` is an integer threshold, not a percentage.
- Hidden/visible Speed: `SPD ??` until the journal bit, Sonar overrides, and the reveal must survive save/load.
- Blind chance vs trigger: `SET_BLIND` fires while below; `pending_blind` must be consumed by the next Strike, not permanently re-arm.
- Journal trigger completeness: first fight end **including** Hull-0 ascent, player flee and creature flee; boss only on kill.
- Zone flavour / journal key mapping (`def_index+1`) — off-by-one would mislabel entries.

---

### Task 0: Preflight

- [ ] Record in `NOTES.md`: P26 rulings (C1–C4, driver table), the landed T1 state M8 verifies (18 rows, 4 rules, tables), the boss row field values, the current `TIER_M7 PASS 126/0` baseline, and the D18 note. Commit `example(undersanded): M8 preflight`.

### Task 1: Derelict row + behaviour wiring

**Interfaces (consumed by M11/M13 — the schema is the contract):** append one `[creatures]` row at load-order index 18 (`id=17`): `family=13`, `role=4`, `zone_mask=256`, `phase_mask=3`, `hp=300`, `resolve=0`, `speed=7`, `attack=10`, `subdue_chance=-1`, `flags=1` (`F_BOSS`), `sale=0`, `respawn_sub=20/kill=20/over=40`, `counter_tool=1`; drop slots `sub` empty; `kill` = Plate×5, Gland×3, Glow×3, Glass×2, Coral×2; `over` = Plate×2, Gland×1. All other fields 0/100 as the other rows. Raise `MAX_DROP_LINES` to 6 in `def.zig` and the `data.zig` key tables (`sub0..sub5`), fallback rows and `--dump-defs` golden. Validator: role max 4, family max 13, `sale<=0` allowed only for boss, `resolve=0` allowed for boss, `subdue_chance=-1` requires `F_BOSS` (already enforced).

- [ ] **Fight wiring** per the driver table. Implement the two missing VM effects: `MISS_STRIKE` (arm a strike-miss latch; `FIRST_ROUND`+one-shot ⇒ round 1 only) and `ADD_SPEED`/`MULT_ATK` (adjust computed speed/attack on top of the field baseline, applied once). Consume the latches: `pending_ink` randomizes the next player action (`rngRange(0,2)`→Strike/Restrain/Equipment, never Flee, 1 draw, Sonar suppresses) and extends `peekCreatureAction`; `pending_blind` rolls its chance to miss the next Strike (Lure suppresses); the decoy/miss latch misses the next Strike (Lure suppresses). `F_PHASING` is the algorithmic exception: `floor((round-1)/2)%2`, locked Phase below 30% HP, Solid ⇒ `active_resist_restrain=50` and Strike works, Phase ⇒ Strike misses and Restrain full. Add `TOOL_LURE=4`, `TOOL_SONAR=6`, msg ids 18–23 with `MESSAGES`/`msgLine` copy. Lure reveals phase/real target; Sonar reveals exact Speed + next action + Ghost-Ray flip.
- [ ] Add the three behaviour rules as `[rules]` rows: blind (`owner=12`, `cond_op=2`, `cond_a=65`, `effect_op=6`, `effect_b=50`, `timing=1`), ink (`owner=14`, `cond_op=3`, `cond_a=3`, `cond_b=0`, `effect_op=7`, `timing=1`), decoy (`owner=15`, `cond_op=4`, `effect_op=10`, `timing=0`). Keep Rust's `SET_FLEE` at `24`; keep discharge thresholds `48/45/50`. Tests: solid/phase alternation, ink cadence + never-Flee + 1 draw, decoy round-1 miss, blind chance, `ADD_SPEED`/`MULT_ATK` rule execution + precedence, Lure/Sonar counters, reveal stable across two peeks, boss row loads and pins all fields. Commit `example(undersanded): Derelict row + combat behaviour wiring`.

### Task 2: Verify shipped content + boss drops

- [ ] Verify (do not re-author) the landed §14.4 drops, §10–§11 tables, §13 Z1–Z3 encounters and zone D; assert them against the spec table in `content_test`. Re-pin `defs_golden.txt` for the boss row. Commit `example(undersanded): verify T1 tables + boss drops`.

### Task 3: Journal + help + tooltips + zone flavour

**Interfaces:** `pub fn journalOnFightEnd(w: *World, def_index: i32) void` (first end, any outcome); `pub fn journalOnBossKill(w: *World) void`; `pub fn helpPage(screen: i32) ?[]const u8`; `pub fn tooltip(kind: i32) ?[]const u8`.

- [ ] `journal.zig`: set `journal_mask` bit for `def_index` (boss bit only via `journalOnBossKill`); `journal_viewed` bit cleared on unlock, set when the entry is opened; "New entry" = any unviewed bit. Key mapping `journal.<def_index + 1>`.
- [ ] Author text: journal 19 (one paragraph each, §18 voice; boss = "a signal, not a machine" pre-kill), manual pages 2–8 (pages 1 is M6-authored), Legends 2 (`legend.1` Mileel, `legend.2` Tunisteel), zone flavour 4 (`zone.1` Z1, `zone.2` Z2, `zone.3` Z3, `zone.9` D; `zone.4..8` deferred M13). Do not author `error.*` (M7 owns the copy).
- [ ] UI: `NAV_JOURNAL`/`NAV_HELP`, `J`/`?` keys, journal screen, per-screen `?` page map (dock→1, map→5, node→2, fight→2, settle→3, refine/craft→4, tools→6, journal→7), node-screen zone flavour, dock "New entry" line. H4: `render_term` prints `SPD ??` unless `journal_mask` bit for `def_index` is set or Sonar is active. Tooltips (2 kinds) once per fresh install via `tooltip_shown` bits; triggers = first Restrain action and first red-zone entry.
- [ ] Persist `journal_viewed` as an **additive optional key** (absent ⇒ 0; always written); extend `persist_test` round-trip and the M7-era fixture (old save without the key must still load). Tests: trigger matrix (incl. ascent/flee), viewed indicator, help map, tooltip once, speed reveal survives save. Commit `example(undersanded): journal, manual, legends, zone flavour`.

### Task 4: `tier_m8_content.sh` — demo content-complete

- [ ] Tier nests `tier_m7_save.sh`; runs the new drivers; scripted full loop **start → Z1–Z3 fights → boss node lock/telegraph at 6-seen** (boss fight is M11); journal bits + `journal_viewed` survive save round-trip; `?` and journal screen goldens; boss row dump golden; non-vacuous (mutate a golden → fail). Commit `example(undersanded): M8 content tier`.

**Gate:** demo content-complete in terminal: every §40 M8 item authored, full T1 loop playable to the boss gate, all goldens green.

### Task 5: Next-milestone amendment review (M9)

- [ ] Read `2026-11-12-undersanded-m09-pixel-tier-plan.md`; judge render-asset needs vs text content (log line lengths, screen copy for art layout). Amendment or "no amendment needed" in `NOTES.md`.
