# UNDERSANDED — full-game economy projection (spec §17, §21.5)

Projection only: no new content and no runtime numbers are defined here. The
T1 rows are binding; the T2–T4 material is the §21.5 re-derivation envelope
that M13 authors and M15 measures.

## §17 boat completion — all five axes to T3

| Material | Total | Parts at E3 | T1 sources |
| :--- | --: | --: | :--- |
| Chitin | 19 | Shell Chip ×7 | all T1 commons |
| Steel Plate | 6 | Plate Scrap ×2 | Steel Tuna, Rust Tuna, Tunisteel |
| Gland | 21 | Gland Sac ×7 | Eel, Electric Eel, Mileel, Anemone |
| Luminescence | 5 | Glow Polyp ×3 | Lantern-Jelly, Ghost-Ray, Angler (rare) |
| Brine | 26 | Brine Vial ×9 | Brine Jelly; Lantern-Jelly, Ghost-Ray, Squid, Angler |
| Coral | 26 | Coral Bud ×9 | Kelp Crab, Barnacle; Coral Crab, Wrasse |
| Glass | 8 | Glass Pane ×4 | Squid, Wrasse (rare) |
| **Total** | **111** | **41 parts** + Steel Fins ×2 | |

Parts at E3 use the real yields (commons 3/part, deep 2/part, rounded up per
material): `ceil(19/3)+ceil(6/3)+ceil(21/3)+ceil(5/2)+ceil(26/3)+ceil(26/3)+
ceil(8/2) = 7+2+7+3+9+9+4 = 41`.

## §17 cosmetic completion and T1 pacing

12 items at an average 175 coins = **2,100 coins**. Common sale average 24 →
**≈88 common sales ≈ 29 short expeditions ≈ 73 in-game days**. Rare sales and
Oxygen accelerate this; full 100% remains **≈3 in-game months**.

## §21.5 full-game projection

### Boat cost is global, not per-tier

The boat is one run-wide object: **111 materials + Steel Fins ×2 stays fixed**
across T1–T4. T2–T4 creatures add higher-sale parts and keystones, never a
second boat cost. M15 verifies full-run pacing with sims; M13 may re-derive
source rows but may not change these totals.

### Sale bands (spec §21.3)

| Tier band | Sale range |
| :--- | :--- |
| T1 | 10–70 (common average 24) |
| T2 | 20–80 |
| T3 | 30–90 |
| T4 | 40–100 |

The T2–T4 envelope is **20–100 coins**. Because sale price rises with tier,
cosmetic completion does not slow down in late tiers: the same 2,100-coin
cosmetic total needs fewer sales at T3/T4 than the T1 calibration above.

### Deep sources per band

§21.5 requires every material to have ≥1 common source **or** ≥2 rare sources
in the tier band that needs it, and the deep materials keep at least one rare
source per relevant band. Projection (M13 fills the creature rows):

| Band | Luminescence | Glass | Other materials |
| :--- | :--- | :--- | :--- |
| T2 (Z4–Z5) | ≥1 rare source | ≥1 rare source | ≥1 common or ≥2 rare |
| T3 (Z6–Z7) | ≥1 rare source | ≥1 rare source | ≥1 common or ≥2 rare |
| T4 (Z8) | ≥1 rare source | ≥1 rare source | ≥1 common or ≥2 rare |

Deep parts remain renewable and never required by tools beyond the fixed boat
cost, so the §17 totals (111 + 2) close for a full run.

## Pacing summary

| Quantity | Value |
| :--- | --: |
| Boat materials | 111 |
| Steel Fins | 2 |
| Parts at E3 | 41 |
| Cosmetics (coins) | 2,100 |
| T1 common sales for cosmetics | ≈88 |
| T1 short expeditions | ≈29 |
| T1 in-game days | ≈73 |

Full-run day count is **not** measured here; that is the M15 balance pass.
