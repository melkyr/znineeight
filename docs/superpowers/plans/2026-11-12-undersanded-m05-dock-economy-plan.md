# undersanded M5 — dock + economy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The complete dock: Refine + Expertise (yields + E2/E4 upgrade gates), 5 boat axes with cumulative totals + Heavy, 7 tools (activated/rigged, fragile), grudges, 12 cosmetics — and the full-game economy arithmetic closing in writing and in a real walk.

**Architecture:** `economy.zig` holds pure arithmetic (material ids, refine yields, upgrade cost tables §11, expertise gates, table self-checks); `dock.zig` implements dock actions behind one entry point (1 phase each, refusals free); `tools.zig` holds tool defs + equip/charge/break logic; `fight.zig` consumes tool effects that exist after M4. Persistence lives in the existing flat structs (`World.materials`, `World.tools_owned`, `World.tool_selected`, `Expedition.tool/charge/broken`, persistent `Expedition.hold`).

**Tech Stack:** Z98 → C89 `-fsafe`; all integer math (R11); module consts (R2).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §10 (tools, fragile, grudges + run scope), §11 (axes, totals, Heavy, upgrade costs, cosmetics), §16 (dock, expertise table + gates, refine/deep rule), §17 (economy targets), §21.5 (full-game rules), §38 P9–P11 + **P22 (M5 kickoff rulings)**, §36 (M5 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m04-expedition-loop-plan.md`. NEXT: `2026-11-12-undersanded-m06-data-loader-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Locked values copied exactly: axis totals Hull max 125/150/200, Speed +2/+5/+9 totals, Cargo +1/+2/+3 current-tier, Oxygen 3→4→5→6, Precision margin 10→15→20→25; upgrade cost table §11 verbatim; Expertise E2/E4 gate T2/T3 purchases in **every material spent** (P9); grudge run = until next Derelict kill (P10); Speed T3 needs Steel Fins ×2 (keystone part, not refined).

**M5 kickoff rulings (P22 — binding):**

- **Deep refine:** `refineYield` applies the deep −1 below E5 and may return **0**; a Refine still grants +1 expertise and is never refused for a 0 yield. Never clamp.
- **Material ids:** `MAT_CHITIN=1 … MAT_GLASS=7` (same numbers as their source parts 1–7); keystone parts are ids 8–9. `MaterialAmt.kind` is a material id (1–7) or a keystone part id (8–9); `canBuyTier` gates material kinds only; Upgrade spends `World.materials[kind]` for 1–7 and `Expedition.hold[kind]` for 8–9.
- **Persistent parts:** `Expedition.hold`/`hold_n` are the dock parts store — `depart` must **not** zero them. Craft/keystone costs consume the hold; Refine consumes all of one part type.
- **Tool scope:** M5 wires only behaviours that exist after M4 — armor negation (Plate), shell/resist-restrain bypass (Brine Net), discharge Hull damage negation (Coral Shield), flee prevention (Pressure Hook), stun (Electric Gland). Blind/decoy/ink/phasing and the Lure/Sonar protections/reveals belong to **M8**; M5 only stores/passes the tool flags (P22.2/P22.8).
- **Sonar lookahead:** implement `fight.peekCreatureAction` by copying the flat `FightState` (POD), drawing on the copy, returning the action, and discarding. Never mutate `GameState`, log, or world. M8 extends it with ink/decoy.
- **Tool lifecycle:** selection is `World.tool_selected` (0 = none), free; Depart copies it into `Expedition.tool`, sets `tool_charge` (1 for activated, 0 for rigged), clears `tool_broken`; `hunt` copies tool/charge/broken into `FightState` and sets `tool_active = 1` for a working rigged tool. Activated tools activate via EQUIP (spends the charge, lasts the fight); EQUIP with no usable tool/charge is refused without advancing a round.
- **Refusals:** any refused dock action costs no phase and no RNG.
- **Sale price:** read `CreatureDef.sale`; no duplicate price table.
- **Economy gate:** a real walk from **0 materials, E0** with a computed parts budget; assert materials **spent** = 111 + Steel Fins ×2, §17 totals self-consistent, all axes bought T1→T3. Full-run pacing stays M15.

## File Structure

- `examples/z98/undersanded/economy.zig` — `MAT_*`, `MaterialAmt`, `refineYield(expertise, is_deep) i32`, `canBuyTier(axis, tier, expertise, cost) bool`, `upgradeCost(axis, tier) [3]MaterialAmt`, `axisTotal(axis)` table check.
- `examples/z98/undersanded/dock.zig` — dock actions (Refine/Upgrade/Craft/Buy/Rest/Depart wrapper), phase ledger, refusal reasons, cosmetic unlock bits, tool selection.
- `examples/z98/undersanded/tools.zig` — 7 `ToolDef` rows (§10), craft costs, equip/charge/break helpers, `rigged(tool)`/`activated(tool)`.
- `examples/z98/undersanded/def.zig` (modify) — `World.materials/tools_owned/tool_selected`, `Expedition.tool/tool_charge/tool_broken`, `FightState.pending_stun`.
- `examples/z98/undersanded/game.zig` (modify) — `zeroWorld` resets new fields; `newGame` + `startFight` Expedition literals init tool fields.
- `examples/z98/undersanded/expedition.zig` (modify) — `depart` keeps the hold, resets/initialises tool state, clears `def_index`/`outcome`/`log_n`; `hunt` copies Speed/Precision + tool + grudge.
- `examples/z98/undersanded/fight.zig` (modify) — tool effects (Plate/Brine/Shield/Hook/stun), grudge armor, `peekCreatureAction`.
- `examples/z98/undersanded/nav.zig` (modify) — dock dispatch `r/u/c/b/e`, sub-menu keys, refusal notices.
- `examples/z98/undersanded/render_term.zig` (modify) — dock materials/expertise/tool lines, sub-menu screens; fight tool/charge line.
- `examples/z98/undersanded/tables_t1.zig` (modify) — `ToolRow`/`UpgradeRow`/`CosmeticRow` (M6 schema), cost + cosmetic rows.
- `examples/z98/undersanded/tests/economy_test.zig`, `tests/dock_test.zig`, `tests/tools_test.zig`, `tests/tier_m5_dock.sh`, `tests/fixtures/economy_full.md`.
- Golden updates: `tests/fixtures/dump_grid_dock.golden` (+ any new sub-menu golden).

## Review Focus

- Expertise gate applied to the wrong material set (must check **every** material spent, not the first) → gate tests with 2-material costs (Speed T1/T2, Oxygen).
- Axis totals misread as additive (must be 125/150/200, 12/15/19) → assert exact totals.
- Fragile break granularity (single hit ≥15, not cumulative) → 14/15 boundary at Precision 1/2.
- Grudge mask leaking across boss kills → `runReset` test; grudge persists across expeditions.
- Deep loss at the wrong expertise (only below E5) → E0=0, E1=1, E3=2, E5=3 for Lum/Glass.
- Refine consuming a batch the player still needs → no silent loss beyond the documented "all of one type" rule (B4 UX line open).

---

### Task 0: Preflight

- [ ] Record P22 in `NOTES.md` (M5 section) and list the exact files above. Pull the §11 cost table, §11 cosmetics table, and §10 tool table into `tables_t1.zig` structs (`ToolRow`, `UpgradeRow`, `CosmeticRow`). Confirm §17 totals: Chitin 19, Plate 6, Gland 21, Lum 5, Brine 26, Coral 26, Glass 8 = 111 + Steel Fins ×2; parts at E3: 41 + fins; cosmetics 12 × 3 = 2,100.
- [ ] Confirm the M4 baseline (`TIER_M4 PASS 47/0`, 1 Wine skip) and the v151 compiler path.
- [ ] Note deliberate M4 edits: `depart` stops zeroing `hold`/`hold_n` (no current test depends on a fresh hold; verify with the M4 tier).

### Task 1: Economy arithmetic (`economy.zig`)

**Interfaces:** `pub const MAT_CHITIN=1 … MAT_GLASS=7`; `pub const MaterialAmt = struct { kind: i32, amt: i32 }` (`kind` 0 = unused slot); `pub fn refineYield(exp: i32, is_deep: bool) i32` (base 1/2/2/3/3/3 for E0–E5; deep subtracts 1 below E5, **may be 0**, no clamp); `pub fn canBuyTier(axis: i32, tier: i32, expertise: *const [10]i32, cost: [3]MaterialAmt) bool` (tier 1 always true; tier 2 → every material kind's expertise ≥ 2; tier 3 → ≥ 4; kinds 8–9 skipped); `pub fn upgradeCost(axis: i32, tier: i32) [3]MaterialAmt` (§11 verbatim; unused slots `{0,0}`); `pub fn materialTotal(m: i32) i32` / expected §17 totals for the self-check.
- [ ] Unit tests: yield grid (7 materials × E0–E5, deep E0 = 0, E5 = 3); gate matrix (T2 fail E1 / pass E2; T3 fail E3 / pass E4; multi-material cost where one material is short → fail); `upgradeCost` sums per material equal the §17 table exactly (111) and Steel Fins = 2; cosmetics total 2,100; every cost row has 3 or fewer components. Implement. PASS. Commit `example(undersanded): economy arithmetic + expertise gates`.

### Task 2: Dock state, actions, UI (`def.zig`, `game.zig`, `expedition.zig`, `dock.zig`, `nav.zig`, `render_term.zig`)

**Interfaces:** `pub fn dockRefine(g, material) i32` (consumes all `hold[material]`, adds `refineYield` per part to `world.materials[material]`, expertise +1 capped 5, 1 phase); `pub fn dockUpgrade(g, axis) i32` (next tier only, cost + gate, spends materials/keystones, applies `boat[axis]`, 1 phase); `pub fn dockCraft(g, tool) i32` (parts from hold, sets `tools_owned` bit, 1 phase); `pub fn dockBuy(g, cosmetic) i32` (unlock bit + price, 1 phase); `pub fn dockSelectTool(g, tool) i32` (free, sets `tool_selected`); each returns 0 = success or a refusal code/reason string; refusals do not advance the phase.
- [ ] Add the new fields + reset paths (`zeroWorld`, `newGame`, `startFight`). `depart` keeps `hold`/`hold_n`, initialises `tool` from `tool_selected`, `tool_charge` (1 activated / 0 rigged / 0 none), `tool_broken = 0`; still clears `def_index`/`outcome`/`log_n`.
- [ ] `nav.zig` dock keys: `r` → refine sub-menu (materials 1–7), `u` → upgrade sub-menu (axes 1–5, next tier), `c` → craft sub-menu (tools 1–7), `b` → buy sub-menu (cosmetics 1–9, a–c), `e` → tool selection (owned), `t`/`d`/`q` unchanged; `Esc` backs out. `render_term.zig` renders the sub-menus + result/refusal line and dock materials/expertise/tool status; remove "not yet (M5)".
- [ ] **Refine UX guard (B4 ruling — rare batch only):** refining a deep/rare-sourced type (`Glow Polyp` → Luminescence, `Glass Pane` → Glass) is a two-press action: the first press prints `Rare batch: N parts -> M materials (expertise +1). Press again to confirm; Esc cancels.` (state `0 materials` explicitly when the yield is 0 below E5) and executes only on the second press; `Esc`/any other key cancels. Common types (`Shell Chip`, `Plate Scrap`, `Gland Sac`, `Brine Vial`, `Coral Bud`) execute immediately — never add a confirmation click to ordinary refining. Keystones are never refineable.
- [ ] Cosmetic unlock bits 0–11 (§11 order) are set on the first `depart` to Z1/Z2/Z3; boss bits set by M11. Buy refuses locked/owned/insufficient coins with the §11 grayed copy.
- [ ] Unit tests: one phase per success and zero for refusals (RNG/`field_phases` unchanged); refine consumes exactly all of one type + expertise cap; upgrade tier order + totals; craft deducts exact parts + owned bit; buy deducts coins + unlock gate; tool selection free. Nav/screens tests + updated dock golden. PASS. Commit `example(undersanded): dock state, actions, menus`.

### Task 3: Tools + fight integration (`tools.zig`, `fight.zig`, `expedition.zig`)

**Interfaces:** `ToolDef { id, kind (ACTIVATED/RIGGED), cost[3]DropLine, effect }`; `pub fn isRigged(tool) bool`; `pub fn canEquip(g, tool) bool`. `fight.peekCreatureAction(s, cdef, rules) i32` copies `s.fight` and returns the next creature action id (M5: attack, or flee when `pending_flee`). EQUIP: activated+charge+not broken → `tool_active=1`, charge−1 written back to `exp.tool_charge`; otherwise refused (no round, no RNG). Fragile: `boat[PRECISION] >= 2` and a single hit ≥15 Hull → `tool_broken=1`, `tool_active=0`, copied to `exp.tool_broken`.
- [ ] Effects wired now: Plate negates armor (+ boss volley flag stubbed for M11); Brine Net ignores shell/phasing restrain (uses existing `resist_restrain_pct`); Coral Shield skips `HULL_DMG` rule effects; Pressure Hook suppresses `pending_flee`; Electric Gland sets `pending_stun` so the creature skips one action. Grudge armor handled in Task 4.
- [ ] `hunt` copies `world.speedMax` → `fight.player_speed`, `world.precisionMargin` → `fight.margin_pct`, plus tool state (as Hull/cond).
- [ ] Tests: Plate 60→100 armor; Brine Net 50→100 restrain; Coral Shield vs Electric Eel/Anemoniacus discharge = 0 Hull; Pressure Hook blocks Mileel/Perch flee; stun skips one creature action; rigged active at fight start without charge use; activated charge 1 use/expedition + second EQUIP refused; fragile 14/15 at Precision 1/2; break survives across fights in the expedition and clears at the next Depart; `peekCreatureAction` leaves fight/rng/log byte-identical. Lure/Sonar blind/decoy/ink tests are **out of scope** (M8). PASS. Commit `example(undersanded): tools + fight integration`.

### Task 4: Grudges (run scope)

- [ ] `World.family_overkill_mask` is already set on overkill (M4). Add `pub fn runReset(w: *World) void` (clears the mask) for M11's Derelict kill. At fight start in `hunt`/`game.startFight`: if `cdef.grudge_kind != 0` and the family bit is set → Mileel kind adds +30 to `res` and `max_res`; Tunisteel kind sets `fight.flags |= F_GRUDGE_ARMOR` and `effectiveArmorPct` returns 30 unless Plate is active. Unit tests: grudge raises res+max_res (feeds surge ceil); persists across expeditions; `runReset` clears; Plate negates grudge armor; non-grudge families unaffected. Commit `example(undersanded): grudges with run scope`.

### Task 5: `economy_full.md` + `tier_m5_dock.sh`

- [ ] Write `tests/fixtures/economy_full.md`: the §17 table (111 materials, 41 parts at E3, 2,100 coins = 88 sales ≈ 29 expeditions ≈ 73 days) **extended per §21.5** (boat cost fixed; T2–T4 sale 20–100; deep sources per band) — projections only, no new content.
- [ ] **Real walk** (P22.7): start 0 materials, E0. Grant a per-material parts budget computed from `refineYield` to reach E4 and produce that material's §17 total (so the walk is reachable from a cold start, not from an E3 idealization). Refine to E4 with the real yields (deep may start at 0-yield), then buy every axis T1→T3 behind `canBuyTier`; assert materials spent = 111 exactly, Steel Fins spent = 2, every purchase succeeds, and no material goes negative.
- [ ] Tier `tests/tier_m5_dock.sh`: Tasks 1–4 tests + economy walk + **nested `tier_m4_loop.sh`** + dock golden(s). Non-vacuous (mutate a cost → fail). Run PASS. Commit `example(undersanded): M5 dock tier + economy fixture`.

**Gate:** the real E0 walk spends exactly 111 materials + Steel Fins ×2 and every axis reaches T3 behind its expertise gate; all dock actions cost 1 phase and refusals cost 0; tools change fight behaviour (not just damage) — re-check §41 question 2 with Plate now rigged (tempo turn no longer exists); full-run pacing is M15.

### Task 6: Next-milestone amendment review (M6)

- [ ] Read `2026-11-12-undersanded-m06-data-loader-plan.md`; judge the new row structs (`CreatureDef`, `ToolRow`, `UpgradeRow`, `CosmeticRow`) and capacities against the loader schema. Amendment or "no amendment needed" in NOTES.md.
