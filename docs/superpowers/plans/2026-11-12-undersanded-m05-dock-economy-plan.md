# undersanded M5 — dock + economy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The complete dock: Refine + Expertise (yields + E2/E4 upgrade gates), 5 boat axes with cumulative totals + Heavy, 7 tools (activated/rigged, fragile), grudges, 12 cosmetics — and the full-game economy arithmetic closing in writing and in sim.

**Architecture:** `dock.zig` implements dock actions behind the same Action interface (1 phase each); `economy.zig` holds pure arithmetic (refine yields, upgrade cost tables §11, expertise gates, sale prices) as testable functions; `tools.zig` holds tool defs + equip/charge/break logic consumed by `fight.zig` (tool effects wire into fight resolution). Tables stay in `tables_t1.zig` schema shape.

**Tech Stack:** Z98 → C89 `-fsafe`; all integer math (R11); module consts (R2).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §10 (tools, fragile, grudges + run scope), §11 (axes, totals, Heavy, upgrade costs, cosmetics), §16 (dock, expertise table + gates), §17 (economy targets), §21.5 (full-game rules), §38 P9–P11 (locked answers), §36 (M5 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m04-expedition-loop-plan.md`. NEXT: `2026-11-12-undersanded-m06-data-loader-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Locked values copied exactly: axis totals Hull max 125/150/200, Speed +2/+5/+9 totals, Cargo +1/+2/+3 current-tier, Oxygen 3→4→5→6, Precision margin 10→15→20→25; upgrade cost table §11 verbatim; Expertise E2/E4 gate T2/T3 purchases in **every material spent** (P9); grudge run = until next Derelict kill (P10); Speed T3 needs Steel Fins ×2 (keystone part, not refined).

## File Structure

- `examples/z98/undersanded/economy.zig` — `refineYield(expertise, is_deep) i32`, `canBuyTier(...) bool`, `upgradeCost(axis, tier) [3]MaterialAmt`, sale prices.
- `examples/z98/undersanded/dock.zig` — Refine (all parts of one type, +1 expertise), Upgrade, Craft, Buy cosmetic, Rest (+40 Hull), Depart.
- `examples/z98/undersanded/tools.zig` — 7 tool defs (§10 table), equip-at-depart (1 slot), activated 1 charge/expedition, rigged passive, fragile rule (Precision T2+, hit ≥15 Hull → tool_broken).
- `examples/z98/undersanded/fight.zig` (modify) — consume tool effects: stun 1 turn, armor negate, volley-halve (boss, M11 — stub flag), flee prevent, shell/phasing-bypass on Restrain, discharge negate, blind/decoy prevent, ink prevent, Sonar reveals.
- `examples/z98/undersanded/tests/economy_test.zig`, `tools_test.zig`, `tier_m5_dock.sh`, `tests/fixtures/economy_full.md` (the arithmetic table).

## Review Focus

- Expertise gates applied to the wrong material set (gate must check every material spent, not just the first) → gate tests with 2-material costs.
- Axis totals misread as additive (+25/+50/+100 cumulative→200 max, never 275) → assert max_hull 125/150/200 exactly.
- Fragile-tool break at the wrong granularity (breaks on hit ≥15 **in one hit**, not cumulative) → single-hit boundary tests 14/15.
- Grudge mask leaking across boss kills (run boundary) → test mask cleared on kill, persisted across expeditions.
- Deep-material loss applied at wrong expertise (lose 1/part **below E5** only) → refine tests at E3/E5 for Glow Polyp and Glass Pane.

---

### Task 0: Preflight

- [ ] Pull the exact cost table (§11) and cosmetics table (§11) into `tables_t1.zig` rows; confirm §17 totals: Chitin 19, Plate 6, Gland 21, Lum 5, Brine 26, Coral 26, Glass 8 = 111 + Steel Fins ×2; parts at E3: 41 + fins.

### Task 1: Economy arithmetic (`economy.zig`)

**Interfaces (consumed by dock + M15 sims):** `pub fn refineYield(exp: i32, is_deep: bool) i32` (yields per §16: E0=1, E1=2, E2=2, E3=3, E4=3, E5=3; deep materials −1 per part below E5); `pub fn canBuyTier(axis, tier, expertise: *const [10]i32, cost: [3]MaterialAmt) bool` (tier ≥2 → each **material**'s expertise ≥2; tier 3 → ≥4; keystone kinds ignored). `pub fn upgradeCost(axis, tier) [3]MaterialAmt` per §11 (3 fixed slots — Speed T3 = Glass 4 + Gland 4 + Steel Fins ×2 has 3 components; unused slot = `{kind=NONE, amt=0}`; keystone parts (Hooked Barbel, Steel Fins) **skip the expertise gate** — `canBuyTier` gates materials only).
- [ ] Unit tests: refine yield grid (7 materials × E0–E5 incl. deep loss at E3 vs E5); gate matrix (T1 pass at E0, T2 fail at E1 pass at E2, T3 fail at E3 pass at E4); full-cost sum == 111 + Steel Fins 2. Implement. PASS. Commit `example(undersanded): economy arithmetic + expertise gates`.

### Task 2: Dock actions (`dock.zig`)

**Interfaces:** Actions DOCK_REFINE(material), DOCK_UPGRADE(axis), DOCK_CRAFT(tool), DOCK_BUY(cosmetic), DOCK_REST, DEPART — each consumes exactly 1 phase (assert in tests) — **Depart = the 1 dock-action phase + travel_cost phases advanced instantly** (M4 invariant: Z2 out = 1+2; ledger goldens in M4/M5 agree on this one rule); Refine converts **all** parts of one type and +1 expertise (cap 5); **keystones are not refineable** (Hooked Barbel / Steel Fins used as-is); refuse Refine when computed yield would be 0 (deep at E0) with a reason string; Upgrade spends materials, applies axis totals (§11: Hull 125/150/200, Speed 12/15/19 — cumulative, replacing not adding), respects Heavy flag (Hull T3 or Cargo T3 → travel +1 where cost ≥3 — integrates M4's injected-tier test); Craft builds owned-forever tools from parts; Buy spends coins (0 start, grayed until "Reach Z1/Z2/Z3" or Kill Derelict per §11 cosmetics table).
- [ ] Unit tests per action incl. phase ledger; craft cost check rejects missing parts (Hooked Barbel keystone consumed as-is). Implement. PASS. Commit `example(undersanded): dock actions`.

### Task 3: Tools + fight integration (`tools.zig`, `fight.zig`)

**Interfaces:** `ToolDef` rows §10 (kind ACTIVATED/RIGGED, part cost, effect id, counters list); `equipTool(state, tool)` at depart; EQUIP action spends activated charge (0 charge → rejected with reason); fragile: `onHullHit(state, dmg)` breaks tool when boat[PRECISION]≥2 && dmg ≥ 15; **break clears at next Depart** (rest of expedition only).
- [ ] Unit tests: stun skips creature action 1 turn; armor negate (Steel Tuna Strike 60%→100% with Plate); Brine Net bypasses Shell/Phasing Restrain 50%; Coral Shield negates discharge; Pressure Hook blocks flee; Lure blocks blind/decoy; Sonar blocks ink; fragile boundary 14/15 at Precision 0/1/2; **reveal tests**: Sonar shows exact Speed + next action (Ghost-Ray flip visible), Lure shows phase pattern / real targets behind decoys. Implement. PASS. Commit `example(undersanded): tools + fight integration`.

### Task 4: Grudges (run scope)

- [ ] `World.family_overkill_mask` set on any family overkill; named defs carry `grudge_family/grudge_kind/grudge_value` (Mileel +30 Resolve incl. max_res; Tunisteel armor 50%→30% flat); mask **cleared on Derelict kill** (M11 will call `runReset`; expose `pub fn runReset(w: *World) void` now). Unit tests: grudge raises res+max_res (feeds surge ceil), persists across expeditions, clears at runReset, Plate negates grudge armor. Commit `example(undersanded): grudges with run scope`.

### Task 5: `economy_full.md` + `tier_m5_dock.sh`

- [ ] Write `tests/fixtures/economy_full.md`: the §17 table (111 materials, 41 parts at E3, ~12–15 hunts at 3–6 parts/hunt, 2,100 coins = 88 sales ≈ 29 expeditions ≈ 73 days) **extended for the full game per §21.5** (boat cost fixed; T2–T4 sale prices 20–100; deep sources per band). Tier asserts: Task 1–4 tests green + a scripted economy walk (drops → refine at rising expertise (yield grid applied at each E) → buy all 5 axes to T3 with gates) succeeds; **the invariant asserted is the §17 totals — 111 materials + Steel Fins ×2 closed**, not a fixed hunt count (hunts vary with yields; 12–15 is the M15-measured target). Run PASS. Commit `example(undersanded): M5 dock tier + economy fixture`.

**Gate:** economy arithmetic closes for the full game (fixture walk closes; full-run sim is M15's job); all dock actions cost 1 phase (Depart = 1 + travel cost); tools change fight behaviour (not just damage) — check against spec §41 question 2.

### Task 6: Next-milestone amendment review (M6)

- [ ] Read `2026-11-12-undersanded-m06-data-loader-plan.md`; judge the table row shapes (defs, tools, costs, cosmetics) against the loader schema. Amendment or "no amendment needed" in NOTES.md.
