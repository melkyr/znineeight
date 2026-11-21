# undersanded M11 — boss + score screen (DEMO GATE) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Derelict boss fight with 5 adaptive Phase-2 variants, the credits + three-panel score screen, and boat cosmetics rendering — the demo-complete gate: full boss loop completable, all 5 variants triggerable from a save.

**Architecture:** `boss.zig` layers the §15 spec onto `fight.zig` (phase bands, Speed/Attack tables, Cannon Volley scheduling, 5 variant scripts selected at engagement by dominant boat axis, Steel Plate volley-halving, Restrain disabled). `score.zig` owns the three panels (Field Record frozen-once, Variants Seen 5-bit mask, Last Run) persisted via M7 (`boss_variants_seen`, `boss_kills`, `runReset`). `render_art`/`render_term` score screens + boat render (blit order §30) with the 9 overlays + paint ramp.

**Tech Stack:** Z98 → C89 `-fsafe`; existing fight/save/render; `boss00` sprite × 5 ramp recolors (M10).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §15 (whole section: phases 300→200→100→0, Speed 7/10/12, Attack 10/15, Volley 15 every 2 rounds, 5 variants + tiebreak H>P>C>O>S + all-zero→Armor, kill 20 / overkill 40 respawn, gate 6 seen, Hull 150+ telegraph), §9.1 (boss subdue −1), §19 (score/Field Record/variants mask/Last Run/closing line), §38 P10 (`runReset`), §34 (variants-bit + Field Record rows), §40 (M11 copy items), §36 (M11 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m10-assets-pipeline-plan.md`. NEXT: `2026-11-12-undersanded-m12-audio-options-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Boss values verbatim: HP bands 300/200/100/0; P1 Speed 7 Attack 10; P2 Speed 10, Cannon Volley 15 every 2 rounds replacing standard, Steel Plate halves to 7 (integer); P3 Speed 12 Attack 15; variants — Armor: Strike 50% unless Plate · Sliver: full odd rounds / 25% even · Hoard: jettisons 1 secured part every 3 rounds · Drown: after round 10, +5 Hull/round beyond 10 · Blur: always first, double-strike every 3rd round. Variant chosen at engagement from `boat[5]` (max tier, tiebreak H>P>C>O>S, all-zero→Armor) — **bit set when Phase 2 is entered**, survives ascent. Restrain disabled with journal line "The machine has no will to break." Subdue chance −1. Overkill → 40-cycle respawn, kill → 20. Boss route: 1 fight max, gate 6 distinct non-boss seen, telegraph "Hull 150+ recommended."

## File Structure

- `examples/z98/undersanded/boss.zig` — boss fight layer + variant scripts.
- `examples/z98/undersanded/score.zig` — Field Record (written once), Variants Seen mask, Last Run, lifetime kills.
- `examples/z98/undersanded/render_art.zig` / `render_term.zig` (modify) — boss screen (5 ramp recolors), credits, score screens, boat render + overlays.
- `examples/z98/undersanded/tests/boss_test.zig`, `tests/tier_m11_boss.sh`, goldens.

## Review Focus

- Variant selection drift (must use cumulative-tier semantics P11 and the exact tiebreak; all-zero→Armor) → matrix test over all boat tier combinations.
- Variants bit set at the wrong moment (must set on **Phase 2 entry**, survive ascent/loss) → ascent-mid-P2 test.
- Volley scheduling (every 2 rounds, replaces standard, Plate halves) and Drown's round-10 escalation off-by-one → round-by-round trace goldens.
- Field Record overwritten on second kill (must be byte-identical) → spec §34 row as test.
- Hoard jettison corrupting the hold (drops **1 secured part every 3 rounds**, not a random loot wipe) → hold-count trace test.

---

### Task 0: Preflight

- [ ] Confirm `runReset` (M5) wired to boss kill; confirm boss def row in `data.z98` has `subdue_chance=-1` (M6 sentinel). Fix the 5 flavor lines (§40) and 12 cosmetic descriptions as copy in `[text]`.

### Task 1: Boss fight core (`boss.zig`)

**Interfaces:** `pub fn startBoss(s: *GameState, w: *World) void` — computes `boss_axis` via **one two-step helper** (`axisFromBoat`: all-zero→Hull; then `variantFromAxis`: Hull→Armor) — never hand-rolled inversion; tiebreak H>P>C>O>S; `pub fn bossPhaseUpdate(s)` — phase band transitions 300→200→100 with Speed/Attack swaps, sets variants bit on entering band 2; variant effects as §15 table (Steel Plate halves Volley → 7); Restrain action rejected + journal line; overkill/kill respawn writes (40/20) via `markTaken`.
- [ ] Unit tests: phase transitions at exactly 200/100; speed/attack per band; volley every 2 rounds replaces standard; Plate halves; each variant script trace (Armor 50%; Sliver odd/even; Hoard jettison cadence + hold decrement; Drown +5/round after round 10; Blur first-act + double-strike cadence); Restrain reject; subdue −1 gate never fires. Implement. PASS. Commit `example(undersanded): Derelict boss fight`.

### Task 2: Variant selection + gate + telegraph

- [ ] Tests: variant matrix (all tier combos → expected identity incl. all-zero→Armor and ties); gate: node locked until 6 distinct non-boss seen (M8 seen array), telegraph string on node screen; respawn 20/40 cycles. Wire boss node into expedition flow (zone D, travel 5, 1 fight max). Commit `example(undersanded): boss gate, telegraph, variant matrix`.

### Task 3: Score screen (`score.zig`)

**Interfaces:** `pub fn scoreSnapshot(w: *World) ScorePanels` — Field Record (cycles, field time = `World.field_phases`, seen N/N, rares N/N, boss kills, final Phase 2 identity, sub/kill/over counts, expertise, money, cosmetics N/12, decorated boat render); Variants Seen `3 / 5` with unseen grayed; Last Run (cycles, Phase 2 identity, outcome, actions, Hull spent) + lifetime kills; closing line "Thank you for playing. The ocean is still there."
- [ ] Tests: Field Record second-kill byte-identical (§34) — **elapsed-time field = `World.field_phases`, excluded from the byte-identity golden** (a live "time in the field" value would break byte-identity; no clock injection needed); variants bit survives ascent (§34); Last Run overwrites per engagement. Implement + screens (both modes). Commit `example(undersanded): three-panel score screen`.

### Task 4: Boat + cosmetics render

- [ ] Boat render with blit order base → paint ramp → decal → figurehead → flag (§30); owned cosmetics applied, unowned slots empty; 12 cosmetic descriptions from `[text]`; credits screen. Golden: `--dump-grid` score + boat (terminal) and an art checksum = **pre-present in-memory framebuffer dump** (M9 `gfxPxOpenMemory` path, software compose, native — never post-present/Wine readback). Commit `example(undersanded): boat cosmetics render + credits`.

### Task 5: `tier_m11_boss.sh` — DEMO GATE

- [ ] Tier: Tasks 1–3 tests + scripted boss kills with 5 different saved boat builds asserting 5 different Phase 2 identities triggerable from saves + Field Record/variants rows + boss gate + full demo loop golden (fresh install → … → boss kill → score). Non-vacuous. Run PASS. Commit `example(undersanded): M11 boss tier — DEMO GATE`.

**Gate:** full boss loop completable; all 5 variants triggerable from a save; Field Record written once; **demo shippable** (terminal + art). STOP-present the gate result for sign-off before M12.

### Task 6: Next-milestone amendment review (M12)

- [ ] Read `2026-11-12-undersanded-m12-audio-options-plan.md`; judge cue trigger points (kill/subdue/bosskill hooks) vs boss code. Amendment or "no amendment needed" in NOTES.md.
