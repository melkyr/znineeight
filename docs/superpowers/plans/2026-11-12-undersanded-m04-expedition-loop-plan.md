# undersanded M4 — calendar + expedition loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The full terminal expedition loop: calendar phases, travel ladder, per-zone/per-species respawn, rare-chance pipeline, node/dock rest, flee + Hull-0 Emergency Ascent, release/sell — dock → travel → fight → return playable end to end.

**Architecture:** `world.zig` owns the flat `World` (§25.7) + metronome; `expedition.zig` owns travel/fights/hold/loot flow (§6–§7); `encounter.zig` implements the §12 rare-chance pipeline over hardcoded T1 tables (data loader arrives M6 — tables live in `tables_t1.zig` as const rows with the final schema shape). Terminal screens: dock menu, map/ladder, node, fight (from M2), end-of-fight loot lines.

**Tech Stack:** Z98 → C89 `-fsafe`; std_file not yet needed (no save before M7); xorshift32 shared per-fight seeding `expedition_seed + fight_index * 77` (§25.5).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §5 (calendar/rest/renewal), §6 (loop, Hull 0, flee), §7 (loot flow), §9.7–9.8 (release/sell, lockout/echo), §11 (zone ladder table + Heavy placeholder), §12 (map, rare pipeline), §13 (T1 encounter tables), §25.7 (World), §36 (M4 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m03-sim-replay-plan.md`. NEXT: `2026-11-12-undersanded-m05-dock-economy-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior milestones. `game.zig` stays pure — World/calendar logic lives in `game.zig`/`expedition.zig` behind the same Action interface; screens only render. Zone table is data-shaped even though hardcoded (M6 swaps source, not schema). Capacity `MAX_ZONES=12`, `MAX_CREATURES=56` used from day one.

## File Structure

- `examples/z98/undersanded/world.zig` — World struct (§25.7), cycle/phase advance, `ready[]` availability (`cycle > ready || (cycle == ready && phase == Day)`), renewal writes (`respawn[0/1/2]` verbatim per §14.2 sub/kill/over), release bonus, lockout + global echo, wariness.
- `examples/z98/undersanded/expedition.zig` — depart/travel-out/fight-count/return, hold (secured parts), Hull 0 ascent, player flee, creature flee, early surface.
- `examples/z98/undersanded/encounter.zig` — pool build → rare pipeline (§12 5 steps) → weighted roll.
- `examples/z98/undersanded/tables_t1.zig` — zone ladder rows (§12: Z1 1, Z2 2, Z3 3, Z4 3, Z5 4, Z6 4, Z7 5, Z8 5, D 5) + encounter weights (§13) as const tables in the M6 schema shape.
- `examples/z98/undersanded/render_term.zig` — dock/map/node/fight-end screens.
- `examples/z98/undersanded/tests/world_test.zig`, `encounter_test.zig`, `tier_m4_loop.sh`, goldens.

## Review Focus

- Respawn double-counting across zones (instances are per-zone per-species) → test same species in Z1 vs Z2 with independent cooldowns.
- Rare pipeline order (lockout zeroes BEFORE bonus/echo arithmetic; floor 0; renormalize) → table-driven pipeline tests with 0/1/2 locked nodes and release bonuses 0/8/40/48.
- Renewal Day-of-cycle semantics (subdued Night of cycle 3, renewal 3 → available Day of cycle 6) → exact-cycle test.
- Loot hold integrity across ascent (current-fight loot dropped, earlier secured loot kept) → two-fight expedition test with forced Hull 0.
- Empty-pool Rest must be safe (no rough-sleep) while node Rest is not → condition-application test. **Rest/conditions wiring (owned here, math hooks exist at M2):** `pub fn rest(g: *GameState, kind: i32) void` — Hull heal +40 dock / +30 node / +30 empty-pool safe, with the condition written into `g.pending_cond`; node Rest grants a rough-sleep condition via 1 RNG draw (`rngRange(0,2)` → Drowsy/Shaky/Exposed) → copied into `FightState.cond` at next fight start (M2 math: Drowsy −20% Strike, Shaky margin ÷2, Exposed +25% incoming).

---

### Task 0: Preflight

- [ ] Confirm M3 gate green. Fix renewal semantics from spec §5/§14.2: respawn triple = spec `respawn[0/1/2]` used **verbatim** (subdue/kill/overkill) — no multiplying; creature-flee uses subdue-length; boss 20/40 handled M11.

### Task 1: World + calendar

**Interfaces (consumed by everything downstream):** `pub fn advancePhase(w: *World) void` (Day→Night→Day+cycle+1); `pub fn available(w: *World, zone, def) bool`; `pub fn markTaken(w: *World, zone, def, outcome: i32) void` (writes `ready` per outcome triple + wariness flag on release); `pub fn rareChance(w: *World, zone) i32` (locked→0 else base + min(release_bonus,40) − 5×locked_count, **clamp 0..100**; **base==0 → always 0** — releases accrue nothing in Z1, spec §12; if no rare candidates remain, rare weight redistributes to commons). Plus `pub fn markSeen(w: *World, def) void` (fight start or creature-flee).
- [ ] Unit tests: renewal day-of-cycle example exactly; per-zone instance isolation; release bonus +8 pp steps, cap +40, reset on rare encounter; lockout 5 cycles; global echo −5 pp per locked node; wariness +15 next rematch only (no stack). Implement `world.zig`. PASS. Commit `example(undersanded): world calendar + respawn + rare pipeline`.

### Task 2: Encounter pipeline

**Interfaces:** `pub fn rollEncounter(w: *World, zone, out: *i32) bool` (false = empty pool → safe Rest); §12 five steps with **largest-remainder apportionment** for integer weight scaling; draws from `w.rng_state` (1 draw per roll, §25.5); tables from `tables_t1.zig` (Z1–Z3 day/night rows exactly spec §13; Z4–Z8/D empty stubs).
- [ ] Table-driven tests: Z1 night weights sum 100 and renormalize when a species is on cooldown; Z3 night rare rows scale to `rareChance` while commons fill remainder; Z1 rareChance == 0 always. Implement `encounter.zig`. PASS. Commit `example(undersanded): encounter pipeline + T1 tables`.

### Task 3: Expedition flow

**Interfaces:** `pub fn depart(g: *GameState, zone: i32) *Expedition` (returns `&g.exp`; also does `g.world.rng_state` draw → `exp.seed`, then fight seeds use `exp.seed + fight_index*77`); `pub fn expeditionStep(g: *GameState, action: i32) void`; fight start copies `g.pending_cond` into `FightState.cond`. **Travel phase model (pinned):** Depart = 1 phase (the dock action, like every dock action) **+ travel_cost phases advanced instantly at departure** (Z2: 1+2=3 consumed on the way out; return likewise). No persistent in-transit state; the save 'in transit' block is vacuous but kept. 1 action/phase (§5), max fights `3 + boat[OXYGEN]` (3→6), boss route = 1 (M11); Hull persists (no dock heal); early surface = normal return travel; player flee / Hull 0 = drop current-fight loot, +1 phase, normal return, secured hold kept; creature flee = nothing kept, counts seen, subdue-length renewal, Pressure Hook prevents (flag checked in fight).
- [ ] Unit tests: full dock→Z2 (depart action 1 + travel 2)→fight→return (travel 2 + arrival) ledger of phases consumed; Hull-0 mid-expedition-2 keeps fight-1 hold; flee same; Heavy placeholder (Hull/Cargo T3 → +1 phase each way where travel ≥3 — boat tiers stubbed 0 in M4, test with injected tiers). Implement `expedition.zig`. PASS. Commit `example(undersanded): expedition loop + loot hold`.

### Task 4: Release/sell + terminal screens

**Interfaces:** end-of-fight prompt (Subdue only): Release → `markTaken(..., RELEASE)` + wariness, Sell → money += sale; per-fight line `Secured: …` (§7); dock menu (Refine/Upgrade/Craft/Buy/Rest/Depart — refine/craft/buy stub "not yet" until M5), map screen listing the zone ladder with travel costs + boss gate telegraph, node screen (Hunt/Rest/Surface).
- [ ] Implement screens + prompts. Golden: `--dump-grid` of dock + map + node screens (console mode, flag delivered at M3) byte-compared. Commit `example(undersanded): terminal dock/map/node screens + release/sell`.

### Task 5: `tier_m4_loop.sh`

- [ ] Tier: Task 1–3 unit tests + a scripted full expedition golden (seeded, exact log): depart Z2 → 2 fights (subdue+release, kill) → return → hold totals match; ascent variant keeps only fight-1 loot; empty-pool safe Rest round. Non-vacuous. Run PASS. Commit `example(undersanded): M4 loop tier`.

**Gate:** full dock→travel→fight→return terminal loop playable; every §6/§12 rule exercised by a test; screen goldens stable.

### Task 6: Next-milestone amendment review (M5)

- [ ] Read `2026-11-12-undersanded-m05-dock-economy-plan.md`; judge World fields (money, expertise, boat) and dock action surface vs M5 needs. Amendment or "no amendment needed" in NOTES.md.
