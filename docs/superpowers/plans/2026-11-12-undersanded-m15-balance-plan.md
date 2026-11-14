# undersanded M15 — full-game balance pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The numbers close for a **full run**: economy arithmetic, calendar pacing ("something always available"), playtime target measured (S3), and per-tier fight metrics — tuning applied via data only.

**Architecture:** Extend the M3 sim harness into a **full-run simulator**: a policy-driven playthrough across the whole game (expedition planning policy + fight policy + dock policy) measuring days-to-boat-max, days-to-cosmetics, dead days, per-tier fight metrics, material flow. All tuning lands in `data.z98` numbers only — no code changes unless a metric is unmeasurable (STOP-present first).

**Tech Stack:** `undtool` extensions (Z98); `economy_full.md` (M5/M13) as the arithmetic mirror; NOTES.md ledger.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §17 (economy targets), §21.3 (fight-length gates ≤12 T1/T2, ≤14 T3, ≤15 T4), §21.5 (economy rules), §5/§12 (calendar pacing), §36 (M15 row; levers: rare chance 60→65, surge restore 30→25 — coupling untouchable), §38 S3 (playtime target set here), §34 (balance row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m14-t234-assets-plan.md`. NEXT: `2026-11-12-undersanded-m16-win98-ship-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. **Pace is sacred (G6):** targets — boat max ~12–15 hunts / ~3 in-game weeks focused; cosmetics ≈88 sales / ~73 days; full 100% ≈3 in-game months (§17). Fight length gates ≤12 T1/T2, ≤14 T3, ≤15 T4 (P20); **boss feasibility ≥50% at Hull 150+Plate, ≥90% at max Hull**. "Something is always available; something is always a few days away" (v0.1 §18 risk table) — no dead days. Tuning only in data rows; the coupling rule is never tuned to compensate (M3 constraint stands). Whatever the sims measure becomes the **S3 playtime target**, recorded in NOTES.md and the spec's TBD table disposition.

## File Structure

- `examples/z98/undersanded/simfull.zig` — full-run policy simulator + report.
- `undtool` flags: `--sim-full <days-cap> --report <file>`.
- `examples/z98/undersanded/data.z98` (tuning edits only), `tests/fixtures/economy_full.md` (final numbers), `tests/tier_m15_balance.sh`.

## Review Focus

- Policy artifacts mistaken for design flaws (a dumb expedition policy manufactures "dead days") → policy unit tests + a second policy variant as control before any tuning.
- Economy double-counts (Cargo bonus on every drop line, expertise yield applied twice) → arithmetic cross-check: sim totals vs `economy_full.md` hand math.
- Rare-chance tuning breaking T1 demo gates (M3 thresholds must still hold after M13–15 tuning) → re-run M3/M13 tier gates in this milestone's tier.
- Playtime target gamed by policy speed (report per-policy numbers; S3 must cite the policy) → report includes policy id.
- Ascent/flee loops inflating days (emergency ascent +1 phase accounting) → phase-ledger assertions.

---

### Task 0: Preflight

- [ ] Re-run M3 and M13 tier gates as the pre-tuning baseline (must be green). Copy current metric numbers into NOTES.md.

### Task 1: Full-run simulator

**Interfaces:** `pub const PolicyId = { AGGRESSIVE=0, CASUAL=1 };` `pub fn simFull(days_cap: i32, seed: u32, policy: PolicyId) FullReport` (the report cites the policy id) — fields: days to boat T3×5, days to 12 cosmetics, 100% days, **dead-day count — opportunity-based (rewritten): a phase where NO reachable zone has an available creature encounter** (dock actions like Rest/Refine/Depart do NOT count as available opportunities; Rest being always clickable must not zero this metric). Plus rare-availability exposure (phases where a rare was reachable but locked), overkill rate per tier, dock+refine phases in the phase ledger., per-tier avg fight actions / ascent rate / overkill rate, material income vs `economy_full.md` expectations, expedition phase ledger. Policies: `AGGRESSIVE` (fights whenever available, subdue-focused) and `CASUAL` (rests, explores, mixes outcomes).
- [ ] Policy unit tests on a 30-day hand trace. Implement `simfull.zig`. PASS. Commit `example(undersanded): full-run simulator`.

### Task 2: Measure + tune

- [ ] Run both policies to 100% or `days_cap` over a **≥16-seed sweep**; report medians + bands; use **common-random-numbers** for before/after tuning comparisons. Compare to §17 targets (boat ~3 weeks focused — **ledger includes dock/refine phases**, 100% ≈3 months). **Precedence (pinned):** §17 hand targets are the priors; if measured medians land outside ±15% after in-band tuning → STOP-present (tune harder vs redefine target = user call; never silently redefine). Tune `data.z98` only. **Lever adjudication (spec §38 P15):** in-band = encounter weights, sale prices within §21.3 bands, drop counts within §21.5. **Spec-fixed (change only via spec amendment):** respawn triples, subdue base 95/80/60/−1, surge restore 30%, global damage ranges, coupling rule. The M3 levers (rare 60→65, surge 30→25) are pre-authorized spec amendments if pulled. **Dead days = 0 required** (opportunity definition). Re-run M3/M13 gates after every tuning batch. Record every change in NOTES.md (before/after). Commit `example(undersanded): balance tuning pass`.

### Task 3: S3 playtime target + arithmetic close

- [ ] Set S3 from measured data (cite policy + seed set); final `economy_full.md` matches the sim within stated tolerance (incl. any new keystone parts from M13 in the re-derived totals); §21.3 fight-length check per tier (≤12/12/14/15) + boss-feasibility re-run recorded. Update the disposition table in NOTES.md (S3 no longer TBD). Commit `example(undersanded): playtime target + economy close`.

### Task 4: `tier_m15_balance.sh`

- [ ] Tier: Task 1 tests + **≥16-seed sweep runs** (both policies) asserting: dead days 0 (opportunity-based — **hand-traced manufactured dead-day fixture must be detected**, killing the vacuous-metric failure mode); boat and cosmetics medians within ±15% of targets; per-tier fight length within P20 gates (≤12/12/14/15); **boss-feasibility re-run meets ≥50%/≥90% kill-rate targets**; M3/M13 gates still green; economy fixture matches sim. Non-vacuous. Run PASS. Commit `example(undersanded): M15 balance tier`.

**Gate:** §17-style arithmetic closes for the full run; no dead days; no unobtainable material; S3 recorded.

### Task 5: Next-milestone amendment review (M16)

- [ ] Read `2026-11-12-undersanded-m16-win98-ship-plan.md`; judge release-candidate scope (which tiers must be green on the RC, artifact list). Amendment or "no amendment needed" in NOTES.md.
