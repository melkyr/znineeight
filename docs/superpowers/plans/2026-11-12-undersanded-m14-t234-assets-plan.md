# undersanded M14 — Tier-2–4 assets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Art for the full game: recolors covering the T2–T4 roster, the 5 new zone backgrounds (`bg_z4`–`bg_z8`), any new overlays — full-game asset budget met with on-demand background loading verified.

**Architecture:** Same M10 policy (palette locked, SVG→`.ZSP` via **transitory uncommitted** conversion, Z98 `--validate-assets`, manifest). No committed converter (P19). **Frozen family→base map (spec §21.1 amended):** Eel→eel00, Tuna→tuna00, Crab→crab00, Jelly→jelly00, Ray→ray00, Angler→angler00, Kelp→crab00, Squid→squid00, Barnacle→barn00, Wrasse→wrasse00, Perch→tuna00, Anemone singletons→anem00. **No new bases anywhere in T2–T4** — a rare's "unique silhouette" = recolor + overlay within its family base. Backgrounds load on demand: only the current zone's background resident (spec §35 sprite arena 2 MB).

**Tech Stack:** Z98 validator + decoder, M9 blit path; transitory (uncommitted) conversion at authoring time only.

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §30 (palette, pipeline, background rules, manifest), §35 (full-game budget: sprite arena 2 MB with 1 resident bg; per-bg ≤120 KB encoded; **disk RLE demo 300–400 KB / full game 550–750 KB** — spec amended), §21.6 (zone visuals), §36 (M14 row + backgrounds risk).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m13-t234-content-plan.md`. NEXT: `2026-11-12-undersanded-m15-balance-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. Palette still locked (§30 anchors — no new hexes). 8.3 names (`bg_z4`…`bg_z8`). Background discipline: banded depth, ≤8 unique colours, flat areas, ≤120 KB encoded each. Style set must still hold across **all** assets after the additions (side-by-side review).

## File Structure

- `examples/z98/undersanded/assets/` — +`bg_z4.svg`…`bg_z8.svg`, new recolor assignments (manifest rows, not new pixels where ramps suffice).
- `examples/z98/undersanded/zsp.zig` / `render_art.zig` (modify) — on-demand background load/unload per zone.
- `examples/z98/undersanded/tests/tier_m14_assets.sh`, manifest + budget goldens (pure Z98/shell; assert no Python).

## Review Focus

- Background budget blowouts (the #1 asset risk) → Z98 validator hard-fails >120 KB encoded; cumulative assertion.
- Resident-set leaks (two backgrounds resident → arena overrun) → load/unload accounting test.
- Recolor mapping errors (wrong ramp for family/variant) → manifest ramp column validated against the §30 ramp-per-family table (6 Eel … 15 Wrasse; UI 0–5).
- Style drift in new SVGs → side-by-side review sign-off with the M10 set (attestation recorded in NOTES.md).
- Zone→background binding off-by-one (Z4↔bg_z4 … Z8↔bg_z8, D↔bg_d, dock↔bg_dock) → binding test.

---

### Task 0: Preflight

- [ ] From the M13 ledger, compute the recolor matrix: roster row → base silhouette + ramp assignment(s). Confirm zero (or minimal) new silhouettes; STOP-present if any new base is required.

### Task 1: Backgrounds `bg_z4`–`bg_z8`

- [ ] Author 5 SVGs (640×300, banded, ≤8 colours) per §30 discipline + §21.6 zone identity (Kelp Basin, The Shelf, Wreck Line, The Hollow, The Trench — deepest = `bg_d`-adjacent mood). Convert (transitory) + `--validate-assets` + budget. Commit `example(undersanded): Z4-Z8 backgrounds`.

### Task 2: Recolors + manifest + on-demand loading

- [ ] Manifest rows for every T2–T4 sprite (recolors of bases via ramp assignment; flex recolors anem00 (Anemoniacus) + icy tuna00 (Freezing Perch); new family → only if Task 0 demanded a new base, then author it and review the set again). Runtime: `render_art` loads the current zone's background on zone change and frees the previous one; unit test asserts 1 resident bg + arena accounting ≤2 MB across the **resident matrix: dock↔zone, zone↔zone, zone↔fight (fight draws zone bg), boss route**; LUT/recolor model: 48 recolors × 512 B LUTs built at load (documented). Commit `example(undersanded): T2-T4 recolors + on-demand backgrounds`.

### Task 3: `tier_m14_assets.sh`

- [ ] Tier: full-manifest validation green (Z98) + budget assertions (per-bg ≤120 KB; total disk RLE **≤750 KB full game / ≤400 KB demo** — two-column accounting; sprite arena accounting) + zone-binding test + goldens unchanged + style sign-off recorded (NOTES attestation + side-by-side evidence). Whole tier is native Z98/shell FAST (no Python). Non-vacuous. Run PASS. Commit `example(undersanded): M14 assets tier`.

**Gate:** full-game asset budget met; on-demand background loading verified; style set holds.

### Task 4: Next-milestone amendment review (M15)

- [ ] Read `2026-11-12-undersanded-m15-balance-plan.md`; judge sim/telemetry sufficiency for full-run balance (per-zone encounter metrics, dead-day detection). Amendment or "no amendment needed" in NOTES.md.
