# undersanded M2 — fight core + rule VM — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The pure fight core: `game.zig` state machine + behavior rule VM + text-mode fight with 5 hardcoded creatures (Mystic Eel, Mystic Electric Eel, Steel Tuna + sim rares Anemoniacus, Freezing Perch), playable 20× by hand, answering the spec's three design questions with "yes".

**Architecture:** `game.zig` is pure (spec §22 hard rule): takes `*GameState` + `Action`, mutates flat structs, appends to a fixed log — no I/O, no rendering. `fight.zig` implements the §9.2 resolution order; `behavior.zig` is the rule VM (§25.6). A thin terminal loop (`input.zig` + `render_term.zig` minimal fight screen) drives it for the manual plays.

**Tech Stack:** Z98 (zig1 → C89, `gcc -m32`, `-fsafe`), std_gfx cell tier / std_io, xorshift32, i32 math only (R6/R7/R11).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §8 (combat), §9 (outcomes incl. §9.1–9.6), §25.2–25.6 (structs, fixed point, RNG, rule VM), §24 (rules), §36 (M2 row), §41 (three questions).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m01-std-audit-plan.md`. NEXT: `2026-11-12-undersanded-m03-sim-replay-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

- Spec binding + Global Constraints of M1 carry over verbatim (example-only, R1–R15, `-fsafe`, capacities spec §25.1 fixed, no push, keep prior gates green).
- `game.zig` performs **no I/O and calls no rendering function** — enforced by review; everything testable headless.
- All tuning constants are module-level (R2); every `switch` has `else` (R3); explicit field init everywhere (R8); no floats — `applyPct` truncation, integer ceil `(max*LAST_SURGE_RESTORE_PCT+99)/100` (§9.5; 25% after the M3 lever).
- RNG: xorshift32 only; **full draw-accounting per spec §25.5 contract** (subdue 1 draw `rngRange(1,100)<=chance`; decline 0; ink 1 draw `rngRange(0,2)` Strike/Restrain/Equipment never Flee; rough-sleep 1 draw; damage 1 draw/roll). Zero-seed guard: state 0 → reseed `0x9E3779B9`. Warm-up: 3× `rngNext` before first draw. `rngRange` uses explicit `@intCast` pairs (R13 — the sketch below is not literally compilable).

## File Structure

- `examples/z98/undersanded/def.zig` — capacities (§25.1), `DropLine`, `CreatureDef`, `FightState` (§25.2–25.3), outcome/action/flag consts.
- `examples/z98/undersanded/math.zig` — `applyPct`, `ceilPct30`.
- `examples/z98/undersanded/rng.zig` — `rngNext`, `rngRange`.
- `examples/z98/undersanded/behavior.zig` — `Rule`, rule-VM interpreter, one-shot crossing detection.
- `examples/z98/undersanded/fight.zig` — action resolution (§9.2), coupling (§8.5), overkill (§8.6), subdue gate + modal/silent + Last Surge (§9.1–9.5), turn order (§8.4).
- `examples/z98/undersanded/game.zig` — pure state machine (`gameStep(state, action)`), fixed-size combat log.
- `examples/z98/undersanded/creatures_t1.zig` — 5 hardcoded defs + their rule rows (3 commons + 2 sim rares).
- `examples/z98/undersanded/input.zig` / `render_term.zig` — minimal fight screen + keys (S/R/E/F).
- `examples/z98/undersanded/tests/fight_test.zig`, `tests/rulevm_test.zig`, `tests/tier_m2_fight.sh`.

## Review Focus

- Resolution order drift (death before subdue before creature action) corrupts every later outcome test → pin §9.2 order explicitly in tests.
- Surge stacking: attack bonus must apply once (+25 pp), speed cap +6 — the accumulate-then-apply-once rule (§9.5) → unit tests with repeated failures.
- `max_res` must include grudge/wariness raises before the 30% ceil restore → restore test with raised max.
- Ties in turn order go to the player; speed modifiers apply the moment their condition is met → ordering test at equal speed and at HP<30% Speed+4 (Steel Tuna).
- Decline must not consume RNG (byte-identical state before/after) → test `rng_state` equality across F/Esc.

---

### Task 0: Preflight

