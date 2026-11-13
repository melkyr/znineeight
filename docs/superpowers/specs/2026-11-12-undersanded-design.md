# UNDERSANDED — Umbrella Design Specification

**Date:** 2026-11-12 · **Status:** approved design for agent-driven development
**Scope:** the FULL 4-tier game (not a demo-only deliverable), with a demo-complete gate at milestone M11.
**Consumers:** the 16 milestone plans in `docs/superpowers/plans/2026-11-12-undersanded-mNN-*-plan.md`.
**Self-containment:** this document embeds every mechanic, number, and table needed to build the game. It references no external design files. If a later milestone plan and this spec disagree, this spec wins and the plan is corrected.

---

## 0. Intent, Goals, Approaches

### 0.1 Why this project exists

Z98 is a self-hosted language targeting Win98-era PE32 binaries. The compiler has already shipped a Game Boy emulator (z9gb) and a cell-tier editor (z9edit). *Undersanded* is the **pre-endgame capstone**: a real, shippable, content-rich desktop game proving Z98 can carry a full production app — data-driven content, save system, pixel rendering, audio, asset pipeline, installer-grade error UX — before the final phase-5 3D (D3D6/7) project. It is an example project under the compiler repo, but it is the **largest** example and must be done to shippable quality. Its module boundaries and standards become the reference for the endgame project.

### 0.2 What the game is

*Undersanded* is a turn-based hunting / calendar adventure for Windows 98SE/ME. You are a scavenger pilot in a drowned world. You plan expeditions on a calendar, hunt leviathans in 8–15-action 1v1 fights with two coupled bars (HP and Resolve), and end every hunt three ways: Subdue, Kill, or Overkill. Subdued creatures can be Released (richer future hunts) or Sold (boat cosmetics). The only true cost is time.

**One sentence:** *You hunt leviathans on a calendar. Every hunt ends three ways. Releasing a creature makes the next hunt richer; selling it makes your boat prettier. The calendar does not wait.*

### 0.3 Goals

- A complete, playable, balanced 4-tier game: ~49–55 creatures, 8 hunting zones + 1 boss route, one boss with 5 adaptive variants, full economy, full save system, art + terminal presentation, ambient audio + cues.
- A **demo-complete gate at M11**: Tier-1 content (17 creatures + 2 flex), the full boss loop, score screen — shippable as a demo of the whole game, smaller.
- Every milestone self-contained and **testable in isolation** (fight core testable in text mode; audio testable alone; calendar testable alone; etc.).
- Schemas and module capacities sized for the **full game from milestone 1** — no retrofit of capacities (Z98 has no generics; retrofit is pain).
- Ship on real Win98SE hardware within budget: ≤8 MB working set, no-CRT PE32, imports limited to GDI32/USER32/KERNEL32 + dynamically loaded ddraw/dsound.

### 0.4 Non-goals

- No multiplayer, no networking, no DLC, no patches required for completion.
- No Direct3D; stay on DirectDraw7 windowed. The endgame project does 3D.
- No composed music score — one ambient loop + 4 one-shot cues is the entire soundtrack.
- No difficulty options, no permadeath, no fail state. No in-game tutorial popups beyond two safety tooltips.
- Not a modding platform; the data tables are dev-facing text, not a user API.

### 0.5 Anti-goals (failure even if it technically runs)

