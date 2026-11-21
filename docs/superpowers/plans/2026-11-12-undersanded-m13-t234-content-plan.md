# undersanded M13 — Tier-2–4 content — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The full-game roster: the T2–T4 rows (shape 4–6 commons + 1 Named + 5 rares per tier = **30–36 rows**; the Task 0 ledger fixes the exact count and every golden uses that number, never "48-ish") under the §21 taxonomy, Z4–Z8 encounter tables, named keystones + grudges, journal/legends additions, material-source re-derivation — full roster loads and per-tier sims pass.

**Architecture:** Pure authoring against the frozen schema (M6/M8): rows in `data.z98`, behaviors as §25.6 rule rows + named fields, encounters as zone/phase/weight rows. The variant taxonomy (12 adjectives × 10 families) supplies fallback names; **rares are unique per band — invented species names encouraged (P16, e.g. Anemoniacus / Freezing Perch style); no rare is shared across tiers.** per-tier shape 4–6 commons + 1 Named + 5 rares; **one boss for the whole game** (no tier bosses).

**Tech Stack:** Z98 → C89 `-fsafe`; M3 sim harness (`undtool --sim`) per tier; M5 economy fixture re-run.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §21 (whole: taxonomy, roster shape, stat scaling table, behavior composition rules, drop/economy rules, zone assignment), §12 (zone ladder Z4–Z8), §14.1 (parts — fixed vocabulary), §16/§17/§21.5 (economy re-derive), §25.1 (capacities: 56 creatures / 12 zones — fits), §36 (M13 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m12-audio-options-plan.md`. NEXT: `2026-11-12-undersanded-m14-t234-assets-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Stat scaling (§21.3) verbatim: HP T2 100–180 / T3 140–200 / T4 180–220; Resolve 70–150 / 90–150 / 100–150; Attack commons 6–9, rares 9–12 everywhere; subdue 95/80/60/−1; sale 20–80 / 30–90 / 40–100; respawn triples unchanged. Behavior rules (§21.4): existing effect vocabulary only; ≥1 bar-switch pressure per creature; ≤1 signature trick beyond it; Named = keystone drop + family grudge (run scope P10). Zone assignment (§21.6): Z4 commons+named / Z5 T2 rares / Z6 commons+named / Z7 T3 rares / Z8 T4 commons+rares; rares bleed ≤10% into the band's commons zone. Global damage ranges unchanged (Strike 15–25, Restrain 10–18) — difficulty via stats/behaviors.

## File Structure

- `examples/z98/undersanded/data.z98` — +30–36 `[creatures]`, `[rules]`, drops, `[encounter]` Z4–Z8 rows, `[text]` journal/legends additions.
- `examples/z98/undersanded/NOTES.md` — the authoring ledger (name → family/adjective/tier/zone/phase; the §21.5 material-source table; economy re-derivation).
- `examples/z98/undersanded/tests/tier_m13_content.sh`, updated goldens.

## Review Focus

- Stat scaling violations (HP band per tier; Attack outside 6–9/9–12) → validation extension + fixture reject.
- Behavior-budget violations (two signature tricks, or no bar-switch pressure) → review checklist + sim bar-switch metric per creature.
- Encounter tables that starve a material (each material needs ≥1 common source OR ≥2 rare sources in the band that needs it — §21.5) → source-coverage test over the §17 material list.
- Grudge keystones duplicated or refined (keystones used as-is, one unique part per Named, ≤3 new parts) → row validation. MAX_RULES=96 global budget (spec §25.1 amended) checked at load. Weight sums validated per zone/phase (M4 rule) incl. the ≤10% rare bleed. MAX_ENCOUNTER=24 = per zone per phase.
- Rares over-weighted into commons zones (>10%) → weight validation.

---

### Task 0: Preflight

- [ ] Draft the authoring ledger in NOTES.md first: pick names from the taxonomy (adjective × family, no collisions with T1), assign each to tier/zone/phase, plan grudge families and keystones for the 3 new Named (one per T2–T4 Named, up to 3 total). STOP-present the ledger list for a sanity glance (names + zone assignment only) before authoring rows.

### Task 1: T2–T4 creature rows + rules

- [ ] Author 30–36 rows (ledger fixes the exact count) per §21.2 (T2: 4–6 commons + 1 Named + 5 rares into Z4/Z5; T3 same into Z6/Z7; T4 4–6 commons + 1 Named + 5 rares into Z8 — rares may bleed ≤10% into the commons zone). Behaviors per §21.4. Named rows: keystone parts + grudge rows. **Keystone policy (pinned):** the 9-part vocabulary may grow by **up to 3 new keystone parts (one per T2–T4 Named; `MAX_PARTS` 14; keystones are drop-only, §17 111+2 unchanged)**; each Named's keystone is a unique part id. **Grudge kinds = RES | ARMOR only** (new Named pick one). **counter_tool:** every T2–T4 creature names one of the 7 existing tools or `none` (field required). Validation: scaling bands, subdue roles, sale ranges. Transcription-diff style tests vs the ledger. Commit `example(undersanded): T2-T4 creature rows + rules`.

### Task 2: Z4–Z8 encounter tables + text

- [ ] Encounter rows per zone/phase (schema §13; T2 rare-dominant Z5 etc. per §21.6); journal entries for every new creature (P12 trigger), Legends entries for the 3 Named ("unconfirmed sightings" voice), zone flavor for Z4–Z8. Goldens updated. Commit `example(undersanded): Z4-Z8 tables + T2-T4 text`.

### Task 3: Economy re-derivation + source coverage

- [ ] Update `economy_full.md`: material-source table for the full game (§21.5 rule), sale-price ladder, full-run estimate (boat cost fixed 111+2; hunt counts by band). Source-coverage test (every material obtainable per §21.5). Commit `example(undersanded): full-game economy re-derivation`.

### Task 4: Per-tier sims

- [ ] `undtool --sim 200` per tier representative (one common + one rare per band) **with the per-tier loadout pinned in the run header: Hull tier = band target (T2: 125 hull, T3: 150, T4: 200) + the band's realistic tool load (M5 sim loadout)**; assert the **per-tier fight-length gates (spec §21.3 P20): ≤12 T1/T2, ≤14 T3, ≤15 T4**, ascent ≤15%, bar-switch >0. Damage ranges are global and never tuned. **Boss-feasibility gate (spec §15/§21.3):** run the boss policy sim with the minimalist T4-proper loadout (Hull 150, Speed 15, Precision 15, Steel Plate) over the fixed seed set and with max Hull — kill rate **≥50%** and **≥90%** respectively; if T4 rows push the boss out of reach → STOP-present (T4 band or boss numbers move via spec amendment, never player damage). Record numbers in NOTES.md. Commit `example(undersanded): tier sims`.

### Task 5: `tier_m13_content.sh`

- [ ] Tier: Tasks 1–3 tests + full-roster load golden (exact ledger count + all validations) + source coverage + per-tier sim gates. Non-vacuous. Run PASS. Commit `example(undersanded): M13 content tier`.

**Gate:** full roster loads; tier sims pass; every material obtainable; goldens green.

### Task 6: Next-milestone amendment review (M14)

- [ ] Read `2026-11-12-undersanded-m14-t234-assets-plan.md`; judge base-sprite reuse (recolors of the 11 bases vs new silhouettes needed for new families). Amendment or "no amendment needed" in NOTES.md.