- [ ] Confirm M1 tier green and NOTES.md G-table. Fix the 3-creature stat rows from spec §14.2 (Mystic Eel 70/80/10/6 subdue 95; Mystic Electric Eel 80/100/16/7 subdue 95; Steel Tuna 120/70/6/8 subdue 95) and behaviors from §14.3 (Despair +8; Thrash +8 + Discharge 8 Hull on Resolve<50% crossing; Armor Strike 60% + Speed+4 at HP<30%). Add the two flex-rare stat rows: Anemoniacus 95/115/7/9 subdue 60 sale 50 respawn 6/18/30; Freezing Perch 105/95/13/10 subdue 60 sale 55 respawn 6/18/30.

### Task 1: Definitions + math + rng

**Interfaces:** as in File Structure; `applyPct(v, pct) = (v*pct)/100`; `rngRange(s, lo, hi)` = spec §25.5 version with `@intCast` (u32→i32 both sides). **State/log (spec §25.3):** `GameState` = fight + world + `LogEntry[MAX_LOG=64]` drop-oldest + expedition flat fields; `LogEntry = {class, msg_id, a, b}` rendered via message table (Last Surge flavor line = §40 copy as a msg_id row — authored here). FightState carries the effect state fields: `rule_consumed: u32`, `pending_blind/ink/flee: i32`, `active_armor_pct/active_resist_restrain: i32`; `flags` uses the spec F_* vocabulary. **Coupling regen = REPLACE** (row `+8` replaces the default +5, never adds). **bar-switch counter:** increments when the player's action changes the active bar (Strike↔Restrain); Equipment/Flee/Attempt do not switch. **Rough-sleep hooks:** FightState condition fields (`cond: i32`) with math: Drowsy −20% Strike, Shaky margin ÷2, Exposed incoming +25% — granted by game layer at M4, math hooks land at M2. **danger_hp clamp ≥0** for display/tests.
- [ ] Unit tests: `applyPct` truncation cases (25→37.5 patterns with pct 150/60); `ceilPct30` == ceil for max_res 50…195; xorshift known sequence for seed 98. Implement `def.zig`/`math.zig`/`rng.zig`. PASS. Also: rng determinism test (same seed + action stream → identical log bytes incl. msg_ids); subdue mapping test (roll 1–60 vs 60% succeeds, 61–100 fails); zero-seed reseed test. Commit `example(undersanded): fight defs, fixed point, xorshift32`.

### Task 2: Rule VM (`behavior.zig`)

**Interfaces:** `pub const Effect = struct { op: i32, a: i32, b: i32 };` and `pub fn ruleFire(r: Rule, prev_hp, now_hp, prev_res, now_res, round, consumed: *u32, bit: i32) ?Effect` returns it — one-shot rules fire when `prev >= threshold && now < threshold` (then set consumed bit); persistent rules report effect every evaluation; ops per §25.6 (`HP_BELOW, RES_BELOW, ROUND_MOD, FIRST_ROUND, ALWAYS` × `REGEN_RES, REGEN_HP, HULL_DMG, SET_ARMOR, SET_FLEE, SET_BLIND, SET_INK, ADD_SPEED, MULT_ATK, MISS_STRIKE`).
- [ ] Unit tests per op and per timing; one-shot fires exactly once across a crossing + repeated evaluation; `else => {}` fallback on unknown op (R3). Implement. PASS. Commit `example(undersanded): behavior rule VM`.
- [ ] G12 resolved by **reuse**: `std_math` already provides `min`:1, `max`:6, `abs`:21, `clamp`:26 (plus `minU`/`maxU`/`clampU`) — do not add game-side copies to `math.zig`. Add unit assertions for the reused helpers (clamp edges, `abs(-2147483647)`) in the M2 test driver. PASS. Commit `example(undersanded): i32 math reuse checks`.

### Task 3: Fight resolution (`fight.zig` + `game.zig`)

**Interfaces:** `pub fn gameStep(s: *GameState, a: Action) void` (Action = `{kind, arg}` kinds: STRIKE/RESTRAIN/EQUIP/FLEE/ATTEMPT/DECLINE/…); `FightState` per §25.3; `pub fn startFight(s: *GameState, def_index: i32) void` seeds `rng_state = expedition_seed + fight_index * 77` (hardcode `expedition_seed=98`, `fight_index=0` for M2).
- [ ] Unit tests pinning §9.2 order exactly: (a) lethal Strike with overshoot ≥ margin → OVERKILL, fight ends, creature does not act; (b) Resolve≤0 & HP>0 & chance success → SUBDUE, creature does not act; (c) chance failure → Last Surge (res `(max_res*30+99)/100`, atk +25pp once, speed +2 cap +6) and creature acts that round; (d) Thrash/Despair regen at end of round with row overrides **REPLACING** default +5 (+8/+10/+12); (e) overkill margin `max_hp*margin_pct/100`, Kill when overshoot < margin; (f) danger_hp `25 - margin` display value; (g) turn order tie → player first; Steel Tuna HP<30% → Speed 10 vs 10 tie → player, Speed +4 applies immediately; (h) DECLINE sets `subdue_declined`, consumes no RNG; gate re-fires only when `subdue_declined==false`.
- [ ] Implement `fight.zig`/`game.zig` flat, module-level consts only. PASS. Commit `example(undersanded): fight resolution core`.

