# undersanded M11 — boss + score screen (DEMO GATE) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Derelict boss fight with 5 adaptive Phase-2 variants, the credits + three-panel score screen, and boat cosmetics rendering — the demo-complete gate: full boss loop completable, all 5 variants triggerable from a save.

**Architecture:** `boss.zig` layers §15 onto `fight.zig` (phase bands, Speed/Attack tables, Cannon Volley scheduling, variant scripts selected at engagement by dominant boat axis, Steel Plate volley-halving, Restrain disabled), with the required boss state carried in `FightState`. `score.zig` owns the three panels (Field Record frozen-once, Variants Seen 5-bit mask, Last Run) fed from the M7 `World` fields. `render_art`/`render_term` add score/credits screens and the boat render (blit order §30) with the 9 overlays and paint LUT.

**Tech Stack:** Z98 → C89 `-fsafe`; existing fight/save/render/UX; `boss00` base/Armor sprite + 4 boss V rows (M10/M11). Score/credits screens use the M10.1 status/help contract.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §7.1 (status/help contract), §15 (phases 300→200→100→0; Speed 7/10/12; Attack 10/15; Volley 15 every 2 rounds; 5 variants + tiebreak H>P>C>O>S + all-zero→Armor; Kill 20 / Overkill 40; gate 6 seen; node telegraph), §9.1 (boss subdue −1), §18 (journal.19 on first defeat), §19 (credits→score, Field Record/variants/Last Run/closing line), §25.10 (`boss.1..5`, `cosmetic.1..12`), §30 (paint LUT/clip + cosmetic map), §34 (variants-bit + Field Record rows), §36 (M11 row), §38 P10/P30/**P31**.

**Sequence:** PREVIOUS: `2026-11-21-undersanded-m10.1-ux-feedback-plan.md`. NEXT: `2026-11-12-undersanded-m12-audio-options-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` + native drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be CI-runnable without Wine. Nest `tests/tier_m101_ux.sh` (which nests TIER_M10) in the M11 tier.

As prior. Boss values verbatim: HP bands 300/200/100/0; P1 Speed 7 Attack 10; P2 Speed 10, Cannon Volley 15 every 2 rounds replacing standard, Steel Plate halves to 7 (integer); P3 Speed 12 Attack 15; variants — Armor: Strike 50% unless Plate · Sliver: full odd rounds / 25% even · Hoard: jettisons the **first non-empty non-keystone hold slot** every 3 rounds · Drown: after round 10, +5 Hull/round beyond 10 · Blur: always first, double-strike every 3rd round. Variant chosen at engagement from `boat[5]` (max tier, tiebreak H>P>C>O>S, all-zero→Armor) — bit set on **Phase 2 entry**, survives ascent/loss. Restrain disabled with "The machine has no will to break." Subdue chance −1. **Boss defeat = Kill or Overkill**: both award credits/score/Field Record first-defeat/journal.19/`runReset`/`boss_kills`; Overkill respawn stays 40 (Kill 20). Boss route: 1 fight max, gate 6 distinct non-boss seen, node telegraph "Hull 150+ recommended." Boss defeat → credits → score → dock with normal D-route return travel.

**UX contract (§7.1, M10.1):** every screen footer keeps `[?] Help`; score/boat map to the existing `manual.8` page (extend it; do not add a page). New nav ids are >=25 (`NAV_SUBDUE_INTRO=24`) and must join **both** allow-lists: `nav.navRun` and `loop_gfx.navRunGfx`, plus `loop_gfx.artMode` and help routing. Fight-ending status must survive the screen change or be deliberately replaced by the score transition; do not silently drop it. Score/credits screens must not erase a live fight log.

**No RNG/phase/save-format changes** except the score counters/Field Record/Last Run writes already defined in M7; `version=2` stays frozen.

## File Structure

- `examples/z98/undersanded/boss.zig` — boss fight layer + variant scripts; `FightState` boss fields.
- `examples/z98/undersanded/score.zig` — data-only `ScorePanels` (Field Record, Variants Seen, Last Run, lifetime counters).
- `examples/z98/undersanded/fight.zig`, `expedition.zig`, `world.zig`, `def.zig` — boss hooks, Hunt branch, zone-aware fight cap, defeat bookkeeping, nav ids/events.
- `examples/z98/undersanded/assets.zig` — boat/overlay/boss-variant accessors; `loop_gfx.zig` `ArtAssets` boat+overlays.
- `examples/z98/undersanded/render_art.zig`, `render_term.zig`, `render_text.zig`, `nav.zig`, `loop_gfx.zig`, `journal.zig` — boss/score/credits/boat screens, both allow-lists, help page 8.
- `examples/z98/undersanded/undtool.zig` — `--dump-grid --screen score|boat|credits`.
- `examples/z98/undersanded/data_schema.zig`, `data.z98` — `boss.1..5` / `cosmetic.1..12` vocabulary + copy.
- `examples/z98/undersanded/tests/boss_test.zig`, `score_test.zig`, `tests/data_load_test.zig`, `tests/fixtures/save_*`, `tests/tier_m11_boss.sh`, goldens; `defs_golden.txt` if text rows are dumped.

## Review Focus

- Variant selection drift (cumulative-tier semantics P11, exact tiebreak H>P>C>O>S, all-zero→Armor) → matrix over all boat tier combinations.
- Variants bit set on **Phase 2 entry**, survives ascent/loss → ascent-mid-P2 test.
- Volley scheduling (every 2 rounds, replaces standard, Plate halves) and Drown round-10 off-by-one → round traces.
- Hoard jettison: first non-empty non-keystone hold slot every 3 rounds, not a random wipe → hold trace.
- Field Record second-defeat byte-identical; time field excluded → §34 row.
- Boss defeat is Kill **or** Overkill: both paths write counters/runReset/journal.19/score; neither loses the score transition.
- Boat paint: header ramp is 1 but hull `from_ramp=0`; exact shade LUT; bbox clip; outside-bbox base pixels; cosmetic highest-owned selection.

---

### Task 0: Preflight

- [ ] Record P31 in NOTES. Pin score layout, credits copy, Field Record title, closing line, and the `boss.1..5` / `cosmetic.1..12` text keys. Extend `data_schema.textKeyKnown`, `data.z98`, `tests/data_load_test.zig` (text count 34→51), and verify whether `defs_golden.txt` needs text rows. Pin the boat paint LUT/clip and cosmetic index map. Confirm boss row `subdue_chance=-1`; do **not** claim `runReset` is already wired. Record defeat = Kill or Overkill. Baseline TIER_M10.1.

### Task 1: Boss fight core (`boss.zig`)

**Interfaces:** `pub fn startBoss(s: *GameState, w: *World) void` — compute `boss_axis` via one two-step helper (`axisFromBoat`: all-zero→Hull; `variantFromAxis`: Hull→Armor), tiebreak H>P>C>O>S; store phase, variant/axis, volley round, engagement-start Hull/actions in `FightState`. `pub fn bossPhaseUpdate(s)` — transitions 300→200→100 with Speed/Attack swaps; set variants bit on entering band 2. Variant effects per §15 (Plate halves Volley to 7); Restrain rejected + journal line; overkill/kill respawn writes 40/20 through `markTaken`; on **Kill or Overkill** call `journalOnBossKill`, `runReset`, and the score counters exactly once.
- [ ] Tests: phase boundaries at exactly 200/100; speed/attack per band; volley cadence/Plate; each variant trace (Armor 50%; Sliver odd/even; Hoard first non-empty non-keystone cadence; Drown +5 after round 10; Blur first/double-strike); Restrain reject; subdue −1; Kill and Overkill both bookkeep. Commit `example(undersanded): Derelict boss fight`.

### Task 2: Variant selection + gate + flow

- [ ] **Verify** the already-landed gate/telegraph/zone D/cost 5/20-40 respawn (`render.bossGateOpen`, `render_term` map/node text, `data.z98` zone 8, `world.markTaken`); do not reimplement. Add variant matrix; zone-aware `maxFights` (boss zone 8 = 1); boss Hunt branch in `expedition.hunt`; node telegraph "Hull 150+ recommended." (map already has it); 1-fight boss cap tests. Commit `example(undersanded): boss gate, telegraph, variant matrix`.

### Task 3: Score + credits (`score.zig`)

**Interfaces:** `pub fn scoreSnapshot(w: *World) ScorePanels` — data only (boat render is Task 4): Field Record (cycles, `World.field_phases`, seen/rares, boss kills, final Phase 2, sub/kill/over, expertise, money, cosmetics, boat tiers), Variants Seen `n/5` grayed, Last Run (cycles, Phase 2 identity, outcome, actions = `FightState.actions`, Hull spent) + lifetime kills. Closing line exact. Defeat path (Kill or Overkill) → credits → score → dock with normal D-route return travel; `runReset`/`journalOnBossKill`/counters exactly once. Score/credits nav ids >=25, both allow-lists, `artMode`, help page 8.
- [ ] Tests: Field Record second defeat byte-identical with time excluded; variants bit survives ascent; Last Run overwrites per engagement incl. loss; counters/runReset/journal.19 on both defeat outcomes; score/credits routing in terminal + window. Commit `example(undersanded): three-panel score screen`.

### Task 4: Boat + cosmetics render

- [ ] `assets.zig` accessors for boat/overlays/boss variants; extend `ArtAssets` with boat+overlays. Boat paint: `from_ramp=0` custom hull LUT, bbox `x=30,y=42,w=153,h=67`, outline 0 and porthole ramp 1 unchanged, outside-bbox base. Paint map: Abyss Teal 0→1; Foam White 5/10/15→10/15/15; Leviathan Black 5/10/15→0/5/10. Cosmetic index-order map (3/4/5 figureheads, 6/7/8 flags, 9/10/11 decals; highest owned per slot). Blit order base→paint→decal→figurehead→flag. Credits screen + copy. `--dump-grid --screen score|boat|credits`; art checksum = pre-present in-memory framebuffer dump. Commit `example(undersanded): boat cosmetics render + credits`.

### Task 5: `tier_m11_boss.sh` — DEMO GATE

- [ ] Tier: Tasks 1–4 tests; 5 saved boat builds asserting 5 different Phase 2 identities from saves; Field Record/variants rows; gate/telegraph; full demo loop golden (fresh → … → boss defeat → credits → score → dock, both Kill and Overkill bookkeeping); nest `TIER_M10.1`; non-vacuous. Run PASS. Commit `example(undersanded): M11 boss tier — DEMO GATE`.

**Gate:** full boss loop completable; all 5 variants triggerable from a save; Field Record written once; **demo shippable** (terminal + art). STOP-present the gate result for sign-off before M12.

### Task 6: Next-milestone amendment review (M12)

- [ ] Read `2026-11-12-undersanded-m12-audio-options-plan.md`; judge cue trigger points (kill/subdue/bosskill hooks) vs boss code. Amendment or "no amendment needed" in NOTES.md.
