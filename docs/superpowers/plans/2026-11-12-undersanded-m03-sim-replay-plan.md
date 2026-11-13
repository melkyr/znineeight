# undersanded M3 — auto-sim + replay + rule tests — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `undtool.exe` console mode with `--sim`, `--replay`, `--test-rules`; the sim harness that proves the fight design in data; the M3 sim gate (rare-fight actions ≤12, Emergency Ascent rate ≤15%) — measured on all **5** M2 creatures incl. the 2 sim rares (Anemoniacus, Freezing Perch) so the rare-fight subset is real. Also delivers `--dump-grid` (M4 goldens depend on it).

**Architecture:** `sim.zig` drives `game.zig` headless with the §25.9 policy and aggregates metrics; `replay.zig` implements the v2 seed+action stream (spec §28) with byte-exact determinism; `ruletest.zig` runs every Rule op against scripted states with exit 0/1. All tooling lives behind `undtool.exe` flags (console subsystem, `gfxOpenMemory` + stdout).

**Tech Stack:** Z98 → C89 `gcc -m32` `-fsafe`; std_io/std_file; console link config from M1.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §25.9 (sim policy), §26 (console mode + CLI), §28 (replay v2), §34 (testing rows: sim, replay, determinism, decline-no-RNG, commons-never-prompt, surge caps), §36 (M3 row + levers).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m02-fight-core-plan.md`. NEXT: `2026-11-12-undersanded-m04-expedition-loop-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As M1/M2 (example-only, R1–R15, `-fsafe`, capacities fixed, no push, prior gates green). Console mode must not touch `game.zig` internals beyond the public Action/log surface — presentation never changes behaviour (spec §26).

## File Structure

- `examples/z98/undersanded/sim.zig` — policy player + metrics.
- `examples/z98/undersanded/replay.zig` — v2 text format read/write (`seed/zone/phase/tool` header + `A <action>` lines).
- `examples/z98/undersanded/ruletest.zig` — scripted rule-VM states.
- `examples/z98/undersanded/undtool.zig` + `build.sh` extension (build `undtool.nix` native too — the gate runner)  — flag dispatch: `--sim N --creature <id> --seed S` (`<id>` = def name string, e.g. `perch`), `--replay <file>`, `--test-rules`, `--dump-grid <file> --screen <id>`.
- `examples/z98/undersanded/tests/sim_test.zig`, `tests/tier_m3_sim.sh`, `tests/fixtures/replay_*.rep`, goldens.

## Review Focus

- Sim policy silently diverging from §25.9 (Shell exception, Kill path) skews every gate number → policy unit test with a scripted creature.
- Replay non-determinism (RNG state not reset per fight seed formula) breaks the golden → byte-compare replay output twice.
- Ascent-rate denominator confusion (fights vs expeditions) flatters the gate → assert the metric definition in the report line.
- Commons accidentally routing through the modal path → 200-fight prompt-counter test (spec §34 row).
- Surge cap regressions under repeated failures → sim asserts attack bonus ≤ +25 pp, speed ≤ +6 over all fights.

---

### Task 0: Preflight

- [ ] Confirm M2 tier green; take the M2 NOTES.md three-questions log as the hand-played baseline the sim must corroborate.

### Task 1: Replay format + determinism

**Interfaces (consumed by all later testing):** `pub fn replayWrite(path, seed: u32, zone, phase, tool, actions: []Action) void`; `pub fn replayRead(path, out: *Replay) bool`; format exactly spec §28 v2 grammar (pinned): `seed=98` / `zone=Z3` / `phase=night` / `tool=sonar` header + one `A <verb>` line per action, verb ∈ `strike|restrain|equipment|flee|attempt|decline`. **F and Esc both record as `decline`** (recorder dedupes; §9.3 they are identical). Ink/encounter draws derive from the seed (§25.5), never recorded.
- [ ] Unit test: write → read → identical actions/seed; replaying a stream twice yields byte-identical outcome+log (determinism, spec §34 "Subdue determinism"). Implement `replay.zig`. PASS. Commit `example(undersanded): replay v2 + determinism`.

### Task 2: `--sim` harness + metrics

**Interfaces:** `pub fn runSim(creature_id, n_fights, seed0) SimReport` — policy: subdue path `hp > 50% → Strike else Restrain` unless creature has Shell (`F_SHELL` flag per spec §25.3 vocabulary → Kill path); Kill path `res > 50% → Restrain else Strike`. Report fields: avg player actions (overall + **rare-fight subset**), bar-switch %, outcome distribution (subdue/kill/overkill/flee/ascent), avg surges per rare fight, **Emergency Ascent rate = ascents / fights**.
- [ ] Unit test: scripted-policy accuracy on a fixed creature (hand-computed 5-fight trace). Implement `sim.zig` + `undtool --sim` output (one report line per metric). PASS. Commit `example(undersanded): sim harness + metrics`.

### Task 3: `--test-rules`

**Interfaces:** `pub fn testRules() i32` — every cond op × effect op × timing (0/1) against scripted `FightState` fixtures; prints `rules_ok=<count>`; exit 0 all-pass / 1 any-fail (spec §34, T5).
- [ ] Implement `ruletest.zig` + flag. Tier asserts exit 0 and a non-zero count ≥ ops×effects tested. Commit `example(undersanded): --test-rules`.

### Task 4: Safety-net tests from spec §34

- [ ] Tests: (a) **decline costs no RNG** — RNG state byte-identical before/after F and Esc in modal fights; (b) **commons never prompt** — 200 sim fights vs commons, prompt counter == 0; (c) **surge caps** — across forced-failure runs, `surge_atk_applied` ≤ 1 (one +25 pp) and speed bonus ≤ +6. Wire into `tier_m3_sim.sh`. PASS. Commit `example(undersanded): M3 safety-net tests`.
- [ ] Implement `--dump-grid <file> --screen <id>` using `gfxDumpGrid` over the console screen; add its golden assertion to the tier. PASS. Commit `example(undersanded): --dump-grid console screens`.

### Task 5: `tier_m3_sim.sh` + the sim gate

- [ ] Tier: unit tests (Tasks 1–4) + `undtool --sim 200` per creature (5 runs incl. the 2 rares) with fixed seeds; asserts **rare-fight avg actions ≤ 12** (rare subset now measurable), **ascent rate ≤ 15%**, bar-switch % > 0, replay golden byte-match, `--test-rules` exit 0. Tuning levers if over gate (spec §36 M3 — **each lever pull = a spec amendment recorded in §38**): first raise rare subdue chance 60→65 in the hardcoded defs; second: Last Surge restore 30%→25%. **Never tune the coupling rule to compensate.** Record final numbers + any lever pulled in NOTES.md. Also assert `--dump-grid` output matches its golden. Run PASS (native `undtool.nix`; Wine run = evidence). Commit `example(undersanded): M3 sim tier + gate`.

**Gate:** sim thresholds met on all 5 creatures (rare subset = Anemoniacus + Freezing Perch) with data recorded; replay golden exact; `--test-rules` exit 0.

### Task 6: Next-milestone amendment review (M4)

- [ ] Read `2026-11-12-undersanded-m04-expedition-loop-plan.md`; judge whether World/encounter needs (availability, rare pipeline) change the sim report shape (e.g. per-zone runs). Amendment or "no amendment needed" in NOTES.md.
