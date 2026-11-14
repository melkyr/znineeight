# undersanded M10 — asset pipeline + art — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The palette-locked `.ZSP` asset set with a **committed Z98 validator** and **transitory (uncommitted) SVG→`.ZSP` conversion**, plus the demo art: 11 creature bases + 6 recolors + 5 boss ramps, 5 backgrounds, boat, 9 cosmetic overlays — budget met and style reviewed as one set.

**Architecture:** The **artifacts of record** are the SVG sources (human-readable), the `.ZSP` files, and `assets.man`. Conversion SVG→`.ZSP` (rasterize 1:1 → alpha→key → 1px outline → ramp assert → RLE encode) is a **transitory ad-hoc script that is never committed** (spec §30 P19) — the project must never require Python (or any non-Z98 tool) to build or test. Every invariant is re-checked in CI by the committed Z98 tool `undtool --validate-assets`: dims, ramp/key conformity, transparent border, 8.3 names, RLE bounds, budget, manifest coverage, decoder golden. Runtime side: the ~40-line Z98 `.ZSP` decoder producing `Sprite` + 565 LUT (M9 interface).

**Tech Stack:** Z98 (validator + decoder); shell (tiers); transitory host rasterization at authoring time only (uncommitted, provenance in NOTES.md). `.ZSP` format per §30 (16B header + 512B palette + RLE runs; canonical RLE rule — one run per maximal stretch, count 1–255).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §30 (palette anchors, stages, `.ZSP`, font, boat/cosmetic anchors, background rules, manifest + 8.3 names, budget, **asset conversion policy P19**), §35 (asset budget: demo ≤1.35 MB indexed, bg ≤120 KB encoded each), §36 (M10 row).

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m09-pixel-tier-plan.md`. NEXT: `2026-11-12-undersanded-m11-boss-score-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

As prior. **No committed tooling outside Z98 + shell (P19)** — no `.py`/`.sh` converter in the repo; the conversion script is transitory, and CI's only asset gate is `undtool --validate-assets`. Palette anchors are **locked** (spec §30 table — the 16 ramps × 4 anchor hexes; shades interpolated; index 255 = transparent key). Filenames 8.3 lowercase (manifest names exactly spec §30: `eel00 tuna00 crab00 jelly00 barn00 anem00 ray00 squid00 angler00 wrasse00 boss00 bg_a bg_b bg_c bg_d bg_dock boat00 fig_merm fig_angl fig_krak flag_pen flag_ref flag_trn dec_barn dec_sqid dec_boss font8x16`). SVG discipline: no gradients/opacity/filters/text; `shape-rendering="crispEdges"`; 1:1 rasterize only. Font is **not generated** (period 8×16 VGA ROM). Validation failures fail the build.

## File Structure

- `examples/z98/undersanded/validate_assets.zig` — committed Z98 validator (called by `undtool --validate-assets`): header/format, dims, ramp-set + key conformity, creature transparent border, canonical RLE bounds, 8.3 name, manifest presence, per-asset + cumulative budget, decode golden compare.
- `examples/z98/undersanded/assets/*.svg` — the authored set (11 bases + boat + 9 overlays + 5 bg) — committed sources.
- `examples/z98/undersanded/assets/out/*.zsp` — **committed artifacts of record** (what ships).
- `examples/z98/undersanded/assets/assets.man` — committed manifest (8.3 name, kind, dims, encoded bytes, ramps).
- `examples/z98/undersanded/zsp.zig` — runtime decoder (header → palette → RLE → `Sprite`).
- `examples/z98/undersanded/NOTES.md` — regeneration recipe (one paragraph: tools used, canonical RLE rule) + style sign-off.
- `examples/z98/undersanded/tests/tier_m10_assets.sh` — pure Z98/shell tier (no Python).
- Transitory, **not committed**: the author's ad-hoc conversion script used to produce `assets/out/*.zsp`.

## Review Focus