- The fight is a two-button treadmill (bars don't couple) — the fatal design risk; sim-gated at M3.
- Retrofits to already-delivered milestones (why capacities are full-size from M1).
- Presentation mode changes game behaviour (art/terminal/console must be behaviour-identical).
- Save corruption that loses the player's world (rollback path is mandatory).
- CPU busy-spin on Win98 (event-driven idle is mandatory).

### 0.6 Approaches considered

| Approach | Summary | Verdict |
| :--- | :--- | :--- |
| **A — Spec-spine expansion (chosen)** | Expand the proven phase order (std → fight core → data/save → pixel tier → assets → content → boss → audio → full-game content → balance → ship) into 16 self-contained milestones. Strong core early; full-size schemas from M1; demo gate mid-project. | **Chosen.** "Phased and consistent integration is the hardest part; a very strong core from the beginning means fewer re-edits to paths already proven." |
| B — Full-data-first | Author all 4 tiers of content before deepening the engine. | Rejected: delays the risky engine proof; content without a proven fight core is guesswork. |
| C — Thin vertical slice first | Minimal one-zone slice end-to-end, then widen. | Rejected: slice would be built on demo-sized capacities and reworked for the full game — exactly the retrofit pain Z98 punishes. |

Plans for all 16 milestones are written up front (not just-in-time), because JIT planning produced deviations and rabbit holes on earlier projects while up-front milestone plans delivered faster with fewer loops.

### 0.7 Where things live

| Artifact | Location |
| :--- | :--- |
| This spec | `docs/superpowers/specs/2026-11-12-undersanded-design.md` |
| Milestone plans (16) | `docs/superpowers/plans/2026-11-12-undersanded-m01-…-plan.md` … `m16-…` |
| Game source tree | `examples/z98/undersanded/` (alongside z9gb) |
| Stdlib patches (M1) | `sf/src/` std modules |

---

# PART I — THE GAME

## 1. Identity

| Field | Value |
| :--- | :--- |
| Title | *Undersanded* |
| Genre | Turn-based hunting / calendar adventure |
| Platform | Windows 98SE / ME |
| APIs | DirectDraw7 (windowed) + DirectSound |
| Language | Z98 (self-hosted), C89 output |
| Tone | Calm, deliberate, exploratory. Not punishing. |
| Session shape | Persistent save. Start and stop whenever. No death, no fail state. |
| Reference points | *Monster Hunter* hunt structure, *Rune Factory* calendar, *Slay the Spire* route choice, era shareware manual-as-tutorial |
| Full-game scope | 4 tiers, ~49–55 creatures (17 Tier-1 + 2 flex + 30–36 Tier-2–4), 8 hunting zones + boss route, 1 boss (5 Phase-2 variants), 1 equipment slot, 7 tools, 5 boat axes, 12 cosmetics |
| Demo gate (M11) | Tier-1 slice: 17 creatures + 2 flex, zones Z1–Z3 + boss route, full boss loop, score screen |

---

## 2. Player Promise and Lore

You are a **scavenger** — a solo submersible pilot working a drowned world from a surface dock. No name, no face. The journal speaks in your voice.

You choose what to hunt, when to hunt it, how to end it, and what to do afterward. You are never rushed, never killed, never sent back to zero. What you spend is **time**.

The player should feel: *"I planned this expedition well." / "I read that creature correctly." / "I released it, and it paid off three days later." / "This boat is mine."*

**Lore delivery:** the manual's first page, shown once on a fresh install. Nothing else is explained up front. The Derelict is referred to only as *"a signal, not a machine"* until you kill it.

### Manual page 1 — "The Drowned World" (draft)

> *You were hired to work the drowned world. Nobody told you what happened to the cities below. The company pays by the part, and the parts come from things that used to be alive. You have a submersible, a net, a hull that has seen better days, and a calendar that does not stop.*
>
> *There is a signal under the reef. Nobody knows what it is. You are going to find out, or you are going to get paid, and either is a good day.*

---

## 3. Design Pillars

1. **The hunt is the game.** Every system exists to make the 8–15 turn fight interesting. If it doesn't, it's cut.
2. **Three endings, one choice.** Strike, Restrain, Overkill. Skill is reading which ending is achievable. The machine boss strips Restrain as the final exam.
3. **Time is the only currency with weight.** No death reset. Cycles spent are cycles gone.
4. **Every creature is content.** Variants share skeletons; rares are unique; the boss is the exam.
5. **The manual is the tutorial.** The game teaches by doing; the journal explains after the fact.
6. **Cosmetics are a real reward.** The decorated boat is the achievement, not a power fantasy.

---

## 4. The Four Resources

| Resource | Earned by | Spent on | Motivation |
| :--- | :--- | :--- | :--- |
| Time (cycles) | metronome | every action | Planner |
| Materials | hunting → refining parts | boat upgrades | Achiever |
| Money | selling subdued creatures | cosmetics | Decorator |
| Rarity | releasing subdued creatures | rare availability | Explorer |

Materials and money are separate tracks. Optimizing one does not optimize the other. Both complete the game.

---

## 5. Time and Calendar

**1 cycle = 1 day = 2 phases (Day, Night). 1 action per phase.**

Dock actions: Refine, Upgrade, Craft, Buy Cosmetic, Rest, Depart.
Field actions: Hunt, Rest at node, Surface, Flee.

### Rest

| Kind | Effect |
| :--- | :--- |
| **Dock Rest** | +40 Hull, 1 phase, no penalty |
| **Node Rest** | +30 Hull, 1 phase, **rough-sleep condition** on the next fight |
| **Empty-pool Rest** | +30 Hull, 1 phase, **no penalty** (nothing available at this node) |

Rough-sleep condition (random, one of):

| Condition | Effect |
| :--- | :--- |
| Drowsy | Strike damage −20% |
| Shaky | overkill margin halved |
| Exposed | incoming damage +25% |

Node Rest is how you cross a phase boundary in the field. It is doable, but it costs.

### Renewal

A creature returns on the **Day phase** of its renewal cycle. Subdued Night of cycle 3 with 3-cycle renewal → available Day of cycle 6.

The calendar reads as a schedule, not a table: *"The Trench Leviathan renews on cycle 14. It is cycle 9."*

---

## 6. Expedition Loop

```
DOCK ── refine / upgrade / craft / buy / rest
  └─ DEPART ── travel out (1–5 phases)
       ▼
   HUNTING NODE ── fight 1 … fight N (optional)
       │            node Rest (optional, penalized)
       └─ surface early at any point
       ▼
   RETURN ── travel back (1–5 phases)
       ▼
DOCK ── process loot
```

| Rule | Value |
| :--- | :--- |
| Max fights | 3 + Oxygen tier (3→6). Boss route = 1. |
| Travel each way | zone ladder: 1–5 phases (see §11) |
| Heavy penalty | Hull T3 **or** Cargo T3 → +1 phase each way on zones with travel ≥ 3 |
| Hull | **Persists across fights and across expeditions.** Dock arrival heals nothing free. |
| Early return | Normal return travel, no extra penalty, secured loot kept |

### Hull 0 — Emergency Ascent

Fight ends immediately. Keep nothing **from the current fight**. Loot secured from earlier fights is kept. Pay +1 phase **and** normal return travel. Surface to dock.

### Player Flee

Same as Emergency Ascent: nothing from the current fight, +1 phase, normal return travel still paid. **Flee is not a shortcut.**

### Creature Flee

Nothing kept from the current fight. Counts as **seen**. Returns after normal subdue-length renewal. Pressure Hook prevents it.

---

## 7. Loot Flow

**Loot is awarded immediately when a fight ends in Subdue, Kill, or Overkill**, into the expedition hold, before any Release/Sell choice and before the next encounter.

The game shows a per-fight line:

```
Secured: Shell Chip ×3, Gland Sac ×1
```

| Outcome | Loot |
| :--- | :--- |
| Subdue | Full table. Then choose Release or Sell. **Both keep the parts.** |
| Kill | Corpse table. No choice. |
| Overkill | Ruined table. No choice. |
| Flee / Ascent | Nothing from this fight. Earlier secured loot is unaffected. |

**Cargo** adds +1/+2/+3 parts to the **drop total**, applied to the primary drop line — not to every line.

At dock, parts refine into materials. **Tools cost parts. Upgrades cost materials.** Named keystones are used as-is.

---

## 8. Combat

### 8.1 Player stats

| Stat | Value |
| :--- | :--- |
| Base Hull | 100 |
| Base Speed | **10** |
| Strike | 15–25 HP |
| Restrain | 10–18 Resolve |
| Base overkill margin | 10% of target max HP |
| Equipment slots | 1 |

### 8.2 Creature stats

Every creature has HP, Resolve, Speed, **Attack**, behavior, three drop tables, sale price, respawn timers, counter tool, and **subdue chance**.

Attack ranges: commons **6–9**, rares **9–12**, boss phase-based. Hull is the fight clock: ~100 ÷ attack ≈ the round budget.

### 8.3 Actions

| Action | Effect | Cost |
| :--- | :--- | :--- |
| Strike | damage HP | 1 turn |
| Restrain | damage Resolve, no HP | 1 turn |
| Equipment | activate equipped tool | 1 turn |
| Flee | end fight | 1 turn + 1 phase + return travel |

### 8.4 Turn order

Compare player Speed vs creature Speed each round. Faster acts first. **Ties go to the player.** Speed modifiers apply immediately when their condition is met.

### 8.5 The Coupling Rule

Regen pressures the bar you are pushing, gated on the other bar being high.

| Gate | Condition | Effect |
| :--- | :--- | :--- |
| **Thrash** | Resolve < 50% **and** HP > 50% | Resolve +5/round (default) — a fresh body resists restraint |
| **Despair** | HP < 30% **and** Resolve > 50% | HP +5/round (default) — a fresh will resists death |

Applied at end of round. **Universal baseline**; creature rows override the number.

**Consequence:** to Subdue, Strike HP to ≤50% first (kills Thrash), then Restrain. To Kill, Restrain Resolve to ≤50% first (kills Despair), then Strike. Both paths touch both bars — this is what forces the mid-fight switch.

### 8.6 Overkill

Let `margin = max_hp × margin_pct / 100`, `overshoot = damage beyond 0`.

| Result | Condition |
| :--- | :--- |
| **Kill** | HP ≤ 0 and overshoot **<** margin |
| **Overkill** | HP ≤ 0 and overshoot **≥** margin |

| Precision tier | Margin |
| :--- | :--- |
| 0 | 10% |
| 1 | 15% |
| 2 | 20% |
| 3 | 25% |

The **red zone is a warning display only**, marking HP where a maximum Strike could overshoot: `danger_hp = 25 − margin`. It shrinks visibly as Precision rises. It is not a trigger.

### 8.7 Behavior timing

Threshold **damage** is one-shot on crossing. Threshold **stat changes** (armor, speed, attack) persist while below the threshold.

### 8.8 Information model

Always visible: both bars, Hull, phase, equipped tool and its charge/broken state, combat log.
Hidden until a journal entry exists: exact creature Speed.
Revealed by tools: Sonar shows Speed and next action; Lure shows phase pattern and real targets.

**Seen** = a fight with that creature began. Fleeing still counts.

---

## 9. Outcomes

| Outcome | Trigger | Loot | Creature state | Rare effect |
| :--- | :--- | :--- | :--- | :--- |
| **Subdue** | Resolve ≤ 0, HP > 0, **chance roll succeeds** | full table | Release or Sell | — |
| **Kill** | HP ≤ 0, overshoot < margin | corpse table | gone 3× renewal | normal |
| **Overkill** | HP ≤ 0, overshoot ≥ margin | ruined table | gone 5× renewal | node lockout + global echo |
| Creature flee | creature escapes | none this fight | subdue-length renewal | normal |
| Player flee / Ascent | player choice / Hull 0 | none this fight | unchanged | normal |

### 9.1 Subdue Chance

| Role | Chance | Prompt |
| :--- | :--- | :--- |
| Common | **95** | silent auto-roll |
| Named | **80** | modal |
| Rare | **60** | modal |
| Boss | **−1** (cannot subdue) | never |

Prompt threshold is one module constant: `SUBDUE_PROMPT_BELOW = 90`. At or above → silent. Below → modal.

**Gate (all four must hold):** HP > 0 · Resolve ≤ 0 · `subdue_declined == false` · `subdue_chance ≥ 0`.

### 9.2 Resolution order

```
player action
  ├─ apply damage / effects
  ├─ death check ......... HP ≤ 0 → KILL or OVERKILL, fight ends
  ├─ subdue gate ......... Resolve ≤ 0 and HP > 0
  │    ├─ prompt or auto-roll
  │    ├─ success ........ SUBDUE, fight ends, creature does NOT act
  │    └─ failure ........ LAST SURGE, fight continues
  ├─ creature action ..... if fight still live
  ├─ end-of-round coupling
  └─ round++
```

On success the creature gets no parting hit. On failure it acts **that same round**, already surged.

### 9.3 The modal (rare / named only)

```
──────────────────────────────────────
  SUBDUE ATTEMPT
  Neon Ghost-Ray — 60% chance

  Failure triggers a Last Surge: its will
  partly returns, it hits harder and moves
  faster. The fight goes on.

  [A] Attempt   [F] Fight on   [Esc] Cancel
──────────────────────────────────────
```

| Choice | Effect |
| :--- | :--- |
| **A — Attempt** | consume one RNG draw, roll. Success → Subdue. Failure → Last Surge. |
| **F — Fight on** | set `subdue_declined = true`, return to combat. **Consumes no RNG.** |
| **Esc — Cancel** | identical to F. Esc is the keyboard alias. |

If Thrash is live when you decline, log: *"You hold off. Its will begins to recover."*

### 9.4 Silent path (commons)

| Result | Log |
| :--- | :--- |
| Success | `Subdued Mystic Eel (95%).` — normal |
| Failure | `Subdue failed — Mystic Eel surges! (95%)` — **warn class** + art-mode screen shake |

No audio cue for failure. The 5% is felt through a loud line, not an interruption.

### 9.5 Last Surge

| Effect | Rule |
| :--- | :--- |
| Resolve restore | every surge: `res = (max_res * 30 + 99) / 100` (integer ceil) |
| Attack | **+25 percentage points, once.** Never stacks. |
| Speed | +2 per surge, **capped at +6** |
| `subdue_declined` | stays false — the gate can re-fire |
| Log | one flavor line per surge |

Percentages **accumulate then apply once**: `atk_pct = 100 + 50 (Angler below 50%) + 25 (surged)`. Never chain multipliers.

**`max_res` includes grudge and wariness.** Mileel's +30 and release wariness +15 raise both `res` and `max_res` for that fight, so the 30% restore uses the fight's real maximum.

At 60%: P(≥2 failures) = 16%, P(≥3) = 6.4%. At 80%: 4%. At 95%: 5% get one surge.

### 9.6 What the risk actually is

Restrain never touches HP, so **it cannot cause overkill**. The real chain:

1. Resolve partly restores → more Restrain turns.
2. Creature acts more often, at +25% attack.
3. Hull drains → **Emergency Ascent risk** → current-fight loot lost, +1 phase, return travel.
4. Overkill risk rises **only if you abandon Subdue and switch to Strike** near the red zone — which is live, because coupling already made you Strike HP to ≤50%.

### 9.7 Release vs Sell

| Choice | Effect |
| :--- | :--- |
| **Release** | node rare chance **+8 pp** per release, bonus cap **+40 pp**, resets when a rare is encountered in that node. Additive to rare entries, commons renormalized. Creature returns **warier: +15 Resolve, next rematch only, no stack**. Parts kept. |
| **Sell** | sale price in coins. Normal renewal. Parts kept. |

Zones with 0 rares (the tutorial zone) have no rare effect from releasing. Intentional.

### 9.8 Overkill lockout

Any overkill (including on a common) zeroes **that node's** rare chance for **5 cycles**.

**Global echo:** each currently locked-out node reduces rare encounter chance by **5 percentage points globally**, redistributed to commons. A locked node's own rare chance is 0 regardless of other modifiers.

### 9.9 Why Kill exists

Subdue gives full loot plus a choice. Kill gives a worse table and no choice. Kill's incentive is **speed and safety** — a shorter fight spends less Hull. No exclusive corpse drops.

---

## 10. Equipment — One Slot

Chosen before the expedition. Crafted at dock (1 phase). Owned forever. **Tools cost parts.**

| Kind | Rule |
| :--- | :--- |
| **Activated** | **1 charge per expedition**, used via Equipment action, effect lasts the fight |
| **Rigged** | passive, always on while equipped, no charge |

| Tool | Kind | Cost (parts) | Effect | Counters |
| :--- | :--- | :--- | :--- | :--- |
| Electric Gland | Activated | Gland Sac ×3 | Stun 1 turn | Electric Eel, Brine Jelly, Anemone, Lantern-Jelly |
| Steel Plate Tool | Rigged | Plate Scrap ×3 | Negates armor; halves boss Cannon Volley | Tuna family, Barnacle, Wrasse, Derelict |
| Bioluminescent Lure | Activated | Glow Polyp ×2, Glass Pane ×1 | Reveals phase/real target; prevents blind & decoy | Ghost-Ray, Lantern-Jelly, Angler |
| Pressure Hook | Rigged | Hooked Barbel ×1, Shell Chip ×2, Coral Bud ×1 | Prevents flee | Mileel, Rust Tuna |
| Sonar Ping | Activated | Glass Pane ×2, Gland Sac ×1 | Reveals Speed + next action; prevents ink; shows Ghost-Ray flip | Glass Squid, Ghost-Ray, Derelict |
| Brine Net | Rigged | Brine Vial ×2, Shell Chip ×1 | Restrain ignores Shell and Phasing reduction | Coral Crab, Ghost-Ray |
| Coral Shield | Rigged | Coral Bud ×2, Plate Scrap ×1 | Negates discharge-type Hull damage | Electric Eel, Spark Anemone |

**Fragile tools:** at **Precision T2+**, a single incoming hit ≥15 Hull disables the equipped tool for the rest of the expedition.

**Grudges** — Named-only, overkill-only, family-based:

| Named | Trigger | Effect |
| :--- | :--- | :--- |
| Mileel | any Eel-family overkill this run | +30 Resolve |
| Tunisteel | any Tuna-family overkill this run | armor 50% → **30%** (flat) |

Steel Plate Tool negates grudge armor. (T2–T4 named creatures get grudges by the same rule, authored at M13.)

**"This run" = since the last Derelict kill (or game start).** The family-overkill mask persists in the save; killing the Derelict clears it (the run ends; the next run starts clean).

---

## 11. The Boat — Five Axes

Sequential tiers, bought at dock with **materials**, 1 phase each. Maxing all five is a **soft** constraint (material/time pressure). Only **Heavy** is a hard tradeoff.

| Axis | Effect (values are **cumulative totals per tier**, T2 replaces T1's total) | Tradeoff |
| :--- | :--- | :--- |
| Hull | max Hull **125 / 150 / 200** (base 100 +25 / +50 / +100 total) | Heavy at T3 |
| Precision | margin 10→15→20→25% | fragile tools at T2+ |
| Cargo | +1 / +2 / +3 parts per drop total (current-tier value) | Heavy at T3 |
| Oxygen | 3→4→5→6 fights per expedition (current-tier value) | none |
| Speed | +2 / +5 / +9 Speed total (player Speed 12 / 15 / 19) | none |

**Heavy:** Hull T3 or Cargo T3 → +1 phase each way on zones with travel cost ≥ 3.

**Expertise gates:** purchasing an axis **T2** upgrade requires Expertise ≥ 2 in **every material type spent** on that purchase; **T3** requires Expertise ≥ 4. (T1 purchases have no gate.)

### Upgrade costs

| Axis | T1 | T2 | T3 |
| :--- | :--- | :--- | :--- |
| Hull | Chitin 3 | Chitin 6, Plate 2 | Chitin 10, Plate 4 |
| Precision | Gland 2, Lum 1 | Gland 4, Lum 2 | Gland 8, Lum 2 |
| Cargo | Brine 3, Coral 1 | Brine 6, Coral 2 | Brine 10, Coral 4 |
| Oxygen | Coral 3, Brine 1 | Coral 6, Brine 2 | Coral 10, Brine 4 |
| Speed | Glass 2, Gland 1 | Glass 2, Gland 2 | Glass 4, Gland 4, **Steel Fins ×2** |

Steel Fins is a keystone **part**, not a material.

### Cosmetics — 12 items

No functional benefit, ever. Bought at dock, 1 phase. **Start with 0 coins.** All items grayed with *"This is for an experienced adventurer."* Each zone milestone de-grays 3.

| Category | Item | Price | Unlock |
| :--- | :--- | :--- | :--- |
| Paint | Foam White | 150 | Zone Z1 milestone |
| Paint | Abyss Teal | 175 | Zone Z2 milestone |
| Paint | Leviathan Black | 200 | Zone Z3 milestone |
| Figurehead | Gull Skull | 150 | Zone Z1 milestone |
| Figurehead | Lantern Jaw | 175 | Zone Z2 milestone |
| Figurehead | Derelict Cog | 200 | Kill Derelict |
| Flag | Patched Pennant | 150 | Zone Z1 milestone |
| Flag | Reef Signal | 175 | Zone Z3 milestone |
| Flag | Trench Mark | 200 | Kill Derelict |
| Decal | Barnacle Stamp | 150 | Zone Z2 milestone |
| Decal | Glass Squid | 175 | Zone Z3 milestone |
| Decal | Boss Sigil | 200 | Kill Derelict |

Total: **2,100 coins**. (Zone milestone = **first arrival at that zone** ("Reach Z1/Z2/Z3"); T2–T4 zones unlock nothing new — the 12 items are fixed.)

---

## 12. Map and Zones — the travel-cost ladder

One home dock. Distance is expressed as **travel phases each way**. The tier band of a zone is its travel cost. **8 hunting zones** (wider, not narrow), plus the **boss route** at the far reach.

| # | Zone | Travel each way | Tier band | Role |
| :--- | :--- | :--- | :--- | :--- |
| Z1 | The Shallows | 1 | T1 | Tutorial. Commons only, 0 rares. |
| Z2 | The Reef | 2 | T1 | Commons + Named + 1 rare. Rares and Named introduced. |
| Z3 | Trench-Edge | 3 | T1 | Rare-dominant. Day = materials, Night = rares. |
| Z4 | Kelp Basin | 3 | T2 | T2 commons + Named. |
| Z5 | The Shelf | 4 | T2 | T2 rare-dominant. |
| Z6 | Wreck Line | 4 | T3 | T3 commons + Named. |
| Z7 | The Hollow | 5 | T3 | T3 rare-dominant. |
| Z8 | The Trench | 5 | T4 | T4 commons + rares. Deepest hunting zone. |
| D | The Derelict | 5 | boss | Boss only. Locked until **6 distinct non-boss creatures seen**. Node telegraphs *"Hull 150+ recommended."* |

Notes:

- The T1 band (Z1–Z3 + D) is the **demo slice**, content-complete at M11. Z4–Z8 are present as empty tables from M1 (schemas full-size) and populated at M13.
- Boss route cost 5 = far reach; the boss sits at the **end of the tier ladder** (after T4). One boss for the whole game.
- Heavy penalty (+1 phase each way) applies to any zone with travel ≥ 3: Z3–Z8 and D.
- A travel-5 expedition is a commitment: 5 out + fights + 5 back.

**Respawn is per-zone, per-species instance.** Subduing Steel Tuna in Z1 does not touch the Z2 instance. Encounter tables renormalize over available creatures. Empty pool → safe Rest.

### Rare chance pipeline

1. Build candidate list from zone/phase pool, filtered by availability.
2. Empty → no encounter; Rest is safe.
3. If node locked → rare chance = 0.
4. Else: base rare weight + release bonus (cap +40 pp) − 5 pp per locked node, floor 0. **If base rare weight is 0, releases accrue no bonus there** (tutorial zones). **Clamp the total to 100.**
5. Scale rare rows to that total; commons fill the remainder. **Apportionment: largest-remainder** over integer weights (no drift to 0 / off-sum). If no rare candidates are available, the rare weight is redistributed to commons; if no candidates at all → empty pool (step 2).

---

## 13. Encounter Tables

Weights are per-zone per-phase; tables renormalize over available (off-cooldown) creatures. Base rare weight is the sum of the rare rows below.

### Z1 — The Shallows (rare chance 0%)

| Day | % | Night | % |
| :--- | --: | :--- | --: |
| Mystic Eel | 30 | Mystic Electric Eel | 40 |
| Steel Tuna | 30 | Mystic Eel | 30 |
| Rust Tuna | 20 | Rust Tuna | 15 |
| Kelp Crab | 10 | Kelp Crab | 10 |
| Spark Anemone | 10 | Spark Anemone | 5 |

### Z2 — The Reef

| Day | % | Night | % |
| :--- | --: | :--- | --: |
| Tunisteel | 15 | Mystic Electric Eel | 20 |
| Mystic Eel | 15 | Brine Jelly | 15 |
| Steel Tuna | 10 | Mystic Eel | 15 |
| Rust Tuna | 10 | Rust Tuna | 10 |
| Mileel | 10 | Kelp Crab | 10 |
| Kelp Crab | 10 | Chitin Barnacle | 10 |
| Chitin Barnacle | 10 | Coral Crab *(rare)* | 10 |
| Spark Anemone | 5 | Anemoniacus *(rare)* | 10 |
| Coral Crab *(rare)* | 5 | | |
| Anemoniacus *(rare)* | 10 | | |

### Z3 — Trench-Edge

| Day | % | Night | % |
| :--- | --: | :--- | --: |
| Ironclad Wrasse *(rare)* | 20 | Coral Crab *(rare)* | 10 |
| Coral Crab *(rare)* | 15 | Abyssal Lantern-Jelly *(rare)* | 15 |
| Rust Tuna | 20 | Neon Ghost-Ray *(rare)* | 15 |
| Kelp Crab | 20 | Glass Squid *(rare)* | 10 |
| Chitin Barnacle | 15 | Brine Angler *(rare)* | 15 |
| Freezing Perch *(rare)* | 10 | Brine Jelly | 15 |
| | | Chitin Barnacle | 10 |
| | | Freezing Perch *(rare)* | 10 |

**Z4–Z8 tables:** authored at M13 (full-game content). Schema identical: per-zone per-phase weight rows, rare rows summed as base rare weight. Balance rules in §20.

**Zone D:** boss only.

---

## 14. Creature Roster — Tier 1 (17 + 2 flex)

Full-game roster target: **49–55 creatures** (T1 17 + 2 flex + T2–T4 30–36; see §21). Tier 1 is fully specified here; T2–T4 rows are authored at M13 within these rules. Rows 18–19 are the **flex slots** — unique-band rares that double as the M2/M3 sim creatures.

### 14.1 Parts and materials

| Part | Refines into |
| :--- | :--- |
| Shell Chip | Chitin |
| Plate Scrap | Steel Plate |
| Gland Sac | Gland |
| Brine Vial | Brine |
| Coral Bud | Coral |
| Glow Polyp | Luminescence *(deep)* |
| Glass Pane | Glass *(deep)* |
| Hooked Barbel | keystone — used as-is |
| Steel Fins | keystone — used as-is |

### 14.2 Master stats

| # | Creature | Family | Role | Zones | Phase | HP | Res | Spd | Atk | Subdue | Sale | Respawn |
| :-- | :--- | :--- | :--- | :--- | :--- | --: | --: | --: | --: | --: | --: | :--- |
| 1 | Mystic Eel | Eel | common | Z1,Z2 | both | 70 | 80 | 10 | 6 | 95 | 20 | 3/9/15 |
| 2 | Mystic Electric Eel | Eel | common | Z1,Z2 | night | 80 | 100 | 16 | 7 | 95 | 30 | 3/9/15 |
| 3 | **Mileel** | Eel | named | Z2 | day | 80 | 140 | 12 | 8 | 80 | 40 | 4/12/20 |
| 4 | Steel Tuna | Tuna | common | Z1,Z2 | both | 120 | 70 | 6 | 8 | 95 | 20 | 3/9/15 |
| 5 | Rust Tuna | Tuna | common | Z1,Z2,Z3 | both | 80 | 60 | 8 | 7 | 95 | 15 | 3/9/15 |
| 6 | **Tunisteel** | Tuna | named | Z2 | day | 140 | 100 | 5 | 9 | 80 | 40 | 4/12/20 |
| 7 | Kelp Crab | Crab | common | Z1,Z2,Z3 | both | 100 | 90 | 8 | 7 | 95 | 20 | 3/9/15 |
| 8 | Brine Jelly | Jelly | common | Z2,Z3 | night | 60 | 110 | 10 | 6 | 95 | 20 | 3/9/15 |
| 9 | Chitin Barnacle | Barnacle | common | Z2,Z3 | both | 130 | 50 | 3 | 6 | 95 | 15 | 3/9/15 |
| 10 | Spark Anemone | Anemone | common | Z1,Z2 | both | 90 | 70 | 4 | 6 | 95 | 20 | 3/9/15 |
| 11 | Coral Crab | Crab | rare | Z2,Z3 | both | 160 | 120 | 5 | 10 | 60 | 55 | 6/18/30 |
| 12 | Abyssal Lantern-Jelly | Jelly | rare | Z3 | night | 90 | 130 | 11 | 9 | 60 | 55 | 6/18/30 |
| 13 | Neon Ghost-Ray | Ray | rare | Z3 | night | 100 | 110 | 18 | 10 | 60 | 60 | 6/18/30 |
| 14 | Glass Squid | Squid | rare | Z3 | night | 100 | 130 | 14 | 9 | 60 | 65 | 6/18/30 |
| 15 | Brine Angler | Angler | rare | Z3 | night | 110 | 100 | 9 | 10 | 60 | 50 | 6/18/30 |
| 16 | Ironclad Wrasse | Wrasse | rare | Z3 | day | 150 | 140 | 7 | 11 | 60 | 70 | 6/18/30 |
| 17 | **The Derelict** | Boss | boss | D | both | 300 | — | 7→12 | 10→15 | −1 | — | 20/40 |
| 18 | **Anemoniacus** *(flex)* | Anemone | rare | Z2 | both | 95 | 115 | 7 | 9 | 60 | 50 | 6/18/30 |
| 19 | **Freezing Perch** *(flex)* | Perch | rare | Z3 | both | 105 | 95 | 13 | 10 | 60 | 55 | 6/18/30 |

Role subtotals (rows 1–17): **8 commons, 2 named, 6 rares, 1 boss** = 17. Rows 18–19 fill the 2 flex slots as unique-band rares (§21.1) and are the M2/M3 sim creatures.

### 14.3 Behaviors

| Creature | Behavior |
| :--- | :--- |
| Mystic Eel | Despair override **+8**. Tutorial creature, learnable bare. |
| Mystic Electric Eel | Thrash override **+8**. **Discharge:** one-shot 8 Hull when Resolve crosses below 50%. |
| Mileel | Despair override **+10**. **Flees next turn if a single hit deals >30% max HP (24).** Grudge +30 Resolve. |
| Steel Tuna | **Armor:** Strike 60% unless Plate. HP<30% → Speed +4. |
| Rust Tuna | **Armor:** Strike 80%. HP<30% → flees next turn. |
| Tunisteel | **Heavy Armor:** Strike 50% unless Plate (grudge → 30%). HP<30% → Speed +6. |
| Kelp Crab | Thrash override **+6**. |
| Brine Jelly | Despair override **+10**. |
| Chitin Barnacle | HP<50% → gains Armor (Strike 70%). **Stationary.** |
| Spark Anemone | **Discharge:** one-shot 10 Hull when HP crosses below 50%. **Stationary.** |
| Coral Crab | **Shell:** Restrain 50% unless Brine Net. Thrash override **+12**. |
| Abyssal Lantern-Jelly | Resolve<50% → blinds next Strike (50%) unless Lure. Despair override **+12**. |
| Neon Ghost-Ray | **Phasing:** Solid/Phase every 2 rounds. Solid: Strike works, Restrain 50%. Phase: Strike misses, Restrain full. HP<30% → stays Phase. |
| Glass Squid | **Ink:** every 3 rounds randomizes next combat action (never Flee) unless Sonar. Resolve<50% → Speed +6. |
| Brine Angler | Round 1: Strike hits decoy (miss) unless Lure. HP<50% → Attack +50%. |
| Ironclad Wrasse | HP<30% → gains Armor (Strike 50%) + Speed +4. Day-side Glass source. |
| Anemoniacus | Thrash override **+10**. **Discharge:** one-shot 10 Hull when HP crosses below 50%. |
| Freezing Perch | Despair override **+8**. **Flees next turn if a single hit deals >20% max HP (21).** |
| The Derelict | Machine. No Resolve. See §15. |

### 14.4 Drops (parts)

| Creature | Subdued | Killed | Overkilled |
| :--- | :--- | :--- | :--- |
| Mystic Eel | Shell Chip ×3, Gland Sac ×1 | Shell Chip ×2 | Shell Chip ×1 |
| Mystic Electric Eel | Gland Sac ×3, Shell Chip ×1 | Gland Sac ×1, Shell Chip ×1 | Gland Sac ×1 |
| Mileel | Gland Sac ×4, Shell Chip ×2, **Hooked Barbel ×1** | Gland Sac ×2, Shell Chip ×1 | Gland Sac ×1 |
| Steel Tuna | Plate Scrap ×3, Shell Chip ×1 | Plate Scrap ×2 | Plate Scrap ×1 |
| Rust Tuna | Plate Scrap ×2, Shell Chip ×2 | Shell Chip ×2 | Shell Chip ×1 |
| Tunisteel | Plate Scrap ×4, Shell Chip ×2, **Steel Fins ×2** | Plate Scrap ×2, Shell Chip ×1 | Plate Scrap ×1 |
| Kelp Crab | Coral Bud ×2, Shell Chip ×2 | Coral Bud ×1, Shell Chip ×1 | Shell Chip ×1 |
| Brine Jelly | Brine Vial ×3, Shell Chip ×1 | Brine Vial ×1, Shell Chip ×1 | Brine Vial ×1 |
| Chitin Barnacle | Shell Chip ×4, Coral Bud ×1 | Shell Chip ×2 | Shell Chip ×1 |
| Spark Anemone | Gland Sac ×2, Shell Chip ×1 | Gland Sac ×1, Shell Chip ×1 | Gland Sac ×1 |
| Coral Crab | Coral Bud ×3, Shell Chip ×2 | Coral Bud ×1, Shell Chip ×1 | Shell Chip ×1 |
| Abyssal Lantern-Jelly | Glow Polyp ×2, Brine Vial ×3 | Glow Polyp ×1, Brine Vial ×1 | Brine Vial ×1 |
| Neon Ghost-Ray | **Glow Polyp ×4**, Brine Vial ×2 | Glow Polyp ×1, Brine Vial ×1 | Brine Vial ×1 |
| Glass Squid | **Glass Pane ×4**, Brine Vial ×2 | Glass Pane ×1, Brine Vial ×1 | Brine Vial ×1 |
| Brine Angler | Glow Polyp ×2, Brine Vial ×2 | Glow Polyp ×1, Brine Vial ×1 | Brine Vial ×1 |
| Ironclad Wrasse | Plate Scrap ×3, Coral Bud ×2, **Glass Pane ×2** | Plate Scrap ×2, Coral Bud ×1 | Plate Scrap ×1 |
| Anemoniacus | Glow Polyp ×2, Coral Bud ×2 | Gland Sac ×1, Coral Bud ×1 | Coral Bud ×1 |
| Freezing Perch | Brine Vial ×3, Plate Scrap ×1 | Brine Vial ×1, Plate Scrap ×1 | Brine Vial ×1 |
| The Derelict | — | Plate Scrap ×5, Gland Sac ×3, Glow Polyp ×3, Glass Pane ×2, Coral Bud ×2 | Plate Scrap ×2, Gland Sac ×1 |

### 14.5 Counter tools

| Creature | Counter |
| :--- | :--- |
| Mystic Eel | none |
| Mystic Electric Eel | Electric Gland (stun) or Coral Shield (discharge) |
| Mileel | **Pressure Hook** |
| Steel Tuna / Tunisteel / Chitin Barnacle / Ironclad Wrasse | Steel Plate Tool |
| Rust Tuna | Pressure Hook or Steel Plate Tool |
| Kelp Crab / Coral Crab | Brine Net |
| Brine Jelly | Electric Gland |
| Spark Anemone | Coral Shield or Electric Gland |
| Abyssal Lantern-Jelly | Bioluminescent Lure |
| Neon Ghost-Ray | Sonar Ping, Lure, or Brine Net |
| Glass Squid | Sonar Ping |
| Brine Angler | Bioluminescent Lure |
| Anemoniacus | Coral Shield or Electric Gland |
| Freezing Perch | Pressure Hook |
| The Derelict | Steel Plate Tool or Sonar Ping |

---

## 15. The Derelict

Machine. **No Resolve.** Restrain disabled with the journal line: *"The machine has no will to break."*

| Phase | HP band | Speed | Attack |
| :--- | :--- | :--- | :--- |
| 1 | 300 → 200 | 7 | 10/round |
| 2 | 200 → 100 | 10 | **Cannon Volley 15 every 2 rounds** (replaces standard) + axis variant |
| 3 | 100 → 0 | 12 | 15/round |

Steel Plate Tool halves Cannon Volley. Overkill → 40-cycle respawn (kill → 20).

**Phase 2 adapts to your dominant boat axis.** Tiebreak: Hull > Precision > Cargo > Oxygen > Speed. All-zero → The Armor.

| Axis | Identity | Behavior |
| :--- | :--- | :--- |
| Hull | **The Armor** | Strike 50% unless Steel Plate Tool |
| Precision | **The Sliver** | full damage odd rounds, 25% even rounds |
| Cargo | **The Hoard** | jettisons 1 secured part every 3 rounds |
| Oxygen | **The Drown** | after round 10, flood damage +5 Hull per round beyond 10 |
| Speed | **The Blur** | acts first always; double-strike every 3rd round |

One silhouette, five palette-ramp recolors, five scripts. **This is the replay incentive** — the 5 Phase-2 variants are the multi-boss experience of the whole game.

Boss gate: **6 distinct non-boss creatures seen**. Node telegraphs *"Hull 150+ recommended."*

**Feasibility arithmetic (binding, see §21.3):** ~15 Strike actions to clear 300 HP; incoming ≈155–170 (≈140–150 with Steel Plate), worst variant ~200. Minimalist-T4-proper (Hull 150 + Plate) must win **≥50%** of policy sims; max-Hull ≥90%.

---

## 16. The Dock

Every action costs 1 phase.

| Action | Effect |
| :--- | :--- |
| Refine | convert **all parts of one type** → materials; +1 expertise in that type |
| Upgrade | spend materials on one axis tier |
| Craft | build one tool from parts |
| Buy cosmetic | spend coins |
| Rest | +40 Hull |
| Depart | begin travel |

### Expertise 0–5, per material type

| Level | Effect |
| :--- | :--- |
| 0 | 1 part → 1 material |
| 1 | 1 part → 2 |
| 2 | **unlocks boat T2 upgrade purchases** in this material |
| 3 | 1 part → 3 |
| 4 | **unlocks boat T3 upgrade purchases** in this material |
| 5 | deep materials handled without loss |

**Deep materials** (Luminescence, Glass) lose 1 material per part below Expertise 5. Commons have no loss.

---

## 17. Economy

### Upgrade completion — all five axes to T3

| Material | Total | Parts at E3 |
| :--- | --: | :--- |
| Chitin | 19 | Shell Chip ×7 |
| Steel Plate | 6 | Plate Scrap ×2 |
| Gland | 21 | Gland Sac ×7 |
| Luminescence | 5 | Glow Polyp ×3 |
| Brine | 26 | Brine Vial ×9 |
| Coral | 26 | Coral Bud ×9 |
| Glass | 8 | Glass Pane ×4 |
| **Total** | **111** | **41 parts** + Steel Fins ×2 |

Typical hunt drops 3–6 parts → **~12–15 hunts to max the boat**, assuming Expertise investment. Dock phases (refining, upgrading, crafting) are additional; a focused run is ~3 in-game weeks. T2/T3 purchases are Expertise-gated (E2/E4 in each material spent, §16) — the refining phases that raise expertise are part of the estimate.

**Pace is sacred.** Deep drops are enriched (Squid Glass Pane ×4, Ghost-Ray Glow Polyp ×4, Wrasse Glass Pane ×2) and deep costs reduced (Lum 5, Glass 8) so the deep axes need roughly one Squid and one Ghost-Ray, not a month of grinding.

### Cosmetic completion

12 × ~175 = **2,100 coins**. Common sale average **24**. ≈ 88 common sales ≈ 29 short expeditions ≈ **~73 in-game days**. Rare sales and Oxygen accelerate this. Full 100% ≈ **3 in-game months**.

### Material sources

| Material | Common sources | Rare sources |
| :--- | :--- | :--- |
| Chitin | all T1 commons | — |
| Steel Plate | Steel Tuna, Rust Tuna, Tunisteel | Wrasse, Derelict |
| Gland | Eel, Electric Eel, Mileel, Anemone | Derelict |
| Brine | Brine Jelly | Lantern-Jelly, Ghost-Ray, Squid, Angler |
| Coral | Kelp Crab, Barnacle | Coral Crab, Wrasse, Derelict |
| Luminescence | — | Lantern-Jelly, Ghost-Ray, Angler, Derelict |
| Glass | — | Squid, Wrasse, Derelict |

Only Luminescence and Glass are rare-gated. They gate Precision and Speed — the "deep hunter" axes — which puts the release loop on the critical path to the best builds.

The full game adds T2–T4 sources for every material (M13 re-derives this table); no material may become unobtainable, and deep materials keep at least one rare source per relevant tier band.

---

## 18. Manual and Journal

**Manual:** HTML 4.0 on the CD. Numbered pages, one mechanic per page, worked examples. Pages: 1 The Drowned World · 2 The Hunt · 3 Drops & Loot · 4 Refinement · 5 Calendar · 6 Equipment · 7 The Signal · 8 Cosmetics & Score · Legends.

**Legends page:** Named creatures as *unconfirmed sightings — investigate if you can.* **2 entries in T1** (Mileel, Tunisteel); T2–T4 named creatures add entries at M13. No locations, no stats, no tips.

**Journal:** reactive, never proactive. **19 entries in T1** (18 non-boss + 1 boss, incl. 2 flex), full game = one per creature (≈49–55). One paragraph each, first-person, past tense, observational. **Non-boss entry is written when the first fight with that creature ends (any outcome).** Boss entry unlocks only after the first kill. Updates silently; a "New entry" indicator appears on the Esc menu. No popups.

**Tooltips:** only two, first time each mechanic appears —
*"Restrain damages Resolve, not HP."* / *"Past the red zone is overkill. It costs you the rare."*

---

## 19. Scoring and the End

Boss killed → credits → score screen → **the game continues**.

Three panels:

| Panel | Behavior |
| :--- | :--- |
| **Field Record** | Written **once** on the first Derelict kill. Never overwritten. |
| **Variants Seen** | 5-bit mask. **Bit set when Phase 2 is entered** — survives a later ascent. Shown as `3 / 5`, unseen grayed. |
| **Last Run** | Overwritten each engagement: cycles, Phase 2 identity, outcome, actions, Hull spent. Plus lifetime boss kills. |

Field Record fields: cycles elapsed · time in the field · creatures seen /N · rares seen /N · bosses killed /1 · final boss Phase 2 · subdued/killed/overkilled · expertise per material · money earned · cosmetics /12 · **the boat, rendered in full, decorated**. (time in the field = `World.field_phases`, total phases played; excluded from byte-identity goldens)

Closing line: *"Thank you for playing. The ocean is still there."*

---

## 20. First Run

```
1. Resolve exe directory; probe writability
2. Look for save0.dat
   ├─ valid    → load → main menu
   ├─ corrupt  → error screen → backup slot / fresh
   └─ absent   → FRESH INSTALL
3. FRESH INSTALL: full-screen text (terminal renderer regardless of art availability)
   → manual page 1 → [Enter] Begin
   → initialize world, dock, 0 coins, 0 journal entries
   → dock (art if available, else terminal)
4. First action is Depart → Z1
```

Initial save creation is **world initialization**, not an autosave. There is no autosave at any point.

---

## 21. Full-Game Content Model (T2–T4)

The 4-tier game is the deliverable; the demo gate is a mid-project checkpoint. T2–T4 content is authored at M13 under these rules (the T1 rows above are the worked example).

### 21.1 Variant taxonomy

Creatures come in **families**; a family shares a skeleton. Variants change behavior, color (ramp), and drop table.

| Tier of member | Naming | Example | Role |
| :--- | :--- | :--- | :--- |
| Base | `[Family]` | Mystic Eel | Teaches the tier's mechanic |
| Behavior variant | `[Adjective] [Family]` | Mystic Electric Eel | Same skeleton, different bar emphasis |
| Named | `[Compound]` | Mileel | Unique keystone drop, family grudge |
| Rare | `[Adjective] [NewFamily]` | Neon Ghost-Ray | Unique silhouette, rare-dominant zones |
| Boss | `The [Noun]` | The Derelict | **One per game** (see below) |

**Name generators:** adjectives = {Mystic, Steel, Neon, Glass, Coral, Rust, Abyssal, Brine, Trench, Sunken, Hollow, Chitin}; families = {Eel, Tuna, Crab, Jelly, Ray, Angler, Kelp, Squid, Barnacle, Wrasse}. **120 combinations.** Authoring will not run out. **Rares are unique per tier band** (never shared across bands): prefer invented species names in the style of *Anemoniacus* / *Freezing Perch*; the adjective×family generator is the fallback when inspiration fails. Sharing within one band's zones is allowed to fill tables.

**Family → base silhouette map (frozen; no new bases in T2–T4):**

| Family | Base | Family | Base |
| :--- | :--- | :--- | :--- |
| Eel | `eel00` | Angler | `angler00` |
| Tuna | `tuna00` | Kelp | `crab00` (kelp recolor) |
| Crab | `crab00` | Squid | `squid00` |
| Jelly | `jelly00` | Barnacle | `barn00` |
| Ray | `ray00` | Wrasse | `wrasse00` |
| Anemone (singletons) | `anem00` | Perch | `tuna00` (icy recolor) |
| Boss | `boss00` | | |

"Unique silhouette" for rares means recolor + overlay within the family base — not a new model.

**One boss per game.** No tier bosses. The Derelict's 5 adaptive Phase-2 variants are the multi-boss experience. T2–T4 have **Named** members as their apex fights.

### 21.2 Per-tier roster shape

Each tier band authors: **4–6 base/variant commons + 1 Named + 5 rares** ≈ 10–12 creatures. Full game = T1 17 + 2 flex + T2–T4 30–36 = **49–55 creatures**. Tier-1 has 17 (richer, it is the tutorial tier and the demo). M13 authors **30–36 rows** for T2–T4.

### 21.3 Stat scaling rules

| Value | T1 | T2 | T3 | T4 |
| :--- | :--- | :--- | :--- | :--- |
| Creature HP | 60–160 | 100–180 | 140–200 | 180–220 |
| Creature Resolve | 50–140 | 70–150 | 90–150 | 100–150 |
| Speed | 3–18 | 3–18 | 3–18 | 3–18 |
| Attack | commons 6–9, rares 9–12 | same | same | same |
| Subdue chance | 95 common / 80 named / 60 rare | same | same | same |
| Sale price | 10–70 | 20–80 | 30–90 | 40–100 |
| Respawn (sub/kill/over) | common 3/9/15, named 4/12/20, rare 6/18/30 | same | same | same |

**Fight length gate: ≤12 player actions at T1/T2, ≤14 at T3, ≤15 at T4** (subdue path = Strike HP to ≤50%, then Restrain Resolve to 0; avg ≈20/round Strike, ≈14/round Restrain). Depth reads as *endurance* — the Hull/oxygen clock is the pressure at T3/T4, not damage numbers. Damage ranges (Strike 15–25, Restrain 10–18) are **global and never creep**; tier difficulty comes from stats and behaviors.

Worked arithmetic (mid-band, actions ≈ HP/40 + Res/14):

| Tier | HP / Res mid-band | Expected subdue actions | Gate |
| :--- | :--- | :--- | :--- |
| T1 | 70 / 95 | ~2 + 7 = 9 | ≤12 |
| T2 | 140 / 110 | ~4 + 8 = 12 | ≤12 |
| T3 | 170 / 120 | ~4 + 9 = 13 | ≤14 |
| T4 | 200 / 125 | ~5 + 9 = 14 | ≤15 |

**Boss carry-over (the T4 ceiling — this is the balance constraint).** The Derelict must be beatable right after a **minimalist T4-proper loadout**: Hull 150 (telegraph minimum), Speed 15, Precision 15, one rigged tool = Steel Plate. Boss = 300 HP ÷ ~20/action ≈ **15 Strike actions** (Restrain disabled). Incoming ≈ P1 50 + P2 volleys 30–45 + P3 75 ≈ **155–170**, or ≈140–150 with Steel Plate; variant penalties (Blur double-strikes, Sliver slows the kill, Drown +25) push the worst case to **~200**. So: Hull 150 survives only with plate + favorable variant + a full-Hull entry; Hull 200 clears with margin. **Gate:** after T4 authoring, a boss-feasibility sim (fixed policy + seed set, minimalist loadout) must show kill rate **≥50% at Hull 150 + Plate** and **≥90% at max Hull**; M15 re-runs it after tuning. If T4 rows push the boss out of reach, move T4 bands or boss numbers (spec amendment) — never player damage.

### 21.4 Behavior composition rules

- Every creature uses only the existing rule-VM effect vocabulary (§24.6): REGEN_RES, REGEN_HP, HULL_DMG, SET_ARMOR, SET_FLEE, SET_BLIND, SET_INK, ADD_SPEED, MULT_ATK, MISS_STRIKE.
- At least one **bar-switch pressure** per creature (Thrash/Despair override or threshold behavior).
- At most one "signature" trick per creature beyond the coupling pressure (decoy, phasing, ink, discharge, shell…).
- Named creatures: unique keystone drop (used as-is) + family grudge (overkill of any family member this run).
- Stationary flag allowed (cannot flee) as in T1.

### 21.5 Drop and economy rules (M13 re-derivation)

- Parts vocabulary: the 9 base parts (§14.1) plus up to 3 new keystone parts (one per T2–T4 Named; MAX_PARTS 14). Keystones are drop-only and never required by tools, so §17's 111+2 economy totals are unchanged.
- Deep sources spread: every material has ≥1 common source OR ≥2 rare sources in the tier band that needs it.
- The §17 arithmetic must close for the full run: total boat cost 111 materials + 2 Steel Fins stays fixed (boat is global, not per-tier). M15 verifies full-run pacing with sims.
- Sale prices rise with tier (§21.3) so cosmetic completion does not slow down in late tiers.

### 21.6 Zone assignment

Z4 (Kelp Basin, T2 commons+named) · Z5 (The Shelf, T2 rares) · Z6 (Wreck Line, T3 commons+named) · Z7 (The Hollow, T3 rares) · Z8 (The Trench, T4 commons + rares). Named creatures appear in their band's commons zone (day-weighted). Rares appear in the band's rare zone and bleed at low weight into the commons zone (≤10%).

---

---

# PART II — THE IMPLEMENTATION

## 22. Constraints and Architecture

| Constraint | Value |
| :--- | :--- |
| OS | Win98SE / ME, PE32, **no-CRT** |
| Graphics | DirectDraw7, **windowed** (`DDSCL_NORMAL`) |
| Logical resolution | 640×480 |
| Imports allowed | `GDI32`, `USER32`, `KERNEL32` only; `ddraw.dll` loaded dynamically |
| Audio | DirectSound, loaded dynamically |
| RAM floor | 64 MB; target working set ≤ 8 MB |
| Concurrency | single-threaded, no event loop, no preemption |

**API generation lock: DirectX 7 only** — DirectDraw7 + DirectSound from the DX7 runtime, no mixing of DX generations anywhere (no D3D8, no DX8 surfaces, no DX8 headers/GUIDs). Stay on DirectDraw7. The game is 2D and turn-based; the DD7 windowed discipline is proven, needs no `dxguid` link and no `CoInitialize`. **Prerequisite:** the DX7 runtime (`ddraw7`); Win98SE ships DX6a — the CD/manual must state the DX7 runtime prerequisite, and startup falls back to terminal mode with a logged reason when DD7 cannot open.

```
main.z98
  ├─ std.os.initArgs / cwd / env       (startup, once)
  ├─ writability probe → data directory
  ├─ std.debug.setTrapHandler
  ├─ permanent arena / frame arena
  ├─ data.z98      text tables → defs
  ├─ game.z98      PURE state machine — no I/O, no rendering
  │    ├─ fight.z98 · expedition.z98 · behavior.z98
  ├─ input.z98     event → Action
  ├─ render_term.z98 / render_art.z98
  └─ persist.z98
```

**Hard rule: `game.z98` performs no I/O and calls no rendering function.** It takes `*GameState` + `Action`, mutates state, appends to a fixed-size log. This is what makes headless simulation, replay, and golden tests possible.

**Do not use `std.async` for game logic.** Coroutines are caller-driven with no executor; a suspending function's address cannot be taken; the frame pool needs 8-aligned storage and has a sticky OOM mode. A turn-based game has no concurrency problem to solve.

### Main loop

```
while (running) {
    pumpInput();
    while (pendingAction()) gameStep(&state, nextAction());
    updateTweens(nowTicks());   // visual only
    renderDirty(&state);
    gfxWaitEvent(g, idleTimeoutMs);
}
```

---

## 23. Stdlib Readiness

**M1 re-audits the real `sf/src/` surface first — do not assume.** The gap list below is the current best knowledge and is known to be partially stale; M1's first deliverable is a corrected gap table.

### Already present and sufficient (probed 2026-11-12)

`std.arena` · `std.pool` · `std.os` (initArgs/argc/argv/env/cwd/exit) · `std.time` (highRes/highResFreq/ticksMs) · `std.debug` (setTrapHandler/writeCoreDump/backtrace/logInt) · `std_gfx` cell tier · `std.buf` · **`std_file`** (open/read/write/seek/size/flush/exists/mtime/remove/rename/readAll/writeAll/openDir/readDir/closeDir) · **`std_str`** (eql/trim/indexOf/lastIndexOf/startsWith/endsWith/eqIgnoreCase/split/splitLines/join/replace/count/repeat) · **`std_dsound`** (dsoundOpen/Write/Queued/BackendKind/Close — a **streaming** API, not the buffer/WAV/play/stop API below).

### Gaps to close (to re-derive at M1)

| # | Pri | Item | Why |
| :-- | :-- | :--- | :--- |
| G1 | — | ~~file I/O~~ | **already present** (audit note; M1 confirms coverage incl. `readAll`/`writeAll`) |
| G2 | P0 | std_str: splitOnce only; int↔text via std_parse (G17 closed by reuse) | the text parser |
| G3 | P0 | `std.mem`: copy, set, eql (confirm surface) | struct copies, save assembly |
| G4 | P0 | `gfxWaitEvent(g, timeoutMs) bool` | the pump is polling; a turn-based game must not spin. `MsgWaitForMultipleObjectsEx`. |
| G5 | P0 | `Event.px`, `Event.py` (u32) | art-mode mouse hit-testing; cell coords are useless at 640×480 |
| G6 | P1 | **Pixel surface tier** `std_gfx_px` (§23.1) | the entire art renderer |
| G7 | P1 | `gfxSetFixedSize(g,w,h)` | art layout is fixed; cell grid is resizable |
| G8 | P1 | `gfxPresentRect(g,x,y,w,h)` | dirty-rect present |
| G9 | P5b/M12 | `std_audio` — DirectSound **buffers, WAV load, play/stop/volume** (static buffers; distinct from the existing streaming dsound) | ambient + cues |
| G10 | P0 | path join + 8.3 validation | Win98 MAX_PATH / short names |
| G11 | P0 | crc32 — **PARTIAL: incremental API already in `std_crypto` (`crc32Init/Update/Final`); add only the one-shot `crc32(data)` there** (no duplicate table) | save integrity |
| G12 | — | min/max/clamp/abs i32 | **CLOSED-ALREADY — reuse `std_math`** (`min`:1, `max`:6, `abs`:21, `clamp`:26; no game-side copies) |
| G13 | P0 | `EventKind.focus_lost` / `focus_gained` + `gfxTestFocus(g,bool)` | pause-on-focus is otherwise unimplementable; also automates the test |
| G14 | P0 | writability probe + fallback directory (game-side; **extend `std_os` with `modulePath`** via `GetModuleFileNameA`, POSIX null) | CD install |
| G15 | P1 | console-subsystem link config (`undtool.exe`) | Win98 has no `AttachConsole` |
| G16 | P2 | rename/remove verified + rollback-safe wrapper | save write path |
| G17 | — | int↔text — **CLOSED-ALREADY by reuse**: `std_parse` (`parseInt`/`parseUint`/`itoa`) is imported bare by applications (z9torr precedent); add no twins | save serialization + M6 parser |

### 23.1 The pixel tier — 16bpp, not 8bpp

In `DDSCL_NORMAL` you cannot realize a full 256-colour palette; the desktop owns it and you get the 20 static Windows colours. Fullscreen exclusive is out of scope. Therefore:

- **Sprites stay 8bpp indexed in RAM** — small, recolorable.
- **Offscreen surface is 16bpp (565)**, 640×480 = 614,400 bytes.
- Blit converts indexed → 565 through a per-sprite 256-entry `u16` LUT built at load.
- No `IDirectDrawPalette`, no desktop arbitration, works at any desktop depth ≥16bpp.

```zig
pub const PxError = error{ OpenFailed, SurfaceFailed, LockFailed, OutOfMemory };
pub const Surface = struct { pixels: [*]u8, pitch: i32, w: u32, h: u32 };
pub const Sprite  = struct { w: u32, h: u32, idx: [*]const u8,
                             lut: [*]const u16, key: u8 };

pub fn gfxPxOpen(title: []const u8, w: u32, h: u32) PxError!*Gfx;
pub fn gfxPxLock(g: *Gfx) PxError!Surface;
pub fn gfxPxUnlock(g: *Gfx) void;
pub fn gfxPxBlit(g: *Gfx, dx: i32, dy: i32, s: *const Sprite) void;
pub fn gfxPxBlitPart(g: *Gfx, dx: i32, dy: i32, s: *const Sprite,
                     sx: i32, sy: i32, sw: i32, sh: i32) void;
pub fn gfxPxFill(g: *Gfx, x: i32, y: i32, w: i32, h: i32, rgb565: u16) void;
pub fn gfxPxPresent(g: *Gfx, x: i32, y: i32, w: i32, h: i32) void;
```

PAL notes: vtable slot order is taken from the **typed ddraw vtable in `sf/src/std_ddraw_pal.zig`** (the z9gb-proven code) — `std_gfx_pal.zig`'s `Lock`/`Unlock`/`BltFast` placeholders must be typed first; unused slots preserved; a wrong order fails silently. Every COM call through `extern "stdcall"` fn-pointer types with the convention-qualified cast. **Windowed present contract:** `Blt` (never `BltFast` — it ignores clippers) to primary with a clipper attached, dest rect in **screen coords** (`ClientToScreen`), `DDBLT_WAIT`. Blit/Fill require a held lock; Present requires the surface **unlocked** (`DDERR_SURFACEBUSY` otherwise). `DDERR_SURFACELOST` → `Restore()` → re-lock → **full widget repaint** (VRAM content is gone). Offscreen surface is `DDSCAPS_SYSTEMMEMORY`. Clip in software before touching locked pixels. **Depth rule:** query `GetPixelFormat` masks at open (565 vs 555 skew is real on VxD-era cards); desktop depth **below 16bpp (including 256-colour 8bpp) refuses art mode → terminal mode**; GDI fallback (24-bit DIB + `StretchDIBits`) covers DD-present failure at ≥16bpp only.

**Sibling module, not a fork.** `std_gfx_px` shares the window/pump/COM PAL but does not touch the cell contract, themes, glyph atlas, or `gfxDumpGrid`. `z9edit` goldens must stay byte-identical — that is the acceptance test.

---

## 24. Z98 Design Rules

Each of these is a compile error or a runtime trap, not a style preference.

| # | Rule |
| :-- | :--- |
| R1 | **Never store to a tagged-union payload member.** `x.fight.hp = 5` is a hard reject. Keep mutable state in **flat structs**; unions only for coarse dispatch. |
| R2 | **No function-local `const` in `switch` case items.** All tuning constants and masks are **module-level**. |
| R3 | **`switch` requires `else`, always.** `unreachable` traps in both modes — use `else => {}` or a real fallback. |
| R4 | **Do not call through `?fn`** — call-through-unwrap is unproven. Plain `fn` fields with a no-op default. |
| R5 | **A suspending function's address cannot be taken.** No coroutine vtables. |
| R6 | **`-fsafe` traps on `+`, `-`, `*` overflow.** All combat math in **`i32`**, never `u8`/`u16`. |
| R7 | **RNG must not multiply** — an LCG overflows u32 and traps. Use **xorshift32**. |
| R8 | **`undefined` is `0xAA` under `-fsafe`, not zero.** Explicitly init every field. |
| R9 | **`print` rejects aggregates containing arrays, slices, optionals, error unions, or void.** Write explicit field-by-field dumps. |
| R10 | **Avoid `i64`/`u64`/`f64` in structs** — they force align-8. Keep `highRes()` results in locals. |
| R11 | **No floats.** Integer percent math, one rounding rule (§25.4). |
| R12 | **Prefer `u32` bitmasks over `packed struct` flags** — packed whole-value stores across byte-aligned containers reject. |
| R13 | **Integer width/signedness changes only warn.** Use `@intCast` explicitly; build with `-W`. |
| R14 | **No generics, `anytype`, `comptime`, or reflection.** Fixed-capacity arrays, runtime-parsed tables. |
| R15 | **`try` needs an enclosing error union whose names are a superset.** One named error set per subsystem. |

---

## 25. Core Game Logic

### 25.1 Capacities (module-level, FULL GAME from M1)

```zig
pub const MAX_CREATURES: usize = 56;   // ~49–55 roster + flex
pub const MAX_ZONES: usize = 12;       // 8 hunting + boss + spare
pub const MAX_DROP_LINES: usize = 4;
pub const MAX_TOOLS: usize = 8;
pub const MAX_PARTS: usize = 14;
pub const MAX_MATERIALS: usize = 10;
pub const MAX_RULES: usize = 96;      // global rules table, ~2/creature
pub const MAX_ENCOUNTER: usize = 24;  // per zone per phase
pub const MAX_LOG: usize = 64;
pub const MAX_COSMETICS: usize = 12;
pub const SUBDUE_PROMPT_BELOW: i32 = 90;
```

These are fixed at M1. T1 content uses a prefix of each table; M13 fills the rest. **Never resize later** (R14: no generics, arrays are baked).

### 25.2 Static definition

```zig
pub const DropLine = struct { part: i32, count: i32 };

pub const CreatureDef = struct {
    id: i32, family: i32, role: i32,
    zone_mask: u32, phase_mask: u32,
    hp: i32, resolve: i32, speed: i32, attack: i32,
    thrash_regen: i32, despair_regen: i32,
    armor_pct: i32, flags: u32,
    resist_restrain_pct: i32,                 // Shell/Phasing: Restrain damage pct (100 = none)
    blind_chance: i32,                        // Lantern-Jelly: % chance next Strike is blinded (50)
    subdue_chance: i32,                       // 0..100, -1 = cannot subdue
    discharge_stat: i32, discharge_th: i32, discharge_dmg: i32,
    armor_below_th: i32, armor_below_pct: i32,
    speed_below_stat: i32, speed_below_th: i32, speed_below_add: i32,
    atk_below_th: i32, atk_below_pct: i32,
    flee_kind: i32, flee_th: i32,
    grudge_family: i32, grudge_kind: i32, grudge_value: i32,
    sub:  [MAX_DROP_LINES]DropLine,
    kill: [MAX_DROP_LINES]DropLine,
    over: [MAX_DROP_LINES]DropLine,
    sale: i32, respawn: [3]i32, counter_tool: i32,
    rule_start: i32, rule_count: i32,
};
```

≈200 bytes × 56 = **11.2 KB**. Loader asserts `subdue_chance == -1` iff `flags & F_BOSS`, and rejects any other value outside 0..100.

### 25.3 Fight state — flat, never a union payload

```zig
pub const FightState = struct {
    def_index: i32,
    hp: i32, max_hp: i32, res: i32, max_res: i32,
    hull: i32, max_hull: i32,
    player_speed: i32, margin_pct: i32,
    round: i32, actions: i32, outcome: i32, flags: u32,
    prev_hp: i32, prev_res: i32,
    subdue_declined: i32, surge_count: i32, surge_atk_applied: i32,
    tool: i32, tool_charge: i32, tool_broken: i32, tool_active: i32,
    phase_state: i32, boss_phase: i32, boss_axis: i32,
    last_bar: i32, switches: i32, hull_spent: i32,
    rng_state: u32,
};
```

≈130 bytes. Copyable by value, trivially serializable, no R1 violations possible. Extended at M2 with flat effect state (no unions): `rule_consumed: u32` (one-shot bits per rule row), `pending_blind: i32`, `pending_ink: i32`, `pending_flee: i32`, `active_armor_pct: i32`, `active_resist_restrain: i32`. Field semantics: `*_below_pct` values are **percentage points added to 100** (Angler `atk_below_pct=50` → atk_pct 150; never chain multipliers). `flags` bit vocabulary (module consts): `F_BOSS=1`, `F_STATIONARY=2`, `F_SHELL=4`, `F_PHASING=8`, `F_DECOY=16`, `F_INK=32`, `F_GRUDGE_ARMOR=64`.

**GameState** (the `gameStep` carrier; also flat): `fight: FightState`, `world: World`, `log` (fixed array of `LogEntry`, `MAX_LOG=64`, drop-oldest), `expedition` flat fields (hold `[MAX_PARTS]i32`, fight_index, travel state), `screen: i32`, `rng ok`. **`LogEntry` format** (stable, replay-goldened): `{ class: i32, msg_id: i32, a: i32, b: i32 }` — rendered via a message table, never stored as strings.

```zig
pub const Expedition = struct {
    active: i32, zone: i32, fight_index: i32, seed: u32,
    hold: [MAX_PARTS]i32, hold_n: i32,
};
// GameState carries: exp: Expedition, pending_cond: i32.
pub const Effect = struct { op: i32, a: i32, b: i32 };
```

`gameStep` mutates `GameState`; all modules take `*GameState` (fight, rest, depart).

### 25.4 Fixed point

```zig
pub fn applyPct(v: i32, pct: i32) i32 { return (v * pct) / 100; }
```

**Truncation toward zero, applied once, after all multipliers accumulate.** Never chain `applyPct`. Margin: `(max_hp * margin_pct) / 100`. Surge restore uses integer ceil: `(max_res * 30 + 99) / 100`.

### 25.5 RNG — xorshift32

```zig
pub fn rngNext(s: *u32) u32 {
    var x = s.*;
    x = x ^ (x << 13);
    x = x ^ (x >> 17);
    x = x ^ (x << 5);
    s.* = x;
    return x;
}
pub fn rngRange(s: *u32, lo: i32, hi: i32) i32 {
    return lo + @intCast(i32, rngNext(s) % @intCast(u32, hi - lo + 1));
}
```

Shifts and XOR only — no overflow trap. Seed per fight: `expedition_seed + fight_index * 77`. **A subdue roll consumes exactly one draw; a decline consumes none.**

**RNG determinism contract (binding for replay goldens):**

| Event | Draws | Mapping |
| :--- | --: | :--- |
| Subdue roll | 1 | success iff `rngRange(1, 100) <= subdue_chance` |
| Decline / F / Esc | 0 | — |
| Ink randomization | 1 | `rngRange(0, 2)` → Strike/Restrain/Equipment (never Flee) |
| Rough-sleep condition | 1 | `rngRange(0, 2)` → Drowsy/Shaky/Exposed |
| Encounter weighted roll | 1 | `rngRange(1, total_weight)` across the apportioned table |
| Strike / Restrain damage | 1 | `rngRange(15, 25)` / `rngRange(10, 18)` |

Zero-seed guard: if state becomes 0, reseed to `0x9E3779B9`. Warm-up: run `rngNext` 3× on a fresh seed before first draw (kills seed correlation across fights; `+ fight_index*77` streams would otherwise overlap). Modulo bias in `rngRange` is accepted (ranges are small vs u32). World RNG: `World.rng_state` seeds `expedition_seed` at Depart (`expedition_seed = rngNext(&w.rng_state)`).

### 25.6 Behavior — a rule VM, not function pointers

```zig
pub const Rule = struct {
    cond_op: i32,   // HP_BELOW, RES_BELOW, ROUND_MOD, FIRST_ROUND, ALWAYS
    cond_a: i32, cond_b: i32,
    effect_op: i32, // REGEN_RES, REGEN_HP, HULL_DMG, SET_ARMOR, SET_FLEE,
                    // SET_BLIND, SET_INK, ADD_SPEED, MULT_ATK, MISS_STRIKE
                    // SET_BLIND uses effect_b = blind_chance pct (§8.7 timing: fires while condition true)
    effect_a: i32, effect_b: i32,
    timing: i32,    // 0 = one-shot on crossing, 1 = persistent while true
};
```

Chosen over fn pointers because: fn pointers need exact signature matches and cannot hold suspending functions; a rule table is serializable, validatable, and authorable **in the same text file as the stats**; the journal can generate its description from the same data. ~150 lines of interpreter, and the strongest data-driven showcase in the project.

One-shot detection: fire when `prev >= threshold && now < threshold`, then set a consumed bit.

### 25.7 World and cooldowns

```zig
pub const World = struct {
    cycle: i32, phase: i32,
    ready: [MAX_ZONES * MAX_CREATURES]i32,   // 672 entries
    seen_mask: [2]u32,                       // u32 words sized ceil(MAX_CREATURES/32)
    journal_mask: [2]u32,                    // journal entries unlocked (bit per def)
    tooltip_shown: u32,                      // once-only tooltips (bit flags)
    field_phases: i32,                       // total phases played (Field Record "time in the field")
    release_bonus: [MAX_ZONES]i32,
    lockout_until: [MAX_ZONES]i32,
    family_overkill_mask: u32, wary_mask: [2]u32,   // grudge mask cleared on Derelict kill (run boundary); wary/seen as u32 words sized ceil(MAX_CREATURES/32)
    rng_state: u32,                                  // world RNG (encounters, rough-sleep, expedition_seed)
    boat: [5]i32, money: i32,
    expertise: [MAX_MATERIALS]i32,
    cosmetics_owned: u32, cosmetics_unlocked: u32,
    field_record_written: i32,
    boss_variants_seen: u32, boss_kills: i32,
    // + frozen Field Record and Last Run flat structs
};
```

Index `zone * MAX_CREATURES + def_index`. Available when `cycle > ready` or (`cycle == ready` and phase == Day). **Seen/journal tracking uses a `u32` word array sized `ceil(MAX_CREATURES/32)`**, not a single mask (roster exceeds 32).

### 25.8 Algorithms

| Algorithm | Rule |
| :--- | :--- |
| Turn order | compare speeds, ties player |
| Coupling | end-of-round gated regen (§8.5) |
| Overkill | overshoot vs margin (§8.6) |
| Threshold one-shot | prev/now crossing + consumed bit |
| Phasing | `floor((round-1)/2) % 2`; lock Phase below 30% HP |
| Ink | every 3rd round, randomize next combat action, never Flee |
| Encounter | availability filter → rare-chance pipeline (§12) → weighted roll |
| Loot | fixed table + Cargo bonus to primary line |
| Expertise yield | 1→1/2/3; deep −1 below E5 |
| Dominant axis | max tier, tiebreak H>P>C>O>S, all-zero → Hull |
| Empty pool | no encounter, safe Rest |

### 25.9 Auto-sim policy (the §22 validator)

Subdue path unless the creature has Shell: `hp > 50% → Strike, else Restrain`. Kill path: `res > 50% → Restrain, else Strike`. Reports avg actions, bar-switch %, outcome distribution, **avg surges per rare fight**, **Emergency Ascent rate**.

---

## 26. Presentation Modes

| Mode | Backend | Surface | Ships to | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Art** | `std_gfx_px` | 640×480 px, 16bpp | player | default |
| **Terminal** | `std_gfx` | 80×30 cells, 16 colours | player | fully playable fallback; <16bpp (including 256-colour 8bpp desktops); DD failure |
| **Console** | `gfxOpenMemory` + stdout | none | tooling | replay, sim, tests, CI |

All three consume the same `*GameState` read-only. **Switching modes must never change game behaviour.**

**Terminal mode is not new infrastructure.** `std_gfx` already ships the glyph atlas, cell primitives, 16-colour themes, full event pump, GDI fallback, and headless grid dump. The only new work is the game's cell layout.

**Terminal ≠ console.** Terminal is a *windowed* TUI (GUI subsystem). Console has no window (CUI subsystem). Win98 has no `AttachConsole`, so:

| Binary | Subsystem | Modes |
| :--- | :--- | :--- |
| `under.exe` | `WINDOWS_GUI` | Art + Terminal |
| `undtool.exe` | `WINDOWS_CUI` | Console only |

One source tree, two link configs, both no-CRT, both must pass `check_win9x_imports.sh <exe> 9x`.

```
undtool.exe --sim 200 --creature ghostray --seed 98
undtool.exe --replay run01.rep
undtool.exe --test-rules
undtool.exe --dump-grid out.txt --screen fight
undtool.exe --validate-assets assets.man
undtool.exe --save-roundtrip save0.dat
```

### Console mode — *nix analogue (binding)

The console/CUI mode is **plain text I/O with COMMAND.COM-era semantics**: 80-column text, CRLF line ends, no ANSI escapes, no colour codes, stdin line input — the same behaviour a player would see piping `undtool.exe` in a Win98 COMMAND.COM box. One source tree builds it **two ways**: `undtool.exe` (WINDOWS_CUI, Win98) and a **native Linux binary** (`undtool.nix`, plain stdio). The *nix build is the authoritative CI test path — same `game.z98` code, same byte-identical output goldens.

### Test model (binding, all milestones)

| Tier class | Runs on | Authority |
| :--- | :--- | :--- |
| Logic/unit/sim/replay/save/content goldens | **native *nix `undtool.nix`** (fast) | **the gate** |
| Cell grid goldens (`gfxDumpGrid`), z9edit goldens | native headless | the gate |
| Art framebuffer goldens (pre-present dumps) | native software compose | the gate |
| DD7/DSound probes, windowed rendering, Wine runs | Wine / real HW | **evidence only, never the gate** |
| Win98 fidelity, perf, working set | operator on real HW (M16) | manual attestation |

Tier scripts label themselves FAST (gate) or SLOW (evidence) and must be runnable in CI without Wine. Wine escapes use an env opt-out (e.g. `Z9_NO_XVFB=1` pattern from z9edit).

### Terminal layout (80×30)

```
┌─ UNDERSANDED ── Z3 / NIGHT ── Fight 2/3 ── Tool: Sonar (1) ────────────┐
│ Neon Ghost-Ray            RARE   Ray family   SPD ?? (no journal entry) │
│ Phasing: SOLID (flips in 1)                                             │
│ HP      [████████████░░░░░░░░░░░░]  62/100   ▒▒ red zone 0–15           │
│ RESOLVE [██████████░░░░░░░░░░░░░░]  48/110   THRASH +5                  │
│ HULL    [████████████████████░░░░]  84/100                              │
│ > You Restrain for 14 Resolve.                                          │
│ > Neon Ghost-Ray hits you for 10 Hull.                                  │
│ [S]trike  [R]estrain  [E]quipment  [F]lee     12 actions · 2 switches    │
└─────────────────────────────────────────────────────────────────────────┘
```

Red zone uses `▒` shading **plus** an explicit numeric range. Bars carry inline numerics. Coupling tags appear only when the gate is live.

---

## 27. Render Engine

### Dirty rectangles, retained widgets

Turn-based means most of the screen is static. Do not redraw 640×480 every frame.

```zig
pub const Widget = struct {
    x: i32, y: i32, w: i32, h: i32,
    kind: i32, dirty: i32,
    a: i32, b: i32, c: i32,     // flat payload, not a union (R1)
    text_off: i32, sprite: i32,
};
```

Fixed array of ~64 widgets, rebuilt on screen change. Each frame: mark dirty → lock → repaint only those rects → unlock → present per coalesced rect. **Coalescing algorithm:** bounded rect list (max 32); merge when bounding boxes overlap or touch; overflow → single full-frame present. A typical action dirties ~15% of screen **area** (assert area bounds, not rect count). **Art goldens are pre-present in-memory framebuffer dumps** (software-composed, checksum) — never post-present screen readback (Wine/driver-dependent).

### Bars

- Fill width = `hp * bar_w / max_hp`.
- Red zone width = `clamp((25 − margin) * bar_w / max_hp, 0, bar_w)`.
- **Red zone carries a 1px dotted border in addition to colour**, and every bar carries an inline numeric (`HP 42/70`) — colour-blind safety.
- Coupling tags drawn only when the gate is active.

### Text

Art mode uses a **bitmap font atlas**, not GDI text — GDI metrics vary across Win98 machines and would break pixel-exact layout. 95 glyphs at 8×16 = 12 KB. Terminal mode keeps `gfxDrawText`.

### Layout (640×480, fixed)

```
┌──────────────────────────────────────────────┐
│ HUD: zone / phase / fight / tool / coins     │  32
├───────────────────────┬──────────────────────┤
│  creature sprite      │ name / role / family │
│  96×96 on zone bg     │ HP bar + red zone    │ 200
│                       │ Resolve bar          │
│                       │ Hull bar · spd/margin│
├───────────────────────┴──────────────────────┤
│ combat log (8 lines)                         │ 140
├──────────────────────────────────────────────┤
│ [Strike] [Restrain] [Equipment] [Flee]       │  56
└──────────────────────────────────────────────┘
```

No scaling. Window fixed-size in art mode.

---

## 28. Player Interaction

```
gfxPollEvent → RawEvent → keymap / hit-test → Action → game.z98
```

`Action` is `{ kind: i32, arg: i32 }`. **Every** mutation goes through an Action; no UI code writes `GameState` directly.

**Keyboard-first, fully playable without a mouse.**

| Key | Action |
| :--- | :--- |
| S / 1 | Strike |
| R / 2 | Restrain |
| E / 3 | Equipment |
| F / 4 | Flee |
| arrows / Tab | move focus |
| Enter / Space | confirm |
| Esc | menu |
| J | journal |
| ? | manual page for this screen |

Mouse hit-tests `Event.px/py` against button rects; click emits the same Action as the hotkey.

**`?` key:** shows the **in-game manual page for the current screen**. All manual pages are embedded as plain text in `data.z98` (the HTML 4.0 CD manual is the same content republished — one source of truth). No browser launch.

**Guards:** actions rejected when the fight is over; Restrain disabled vs boss with the journal line; Equipment disabled at 0 charge or broken, with the reason shown. Ink randomization happens **inside `game.z98`**, never in the input layer, and never selects Flee or a dialog choice.

**Esc menu:** Journal · Map · Save · Quit. Options live at the start menu only.

**Replay:** seed + action stream, version 2. Grammar (pinned): header `seed=` / `zone=` / `phase=` / `tool=` then one `A <verb>` line per action where verb ∈ `strike|restrain|equipment|flee|attempt|decline`. **F and Esc both record as `decline`** (they are identical per §9.3). Ink and encounter draws are not recorded — they derive from the seed (§25.5 draw table).

```
seed=98
zone=Z3
phase=night
tool=sonar
A strike
A restrain
A attempt
...
```

---

## 29. Timing

**Nothing advances unless something happened.**

| Situation | Behaviour |
| :--- | :--- |
| Idle | `gfxWaitEvent(g, 250)` — blocks, 0% CPU |
| Tween running | `gfxWaitEvent(g, 16)` until complete |
| Ambient audio | started once, stopped on pause/quit — not timed |
| Focus lost | pause logic, stop ambience, keep last frame; **no auto-resume** |

Game logic is untimed. A fight resolves identically at 0 fps and 60 fps.

### Tween accumulator

`highRes()` can return equal consecutive samples on the fallback clock, and `delta_ms` truncates to 0 for short intervals — a tween updated as `t += delta_ms / duration` would **never advance**. Accumulate raw ticks, divide once:

```zig
const TWEEN_MS: u32 = 180;

fn tweenAdvance(tw: *Tween, now: u64, freq: u64) void {
    if (freq == 0) { tw.done = 1; return; }
    const ms = (now - tw.start) * 1000 / freq;
    if (ms >= TWEEN_MS) { tw.done = 1; tw.pos = tw.to; return; }
    tw.pos = tw.from + (tw.to - tw.from) * @intCast(i32, ms) / @intCast(i32, TWEEN_MS);
}
```

Equal samples produce the same position — harmless. No clamp, no skip. `u64` in locals only.

---

## 30. Asset Pipeline

### Where each stage runs

| Stages | Runs on | Shipped |
| :--- | :--- | :--- |
| 0–9 palette, generation, conversion, validation, manifest | host | manifest only |
| decode `.ZSP` → indexed + 565 LUT | **Win98, Z98** | yes |

**The runtime decoder is ~40 lines of Z98. Nothing else crosses onto the target.** No PNG parser, no SVG parser, no zlib, no zstd on Win98.

### Stage 0 — lock the palette first

256 entries = **16 ramps × 16 shades**; index 255 reserved as the transparent key. Emit `palette.gpl`, `palette.png` (256×1), `palette.json` from one source. Anchor hexes (Dark / Mid / Light / Hi; intermediate shades interpolated across each ramp):

| Ramp | Purpose | Dark | Mid | Light | Hi |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 0 | UI neutrals / bevels / outlines | `#0A1420` | `#2A3A4A` | `#5A6A7A` | `#9AAABA` |
| 1 | Hull cyan | `#062A38` | `#0E5A72` | `#1E9AB8` | `#5FD4EC` |
| 2 | HP red → overkill crimson | `#3A0A10` | `#8A1622` | `#D42A3C` | `#FF6A78` |
| 3 | Resolve green | `#062A18` | `#0E6A3A` | `#22B46A` | `#6AE8A4` |
| 4 | Warning amber | `#3A2408` | `#8A5A12` | `#D49A28` | `#FFCC66` |
| 5 | Rare magenta | `#320A2A` | `#7A1A62` | `#C43AA0` | `#F47AD8` |
| 6 | Eel | `#06282E` | `#0E6270` | `#1CA8B8` | `#66E0EC` |
| 7 | Tuna | `#101C2E` | `#2A4468` | `#4A76A8` | `#8AB4DC` |
| 8 | Crab | `#3A1808` | `#8A4212` | `#D4762A` | `#F4B066` |
| 9 | Jelly | `#3A1428` | `#8A4468` | `#C88AA8` | `#F4C8DC` |
| 10 | Barnacle | `#14181C` | `#3A4248` | `#6A747C` | `#A8B2BA` |
| 11 | Anemone | `#3A0A22` | `#8A1A52` | `#D43A88` | `#FF7AC0` |
| 12 | Ray | `#122A18` | `#2E6A3C` | `#5AA868` | `#A0DCAC` |
| 13 | Squid | `#1A2836` | `#44607A` | `#8AAAC4` | `#CCE4F4` |
| 14 | Angler/rust | `#241608` | `#5A3A18` | `#8A6230` | `#C49A5C` |
| 15 | Wrasse | `#082A28` | `#126A5E` | `#28A88A` | `#6AE0C0` |

This is what makes recolors free: creatures need only **11 base silhouettes**, and the Derelict's five identities are one sprite with five ramp assignments.

### Stage 1 — source track

**SVG, authored at target size in ramp hexes** (no AI generation, no downscale, no quantize). UI chrome, icons, boat, cosmetic overlays, sigils, creature bases, backgrounds — all SVG. Fills use **only** the 256 locked hexes; no gradients, no opacity, no filters, no text elements. A **transitory, uncommitted** lint script enforces it (see converter policy below). `shape-rendering="crispEdges"`; batch with **rsvg-convert** (1:1, no resampling) — transitory tooling.

If any asset is ever produced as PNG instead: box-filter downscale (not Lanczos), alpha<128 → key, remap with `-dither None` (never dither), then the same outline/ramp stages.

### Stages 2–8

```
SVG ─[2 rasterize 1:1]─[3 alpha→key]─[5 outline]─[6 ramp assert]─[7 .ZSP]─[8 validate]
```

| Stage | Command / rule |
| :--- | :--- |
| 2 | `rsvg-convert $f -o ${f%.svg}.png` (declared target size; no resampling) — transitory |
| 3 | `alpha < 128 → index 255`; composite onto ramp-0 shade-0 first so edges don't fringe |
| 5 | enforce 1px ramp-0/shade-0 outline around the alpha mask (normalizes stroke rendering) |
| 6 | **assert only** — fail the build if a pixel falls outside the asset's allowed ramp set + key |
| 7 | encode `.ZSP` — transitory script; **canonical rule: one run per maximal stretch, count 1–255, split longer stretches** (byte-exact goldens depend on it) |
| 8 | validate; build fails on any violation |

**Validation checks** (run by the committed Z98 tool **`undtool --validate-assets`**, never by the transitory converter): dimensions match target · every pixel inside the asset's allowed ramp set + key · creature has a transparent border · RLE round-trip byte-exact · filename 8.3 lowercase no spaces · cumulative budget · manifest entry present.

### `.ZSP` format

```
header 16B: 'Z','S','P','1' | w u16 | h u16 | key u8 | ramp u8 | flags u16 | reserved u32
palette 512B: 256 × u16 RGB565
data: RLE runs [count u8][index u8], count 1..255
```

### Font — do not generate it

Use a **period bitmap font** (8×16 VGA ROM, public domain). Pixel-exact, era-correct, 12 KB. AI letterforms at 8px will be inconsistent and will break layout.

### Boat and cosmetics

One 200×150 SVG base (`boat00`). Paint = ramp swap on the hull region (zero new pixels). Figurehead / Flag / Decal = 64×64 overlays at fixed anchors (24,40) / (150,18) / (96,96). Blit order: base → paint ramp → decal → figurehead → flag. The three porthole circles are the only non-polygon primitives — if a rasterizer softens circles, replace with 16/12/8-sided polygons.

### Asset manifest (full game)

| Asset | 8.3 name(s) | Notes |
| :--- | :--- | :--- |
| Creature bases (11) | `eel00 tuna00 crab00 jelly00 barn00 anem00 ray00 squid00 angler00 wrasse00 boss00` | 96×96; 4 family bases → 6 recolors; 6 singletons; boss 1 base × 5 ramps; flex recolors: anem00 (Anemoniacus), tuna00 icy (Freezing Perch) |
| Backgrounds (demo 5) | `bg_a bg_b bg_c bg_d bg_dock` | 640×300, banded, ≤8 colours, ≤120 KB encoded each |
| Backgrounds (full +M14) | `bg_z4 bg_z5 bg_z6 bg_z7 bg_z8` | Z4–Z8; same rules |
| Boat | `boat00` | 200×150 |
| Cosmetic overlays (9) | `fig_merm fig_angl fig_krak flag_pen flag_ref flag_trn dec_barn dec_sqid dec_boss` | 64×64 (flags taller where authored) |
| Font | `font8x16` | 95 glyphs, 8×16 |

(T1 naming corrections applied: `barn00`, `anem00`, `fig_merm`, `fig_angl`, `fig_krak`, `flag_pen`, `flag_ref`, `flag_trn`, `dec_barn`, `dec_sqid`, `dec_boss` — all 8.3-safe.)

**Backgrounds are the budget risk.** Author large flat areas, render depth as **ordered bands** not smooth gradients, cap at 8 unique colours. If a background exceeds 120 KB encoded, reduce colours and re-encode. **Backgrounds load on demand** — only the current zone's background is resident (see §35).

### Asset conversion policy (era reproducibility — P19)

**No committed tooling outside Z98 + shell.** The SVG→`.ZSP` converter is **transitory and uncommitted**: an ad-hoc script (Python or anything else) runs on the author's machine, produces `.ZSP` files, and is thrown away. The **committed artifacts of record** are the `.ZSP` files (+ SVG sources as human-readable art documents) and the **Z98 `undtool --validate-assets`** tool that re-checks every invariant in CI with no Python present. Regeneration recipe (one paragraph, incl. canonical RLE rule) lives in NOTES.md.

This is stricter than "not shipped": a committed converter would mean the project cannot be built in its own era. Transitory Python for one-off translation or golden-seed generation is explicitly fine — it never becomes a build dependency, never enters the repo, and every committed check runs on Z98.

**zstd is offline only.** Pack `.ZSP` into `.ZPK` on the host if you want single-file distribution; the runtime stays RLE-only. Ship **loose files** — easier to debug and hot-swap during review.

---

## 31. Audio

| Item | Rule |
| :--- | :--- |
| Ambient | WAV 22.05 kHz, 16-bit, mono, 90 s = 3,969,000 bytes ≈ 3.79 MiB |
| Caps | `DSBCAPS_GLOBALFOCUS \| DSBCAPS_STATIC \| DSBCAPS_CTRLVOLUME` (**CTRLVOLUME is mandatory** — `SetVolume` returns `DSERR_CONTROLUNAVAIL` without it). **Never `LOCHARDWARE`** — a 3.9 MB buffer will not fit a 4 MB card. Accept software mixing. Cooperative level `DSSCL_NORMAL`. |
| Playback | `Play(0, 0, DSBPLAY_LOOPING)` once. No callback, no thread, no streaming. **Cue replay protocol: `Stop()` → `SetCurrentPosition(0)` → `Play(0)`** (a finished buffer resumes at end = silence otherwise). |
| **Focus loss** | **`Stop()` is mandatory.** GLOBALFOCUS keeps the buffer *playing*; without Stop the game "pauses" with audio running. Restart only after the player confirms resume. |
| Volume | `SetVolume` from options, persisted (0–100 → dsound hundredths-of-dB attenuation, negative range) |
| Loop point | authored gapless; offline 250 ms tail→head crossfade; verified on real hardware |

| Cue | Trigger | Length |
| :--- | :--- | :--- |
| `hit.wav` | any player Strike lands | ≤0.5 s |
| `subdue.wav` | subdue success | ≤1 s |
| `kill.wav` | kill outcome | ≤1 s |
| `bosskill.wav` | Derelict first kill | ≤3 s |

All 22.05 kHz mono, static buffers at startup, `Play(0)`, overlap allowed. **Overlap policy:** each hot cue (hit) gets 2 rotating duplicate buffers so rapid re-triggers don't cut each other; cold cues (subdue/kill/bosskill) restart via the replay protocol. **Subdue failure has no cue** — warn log + screen shake. No composed music; the ambient bed is the entire soundtrack.

---

## 32. Save System

**Text, not binary.** Same parser as the data tables, human-readable, diffable.

```
version=2
data_version=2
[world]
cycle=...
[boat] ...
[cooldowns] ...
[journal] ...
[score]
field_record_written=0|1
field_record=...
boss_variants_seen=0..31
boss_kills=N
last_run=...
[crc32]
hash=0x........
```

`version` = format layout. `data_version` = content IDs. `hash` = CRC32 of everything above `[crc32]`.

### Load checks

| Check | On failure |
| :--- | :--- |
| file exists | fresh install flow |
| `version` matches | error screen → fresh / backup slot / quit |
| `data_version` matches | error screen → same options. **No auto-migration.** |
| CRC32 matches | error screen → backup slot / fresh |
| all IDs resolve | error screen → same options |

### Write path (with rollback)

```
1. serialize → save.tmp
2. flush + close
3. re-read save.tmp, verify CRC
4. remove stale save.bak if present; rename save0.dat → save.bak
5. rename save.tmp → save0.dat
6. on ANY failure at 5: rename save.bak → save0.dat
```

Step 4's delete is **mandatory on Win9x** — `MoveFileA` fails when the destination exists (`MoveFileEx(MOVEFILE_REPLACE_EXISTING)` is not available on 9x). Host tests using POSIX rename(2) will NOT catch this bug.

**Startup recovery:** if `save0.dat` is missing but `save.bak` exists → restore `save.bak` → `save0.dat` (log it). Delete stale `save.tmp` on load. Step 6 is mandatory — without it a failed step 5 leaves no `save0.dat` at all.

`save1.dat` is a manual backup slot chosen in options, never auto-written.

### Save UX

Esc → Save, unavailable only mid-fight (travel is instantaneous at depart/return; there is no persistent in-transit state). Greyed with the reason otherwise. Quit prompts *"Save before quitting? [Y] [N] [Cancel]"* if unsaved. **No autosave.**

### Data directory

Resolve via `GetModuleFileNameA`, strip filename. **Probe writability** (create + delete `probe.tmp`). `data.z98` is always **read from the exe directory** (it is installed content). If the probe fails — CD-ROM, network share — **mutable files only** (saves, `options.cfg` (save-slot choice only), `crash.*`, `errors.log`, `grid.txt`, `probe.tmp`) are written to `C:\WINDOWS\TEMP\UNDERSAN\`; create it, log the redirect, show the path once.

---

## 33. Error UX and Crash Handling

### Fatal

| Condition | Message |
| :--- | :--- |
| `data.z98` missing | "Content file missing. Reinstall from CD." |
| `data.z98` parse failure | "Content file is damaged at line N. Reinstall from CD." |
| save corrupt, no backup | "Save file is damaged. Starting fresh." → fresh install |
| version mismatch | "Save is from a different version." → fresh / backup slot |
| DirectDraw cannot open | **not fatal** — fall back to terminal, log the reason |
| Audio cannot open | **not fatal** — continue silently |

Error screen: full-screen text, 640×480, era-authentic, `[Enter] Quit`.

### Non-fatal

Warnings go to `errors.log` beside the exe and never interrupt play: missing sprite → placeholder; missing cosmetic overlay; backup slot written.

### Crash — three files, not one

`std.debug.writeCoreDump` writes **registers only** (`eip, esp, ebp, eflags, eax, ebx, ecx, edx, esi, edi`, one `name=decimal` per line). It does not write game state.

| File | Contents |
| :--- | :--- |
| `crash.dmp` | registers, via `writeCoreDump` |
| `crash.log` | backtrace into a **pre-allocated** `std.buf.Buf` |
| `crashstate.dat` | game serialization — **best-effort, guarded, skipped if the arena looks poisoned** |

The trap handler must avoid operations that could themselves fault; serializing full state after an overflow/OOB trap risks a second fault. `std.debug.assert/panic` write to **buffered stdout that may be lost** — use `@stderrWrite` for reliable messages. Pre-allocate the backtrace buffer at startup, never inside the handler.

Then: error screen — *"The game has crashed. A crash file has been written. Please report it."*

---

## 34. Testing

| Gate | Mechanism | Where |
| :--- | :--- | :--- |
| UI layout regression | `gfxOpenMemory` + `gfxDumpGrid` → byte-compare golden | CI, headless |
| Combat correctness | replay → exact outcome + log match | CI |
| Balance | `--sim N` → actions, switch %, outcomes, surges, ascent rate | CI + manual |
| Rule VM | `--test-rules` — each Rule against scripted states; **exit 0/1**, print count | CI |
| Save integrity | save → load → save byte-compare; rollback path exercised | CI |
| Data version | save v1, load v2 → expect error screen | CI |
| Subdue determinism | same seed + same action stream → identical rolls | CI |
| **Decline costs no RNG** | RNG state byte-identical before/after F/Esc | CI |
| **Commons never prompt** | no prompt event across 200 sim fights | CI |
| Surge caps | attack bonus ≤ +25 pp; speed bonus ≤ +6 | CI |
| Boss sentinel | loader rejects `subdue_chance != -1` on boss, `-1` on non-boss | CI |
| Variants bit | set on Phase 2 entry, survives ascent | CI |
| Field Record | second kill leaves record byte-identical | CI |
| Restore rounding | `(max*30+99)/100` == ceil for max 50…195 incl. grudge/wariness | CI |
| First run | delete save, launch, page 1 appears, fresh save created | CI |
| Focus pause | `gfxTestFocus(g,false)` → logic halts, audio stops | CI |
| Win98 fidelity | operator session on real hardware | manual |

Pixel output under Wine is font/driver-specific: **evidence, not a pass/fail gate.** The deterministic gates are the grid golden, the replay match, and the save round-trip.

---

## 35. Budgets

| Region | Size |
| :--- | --: |
| Permanent arena (defs, strings, save image) | 256 KB |
| Sprite arena (indexed + LUTs; creatures + font + UI + 1 resident background) | 2 MB |
| Frame arena | 64 KB |
| DD7 offscreen 640×480×16bpp | 600 KB |
| DD7 primary | 600 KB |
| Game state + world + logs | 64 KB |
| Ambient WAV static buffer | 3.9 MB |
| 4 cue buffers (hit ×2 rotating + 3 cold; 6.0 s total: hit×2 + subdue + kill + bosskill at 44.1 KB/s ≈ 265 KB) | 270 KB |
| **Total working set** | **≈ 7.5 MB** (≤ 8 MB target holds) |

Asset detail (demo gate): 19 creature sprites ~174 KB · boss 25 KB · 5 backgrounds 960 KB · boat 30 KB · 9 overlays 49 KB · font 12 KB · UI chrome 60 KB ≈ **1.35 MB indexed**. Full game (M14) adds T2–T4 recolors (cheap, ramp-swaps) + 5 zone backgrounds (+~960 KB indexed) — but **backgrounds are loaded on demand** (one resident at a time), so the sprite arena stays 2 MB. Disk at RLE ~4×: demo ≈ **300–400 KB**, full game ≈ **550–750 KB** (10 backgrounds × 40–120 KB + sprites). Per-background encoded cap: **120 KB**.

Performance target: **≤8 ms per dirty frame on a Pentium II 300**, achieved by dirty rects, LUT blits, and zero per-frame allocation.

---

## 36. Milestones M1–M16

The delivery spine. Each milestone is self-contained, testable in isolation, and has a hard exit criterion. Demo gate at M11. Plans live in `docs/superpowers/plans/2026-11-12-undersanded-mNN-*-plan.md`.

| # | Milestone | Deliverable | Exit criterion |
| :-- | :--- | :--- | :--- |
| **M1** | Stdlib audit + gaps | Re-derive the gap table against real `sf/src/`; patch G2–G5, G10, G11, G13; game-side writability probe (G14, `paths.zig`); scaffold G15 (2 link configs); `-W` clean; trap handler wired | No-CRT Win9x exe: opens a window, reads a text file, writes a file, writability probe works from a read-only dir, `check_win9x_imports.sh` passes |
| **M2** | Fight core + rule VM | Pure `game.z98` (flat structs, xorshift32, fixed-point), coupling rule §8.5, overkill margin, Attack, Hull clock, subdue roll + Last Surge, comparative Speed; 5 hardcoded creatures: Mystic Eel, Mystic Electric Eel, Steel Tuna + sim rares **Anemoniacus** and **Freezing Perch** (flex slots, subdue 60, modal path); text fight UI | Text fight playable 20×; the §41 three questions answered **yes** by hand |
| **M3** | Auto-sim + replay + `--test-rules` | `--sim`, `--replay` (v2 stream), `--test-rules`, console mode (*nix analogue first); sim policy §25.9 incl. subdue roll | **Sim gate:** avg rare-fight actions ≤12 · ascent rate ≤15% · bar-switch observed · decline costs no RNG · commons never prompt. Tuning levers (each = spec amendment, recorded in §38): rare chance 60→65 first; surge restore 30%→25% second. Do not tune coupling to compensate |
| **M4** | Calendar + expedition loop | Phases, travel ladder, per-zone respawn, rare pipeline, flee, Hull-0 emergency ascent, release/sell | Full dock→travel→fight→return loop playable in terminal; empty-pool safe Rest works |
| **M5** | Dock + economy | Refine/expertise 0–5, 5 boat axes + Heavy, tool crafting (7 tools), cosmetics (12), grudges | Economy arithmetic closes for the **full game** (§17 + §21.5); all dock actions 1 phase |
| **M6** | Data tables + loader | Text format, full schema, capacities §25.1; all T1 tables loaded from `data.z98`; malformed rejection | Loader goldens pass; bad sentinels (boss subdue_chance) rejected; Z4–Z8 empty-table stubs load |
| **M7** | Save system | CRC32, `data_version=2`, tmp+verify+rename+rollback, 2 slots, first-run lore page | Save round-trip golden passes; rollback path exercised; v1 save → v2 loader errors correctly |
| **M8** | Tier-1 content authoring | 17 creature rows + 2 flex, tools, journal 19 entries, manual pages, Legends 2, zone flavor, error copy — §40 checklist | **Demo content-complete in terminal**; full T1 loop playable start→boss gate |
| **M9** | Pixel tier | G6–G8 (`std_gfx_px`), 8×16 font atlas, bars + dotted red zone, dirty rects, surface-lost recovery | Fight renders in art mode; terminal + z9edit goldens byte-identical |
| **M10** | Asset pipeline + art | Palette lock, transitory SVG→`.ZSP` conversion (uncommitted, P19), committed Z98 `--validate-assets`, 11 bases + 6 recolors + 5 boss ramps, 5 demo backgrounds, boat, 9 overlays | Demo asset budget met (≤1.35 MB indexed, backgrounds ≤120 KB each); all 11 bases reviewed side-by-side as one set |
| **M11** | Boss + score screen — **DEMO GATE** | The Derelict §15 (3 phases), 5 Phase-2 adaptive variants, credits, 3-panel score screen, cosmetics render on boat | Full boss loop completable; all 5 variants triggerable from a save; Field Record written once; demo shippable |
| **M12** | Audio + options | Ambient + 4 cues (§31), options (volume, keys, save slot, colour-blind), pause-on-focus + audio Stop | Alt-tab pauses and silences; options persist; audio plays with no callback thread |
| **M13** | T2–T4 content | 30–36 creature rows (exact count fixed by the Task-0 ledger; §21 taxonomy, rares unique per band), Z4–Z8 encounter tables, named keystones, journal/manual additions, economy re-derive | Full roster loads; per-tier sims pass (≤12/12/14/15 action gates); **boss-feasibility sim: ≥50% at Hull 150+Plate, ≥90% at max Hull**; material sources complete |
| **M14** | T2–T4 assets | Recolors for new families, 5 new zone backgrounds, any new overlays | Full-game asset budget met (on-demand bg loading verified); style set holds |
| **M15** | Full-game balance pass | Playtime target measured post-sim (S3), calendar pacing ("something always available"), full-run economy arithmetic, **boss-feasibility re-run** | §17-style arithmetic closes for a full run; sim of a full run shows no dead days, no unobtainable material |
| **M16** | Win98 validation + ship | Real hardware 64 MB, crash UX (3 files) incl. deliberate-trap-on-hardware item, manual HTML, CD layout (DX7 runtime prerequisite stated), imports = exact KERNEL32/USER32/GDI32 set, 256-colour desktop fallback item | Full loop completable on Win98SE / 64 MB; no crash dumps in operator session; CD ready |

**Ordering:** M2–M3 are the design proof — nothing downstream starts until the sim gate passes. M4–M8 are terminal-mode only. M9–M10 build art. M11 is the demo. M12 may overlap M13. M15 needs M13+M14. M16 last.

**Regression rule:** every milestone's gates keep passing in CI for all later milestones (z9edit goldens, replay goldens, save round-trip, sim thresholds).

---

## 37. Risk Register

| Risk | Severity | Mitigation |
| :--- | :--- | :--- |
| Two bars don't couple | Fatal | gating forces the switch; verified by sim at the M3 gate |
| Pixel-tier vtable slot error | High | slots from `ddraw.h`, unused preserved; minimal blit test first |
| Surface lost on alt-tab | High | `Restore()` + re-lock exercised deliberately in M9 |
| 8bpp windowed palette arbitration | High | **avoided by design** — 16bpp backbuffer |
| Content authoring overruns | High | variants not uniques; 11 bases, not 48 sprites; T2–T4 is rows in a table |
| Tagged-union payload store reject | Medium | flat state structs (R1) |
| `-fsafe` overflow trap in combat math | Medium | i32 everywhere, xorshift RNG, CI runs `-fsafe` |
| AI art style drift | Medium | n/a — SVG-authored set; still review 11 bases side-by-side |
| Save corruption on FAT32 | Medium | tmp + verify + rename + **rollback**, two slots, `.bak`, non-fatal load |
| CD install cannot write | Medium | writability probe + temp fallback |
| Busy-spin CPU on Win98 | Medium | `gfxWaitEvent` |
| Subdue roll lengthens rare fights | Medium | measured at the M3 gate; two tuning levers defined |
| Ambient loop gap | Medium | offline crossfade; hardware check in M12 |
| Calendar feels like a chore | Moderate | something always available; empty pool = safe Rest |
| Speed dominant | Moderate | comparative order + creature Speed; accept min-max breakage |
| Full-game map rework late | Moderate | zone ladder + full capacities from M1; M13 is data-only |
| Backgrounds blow the budget | Moderate | 8-colour banded authoring, 120 KB cap, on-demand loading |

---

# PART III — LOGS

## 38. Decision Log (all locked)

### Project-level (this design phase)

| # | Decision |
| :-- | :--- |
| P1 | Scope = **full 4-tier game**; demo gate at M11 is a checkpoint, not the deliverable |
| P2 | Exactly **one boss battle** (The Derelict) at end of Tier 4; its 5 adaptive Phase-2 variants are the multi-boss experience; no tier bosses |
| P3 | Map = one home dock + **travel-cost ladder**: 8 wider zones (Z1–Z8), tier band ≈ travel cost 1→5, boss route cost 5 at far reach |
| P4 | Approach A: spec-spine expansion into 16 self-contained milestones; full-size capacities/schemas from M1 |
| P5 | All 16 milestone plans written up front |
| P6 | Spec is fully self-contained; embeds all tables |
| P7 | Spec in `docs/superpowers/specs/`, plans in `docs/superpowers/plans/`, source in `examples/z98/undersanded/` |
| P8 | T2–T4 creature rows authored at M13; spec carries T1 tables + scaling rules (§21) |
| P9 | Expertise 2/4 **gate boat upgrade purchases** (T2 needs E2, T3 needs E4 in every material spent) |
| P10 | Grudge "run" = since last Derelict kill; boss kill clears the family-overkill mask |
| P11 | Axis tier values are **cumulative totals** (Hull 125/150/200, Speed 12/15/19); Cargo/Oxygen are current-tier values |
| P12 | `data.z98` read from exe dir; fallback dir is for mutable files only; journal entry at first fight end (any outcome); `?` shows embedded manual text; zone milestones = first arrival |
| P13 | **API generation lock: DirectX 7 only** — no DX8 anywhere; DX7 runtime prerequisite shipped/stated |
| P14 | Console mode = COMMAND.COM-era plain text, with a **native *nix build as the authoritative CI path**; test model: native gates, Wine evidence-only |
| P15 | Levers adjudication: subdue base 95/80/60/−1, surge restore 30%, respawn triples are **spec-fixed**; M3's two levers are pre-authorized spec amendments when pulled; M15 tunes only in-band values (encounter weights, sale prices within §21.3 bands) |
| P16 | Rares unique per tier band (invented species names, e.g. Anemoniacus / Freezing Perch); flex slots filled by the two sim rares |
| P17 | Win9x save write path: delete stale `.bak` before rename (MoveFileA no-overwrite) + startup recovery |
| P18 | RNG determinism contract (§25.5 draw table, zero-seed guard, warm-up); art goldens = pre-present framebuffer dumps |
| P19 | **No committed tooling outside Z98 + shell.** Python = transitory, uncommitted (asset translation, golden-seed generation), never a build/test dependency. `.ZSP` + SVG sources + Z98 validator are the artifacts of record. |
| P20 | Fight length gates ≤12/12/14/15 (T1–T4); damage ranges never creep; **boss feasibility is a gate** (minimalist T4-proper loadout, kill-rate targets §21.3) |

### Game design

| ID | Decision |
| :--- | :--- |
| A1 | Attack stat on every creature; commons 6–9, rares 9–12 |
| A2 | Player base Speed 10 |
| A3 | Hull 0 = Emergency Ascent; Hull persists everywhere; dock Rest +40; no free heal |
| A4 | Overkill = overshoot ≥ margin (10% base); red zone is a warning only |
| A5 | Subdue legal whenever HP > 0 *(now also requires the chance roll — D7)* |
| A6 | Coupling gated on the other bar being high; universal baseline with overrides |
| B1 | Kill incentive = speed/safety only; no exclusive drops |
| B2 | Grudges Named-only, overkill-only |
| B3 | Tunisteel grudge = flat armor 50%→30% |
| B4 | Mileel → Hooked Barbel; Tunisteel → Steel Fins ×2 |
| C1 | Activated tools 1 charge/expedition; rigged tools passive; owned forever |
| C2 | Mileel flees on a single hit >30% max HP; HP tuned 90→80 so it is reachable |
| C3 | Brine Net ignores Shell/Phasing; Coral Shield negates discharge |
| C4 | Lure prevents blind/decoy; Sonar shows Ghost-Ray flip; Plate halves volley |
| C5 | Precision T2+ tools break on a single hit ≥15 Hull |
| D1 | Lore = manual page 1, shown on fresh install |
| D2 | Player is a scavenger; no name, no face |
| D3 | Journal = personal diary, first-person, past tense |
| D4 | Named creatures rumored, not clued; Legends page, 2 entries per tier band |
| D5 | Derelict is a mystery — "a signal, not a machine"; journal after first kill |
| D6 | Field Record written on first boss kill only |
| D7 | Subdue Chance + Last Surge |
| D8 | Esc menu: Journal / Map / Save / Quit; options at start menu |
| D9 | Manual save; prompt on quit; blocked mid-fight only (travel instantaneous, no persistent in-transit state); no autosave |
| D10 | **Commons auto-roll silently; modal for rare/named only** |
| D11 | **Dialog = Attempt / Fight on / Cancel; F and Esc identical, both set the flag** |
| D12 | **Field Record frozen + Variants Seen + Last Run** |

### Boss

| ID | Decision |
| :--- | :--- |
| BD1 | Adaptive Phase 2, 5 variants (Armor/Sliver/Hoard/Drown/Blur) |
| BD2 | No tier boss; the Derelict self-teaches; boss at end of Tier 4 |
| BD3 | Volley replaces standard attack; overkill → 40 cycles; Restrain disabled + journal line |
| BD4 | Gate = 6 distinct non-boss seen; Hull 150+ telegraphed on the node |

### Calendar and economy

| ID | Decision |
| :--- | :--- |
| E1 | Node Rest +30 with rough-sleep condition; empty pool = safe Rest |
| E2 | Flee = +1 phase **and** normal return travel |
| E3 | Creature flee keeps nothing, counts as seen, normal respawn |
| E4 | Per-zone per-species instances; renormalize; empty pool safe |
| E5 | Renewal from Day of cycle N |
| F1 | Wariness +15 Resolve, next rematch only, no stack |
| F2 | +8 pp/release, cap +40 pp, reset on rare, node-scoped, additive + renormalize |
| F3 | Node lockout 5 cycles + global echo −5 pp per locked node |
| G1 | Distinct part names; tools cost parts; upgrades cost materials |
| G2 | Refine converts all parts of one type per action |
| G3 | Cargo adds to the drop total |
| G4 | Deep materials lose 1/part below E5 |
| G5 | Soft max-all-five; only Heavy is a hard tradeoff |
| G6 | Pace is sacred; drops and costs re-derived to hold it |
| H1 | Roster T1 = 8 common / 2 named / 6 rare / 1 boss (+2 flex: Anemoniacus, Freezing Perch) |
| H2 | Ink never randomizes into Flee |
| H3 | Threshold damage is one-shot on crossing |
| H4 | Speed hidden until a journal entry exists |
| H5 | 0 coins start; cosmetics grayed, 3 unlocked per zone milestone |
| H6 | Sale range 10–70 (T1); rising with tier (§21.3) |
| H7 | Full roster ≈ 49–55; T1 locked at 17 authored (+2 flex) |

### Scope and technical

| ID | Decision |
| :--- | :--- |
| S1 | Boss gate = 6 distinct **non-boss** creatures seen |
| S2 | 2 flex slots reserved at content level |
| S3 | Playtime target **TBD**, measured post-M13 from sim data (M15) |
| S4 | Journal updates silently; "New entry" indicator; no popups |
| S5 | Ambient loop + 4 one-shot cues |
| S6 | Three presentation modes: art / terminal TUI / console |
| T1 | DirectSound, no callback, no thread; `DSBCAPS_GLOBALFOCUS`; looping ambient |
| T2 | Pause on focus loss; no auto-resume; audio Stop |
| T3 | `data_version` in save; refuse migration |
| T4 | CRC32 over the data section |
| T5 | `--test-rules`; exit 0/1, print count |
| T6 | Data directory = exe directory, **with writability probe + temp fallback** |
| T7 | Minimal full-screen text error screen |
| T8 | Colour-blind: dotted red-zone border + inline numerics |
| T9 | Frame-independent tweens via **raw-tick accumulator** |
| T10 | Sibling module `std_gfx_px`; cell contract untouched |
| T11 | Event-driven timing only |
| T12 | Assets authored as SVG at target size; offline pipeline → `.ZSP` |
| T13 | Backgrounds on-demand loaded (1 resident) |

---

## 39. Still TBD

| Item | When |
| :--- | :--- |
| Playtime target (S3) | measured at M15 from sim data |
| Score screen visual layout | M11 |
| Options menu exact list | M12 |
| Boss Phase-2 flavor lines (5) | M11 |
| Cosmetic descriptions (12) | M11 |
| T2–T4 creature rows, names, tables | M13 (authoring, rules locked in §21) |
| Legends entries T2–T4 | M13 |

**No design questions remain open.** Everything above is authoring or measurement.

---

## 40. Authoring Checklist

| Item | Count | Milestone |
| :--- | :--- | :--- |
| Manual page 1 — The Drowned World | 2 paragraphs | M7 |
| Manual pages 2–8 | ~1 page each | M8 |
| Legends page T1 | 2 entries | M8 |
| Journal entries T1 | 18 non-boss + 1 boss = 19 | M8 / M11 |
| Error screen copy | 6 messages | M7 |
| Zone flavor text | 1 paragraph per zone (4 at demo, 9 full) | M8 / M13 |
| Cosmetic descriptions | 12 lines | M11 |
| Boss Phase-2 flavor lines | 5 lines | M11 |
| Last Surge flavor line | 1 line | M2 |
| Field Record title + closing line | 2 lines | M11 |
| Journal/legends T2–T4 | 30–36 entries + named legends | M13 |

---

## 41. What To Build First

The text-mode fight (M2). One creature, four actions, two bars, comparative Speed, the coupling rule, the overkill margin, the Attack stat, the Hull clock, the subdue roll.

Play it twenty times. Ask three questions:

1. Does the creature's behavior make me **switch which bar I push**, mid-fight?
2. Does the equipment slot change **how** I fight, or is it just a damage bonus?
3. Does Speed feel like a **trade-off**, or a dominant stat?

Then M3 proves it in data: yes to all three across the sim gate → the design is proven and the rest of the game is authoring and integration.

**The fight is the game.**