### Task 4: 5 creatures + minimal text UI

**Interfaces:** `creatures_t1.zig` exports `pub const DEFS: [5]CreatureDef` + rule rows; `render_term.zig` draws the fight frame (HP/RESOLVE/HULL bars with numbers, log lines, `[S]trike [R]estrain [E]quipment [F]lee`); `input.zig` maps keys → Action, including subdue modal `[A] [F] [Esc]` (rare/named path exists in code, unused by these 3 commons — silent auto-roll).
- [ ] Implement defs from Task 0 + rule rows (Despair/Thrash overrides, discharge one-shot, armor below 30% persistent; Anemoniacus Thrash +10 + Discharge 10 at HP<50% crossing; Freezing Perch Despair +8 + flee-next-turn when a single hit >35% max HP (37), strict `>` boundary). Minimal screen via std_io/std_gfx cell. Manual smoke: complete a fight each way (Subdue/Kill/Overkill). Commit `example(undersanded): 5 creatures + text fight screen`.

### Task 5: `fight_test.zig` + `tier_m2_fight.sh`

- [ ] Tier runs the unit tests (Tasks 1–3 assertions) headless plus a scripted full fight (fixed seed, fixed action stream) asserting the exact outcome + log bytes. Non-vacuous. Run PASS. Commit `example(undersanded): M2 fight tier`.

**Gate:** tier green; 20 manual fights played (log in NOTES.md); the three questions (spec §41) answered **yes** in NOTES.md with observations. **If any answer is no: STOP-present — fix the fight before M3.**

### Task 6: Next-milestone amendment review (M3)

- [ ] Read `2026-11-12-undersanded-m03-sim-replay-plan.md`; judge `game.zig`'s Action/log surface against M3's sim/replay needs (needs: full action stream incl. A/D, deterministic RNG state visibility). Amendment or "no amendment needed" recorded in NOTES.md.

---

## Post-gate tasks (user-authorized after the final review)

### Task 6.1: Post-gate hardening

**Files:** `examples/z98/undersanded/creatures_t1.zig` (defAt invalid index), `rng.zig` (hi<lo guard), `tests/fight_test.zig` (20-fight table asserts declines), `tests/tier_m1_std.sh` (stdin redirect `</dev/null` on undtool invocations), `NOTES.md`.
- [ ] Explicit failure instead of the silent `defAt` fallback (invalid index traps with a clear panic); `rngRange` rejects `hi < lo` explicitly. Pin `declines` in the 20-fight table. Add `</dev/null` so interactive TTY runs cannot hang the M1 tier. No behavior change on valid inputs. PASS; commit `fix(undersanded): post-gate hardening`.

### Task 6.2: Freezing Perch flee reachability (user decision: option a)

**Files:** spec §14.3 row, `m08` plan row, `creatures_t1.zig` (`flee_th`), `NOTES.md`.
- [ ] Change Freezing Perch's trigger from "single hit >35% max HP (37)" to **">20% max HP (21)"** (105×20% = 21; strict `>` means hits of 22–25 trigger, 21 does not). Update spec §14.3 + m08 plan wording to match. Test both sides of the boundary. PASS; commit `fix(undersanded): make Freezing Perch flee reachable`.

### Task 6.3: lin_bin player artifact (user request)

**Files:** `lin_bin/README.md` (committed); `lin_bin/undtool.exe` + `sample.txt` (built, untracked; copied to the main checkout after merge).
- [ ] Build via `build.sh`, place `undtool.exe` + `sample.txt` + `README.md` in `lin_bin/`. README: wine invocation, 1–5 creature chooser, key map (S/R/E/F; modal A/F/Esc), and the three §41 questions to observe. Verify `wine lin_bin/undtool.exe` starts. No binary committed. Commit `docs(undersanded): lin_bin player instructions`.