- Style drift across bases (the #1 content risk): the 11 bases must pass a side-by-side review as one set; reject and regenerate offenders — sign-off recorded in NOTES.md.
- RLE budget blowouts from noisy backgrounds: enforce 8 unique colours + banded depth; hard-fail >120 KB encoded; remeasure cumulative demo budget (≤1.35 MB indexed).
- Ramp-snap violations slipping through (validator stage must actually fail) → negative fixture with an off-ramp pixel.
- RLE round-trip/byte-exactness drifting between regenerations: canonical encoder rule is documented in NOTES.md; goldens are the committed `.ZSP` decode outputs, so a bad regeneration is caught even without the script.
- Decoder/encoder endianness and header mismatch (w/h u16 LE, key/ramp u8, flags u16, reserved u32) → golden `.ZSP` fixture decoded to known pixels.
- **Compliance creep:** nobody re-introduces a committed converter — grep the tier/repo for `.py` at review time (P19).

---

### Task 0: Preflight

- [ ] Import the period 8×16 VGA ROM font (public domain) as `font8x16.zig`; record provenance in NOTES.md. Create `assets/` skeleton + `assets/out/`. State the P19 rule and the regeneration recipe stub in NOTES.md.

### Task 1: Palette data + Z98 validator + transitory converter

**Interfaces:** `validate_assets.zig`: `pub fn validateAsset(buf: []const u8, expect: AssetSpec) ValidateErr` (magic/format, dims, all pixels ∈ ramps∪{key}, border key for creatures, RLE counts 1–255 within bounds); `pub fn validateManifest(man: []const u8, files: []const u8) ValidateErr` (8.3 names, every asset present, budget sums). Palette = Z98 const table (`palette.zig`, 16×16 RGB565 from the §30 anchors, index 255 key) — shared by validator, decoder tests, and the renderer.
- [ ] Unit tests: palette RGB565 values exact vs spec anchors; validator rejects off-ramp pixel fixture, bad magic, truncated run, oversized dims, bad 8.3 name, missing manifest entry; accepts a known-good `.ZSP`. Write the transitory conversion script **outside the repo** (e.g. `/tmp`), produce one test `.ZSP`, delete/ignore the script. Commit `example(undersanded): Z98 asset validator + palette`.

### Task 2: `.ZSP` runtime decoder (`zsp.zig`)

**Interfaces:** `pub fn zspDecode(buf: []const u8, out_sprite: *Sprite, out_lut: *[256]u16, pix: []u8, pix_len: *i32) bool` (validates magic `ZSP1`, dims, runs bounds; **output contract**: RLE-expanded pixels land in the caller-provided `pix` buffer — arena-backed at load, overflow → false; LUT = full 256×u16 built from the embedded palette).
- [ ] Unit test: golden fixture decodes to expected indexed pixels + LUT values; truncated/garbage buffers → false. Implement. PASS. Commit `example(undersanded): ZSP decoder`.

### Task 3: Author the SVG set + convert (transitory) + commit `.ZSP`

- [ ] Author per §30: 11 creature bases 96×96 (eel00…boss00; 4 family bases take 6 recolors via ramp assignment; flex recolors anem00 (Anemoniacus) + icy tuna00 (Freezing Perch); boss00 takes 5 ramp assignments = The Armor/Sliver/Hoard/Drown/Blur recolors), 5 backgrounds 640×300 (banded, ≤8 colours; `bg_d` boss route; `bg_dock`), `boat00` 200×150 (hull paint = ramp swap region; porthole circles → polygons), 9 overlays 64×64 at anchors (24,40)/(150,18)/(96,96). Convert with the transitory script; run `undtool --validate-assets`; commit the SVGs + `.ZSP` outputs + manifest. **Side-by-side review of the 11 bases as one set** — regenerate any that break it (record sign-off in NOTES.md). Commit `example(undersanded): demo art set (SVG sources + ZSP + manifest)`.

### Task 4: Wire art screen to real sprites + budget

- [ ] Swap M9 fill-rect stand-ins for sprite blits (creature, boat on dock/score screens per §30 blit order base→paint→decal→figurehead→flag — full cosmetics render lands M11; base order now; 19 sprites including the 2 flex recolors anem00 (Anemoniacus) + icy tuna00 (Freezing Perch)). Validator checks: demo indexed ≤1.35 MB total, each bg ≤120 KB encoded, cumulative RLE disk ≈300 KB. Commit `example(undersanded): sprites wired + budget check`.

### Task 5: `tier_m10_assets.sh`

- [ ] Tier (pure Z98/shell — **assert no Python invocation**): validator tests + full-manifest validation green + budget assertions + golden decode of 3 sprites + z9edit/terminal goldens unchanged + `grep -r` compliance check for committed converter files. Non-vacuous. Run PASS. Commit `example(undersanded): M10 assets tier`.

**Gate:** demo asset budget met; Z98 validation green; 11-base style set signed off; no committed non-Z98 tooling.

### Task 6: Next-milestone amendment review (M11)

- [ ] Read `2026-11-12-undersanded-m11-boss-score-plan.md`; judge boss sprite ramp set (5 recolors of `boss00`) + boat render needs vs the pipeline outputs. Amendment or "no amendment needed" in NOTES.md.
