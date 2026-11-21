# undersanded M10 — asset pipeline + art — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The palette-locked `.ZSP` asset set with a **committed Z98 validator** and **transitory (uncommitted) SVG→`.ZSP` conversion**, plus the demo art: 11 creature A sprites (10 non-boss + `boss00` re-authored at 96×96), 6 non-flex recolors, 2 flex recolors, 4 boss V rows (Armor = base), 5 backgrounds, boat, 9 cosmetic overlays — budget met and style reviewed as one set. Boat render/score stay M11.

**Architecture:** The **artifacts of record** are the SVG sources, the `.ZSP` files, and `assets.man`. Conversion SVG→`.ZSP` (rasterize 1:1 → alpha→key → 1px outline → ramp assert → canonical RLE encode) is a **transitory ad-hoc script that is never committed** (spec §30 P19). Every invariant is re-checked by the committed Z98 tool `undtool --validate-assets`: header/format, palette conformity, dims, ramp/key conformity, transparent creature border, canonical RLE byte-exactness, 8.3 names, manifest/variant coverage, budget, decoder golden. Runtime side: `zsp.zig` decoder + recolor LUT builder; `assets.zig` owns the arena loader and one resident background; `render_art` receives decoded `Sprite`s and does no file I/O.

**Tech Stack:** Z98 (validator, decoder, loader); shell (tiers); transitory host rasterization at authoring time only (uncommitted, provenance in NOTES.md). `.ZSP` format per §30 (16B header + 512B palette + RLE runs; canonical RLE rule — one run per maximal stretch, count 1–255, greedy 255 split).

**Spec:** `docs/superpowers/specs/2026-11-12-undersanded-design.md` §30 (palette anchors, stages, `.ZSP`, font, boat/cosmetic anchors, background rules, manifest + 8.3 names, budget, **asset conversion policy P19**), §35 (asset budget: demo ≤1.35 MB indexed, bg ≤120 KB encoded each), §36 (M10 row), §38 M10 preflight rulings.

**Sequence:** PREVIOUS: `2026-11-12-undersanded-m09-pixel-tier-plan.md`. NEXT: `2026-11-12-undersanded-m11-boss-score-plan.md`.

## Global Constraints

**Test model (spec §26, binding):** tiers run natively — `undtool.nix` (COMMAND.COM-analogue console) + native test drivers are the FAST gate; Wine/DD7/DSound probes are SLOW evidence only, never the gate; operator hardware is M16-only. Logic goldens must be runnable in CI without Wine.

**Palette contract (binding, M10 ruling):** each ramp has its four anchors at shade indices **0, 5, 10, 15** (Dark/Mid/Light/Hi). Shades between anchors are linear interpolated in 8-bit RGB with integer round-to-nearest: for a segment with anchors `c0` at `a0` and `c1` at `a1`, `c(i) = (c0*(a1-i) + c1*(i-a0) + (a1-a0)/2) / (a1-a0)`. RGB565 conversion uses round-to-nearest: `r5=(r*31+127)/255`, `g6=(g*63+127)/255`, `b5=(b*31+127)/255`. Index **255 is the transparent key**, not ramp-15 shade-15; ramp 15 therefore has 15 usable shades, and recolor `to_ramp==15 && shade==15` uses `base[254]`. `out[255] = base[255]` always.

**Boss contract (binding, M10 ruling):** `boss00` is re-authored at **96×96** and its header ramp is **10** (Armor). `id=17` maps directly to `A boss00` with no `V` row. Four boss `V` rows use `base8.3=boss00`, `from_ramp=10`: `boss00:sliver 10->2`, `boss00:hoard 10->4`, `boss00:drown 10->13`, `boss00:blur 10->5`. No identity boss V row.

**Asset ledger (binding):** `A` rows are exactly 26 files: `eel00 tuna00 crab00 jelly00 barn00 anem00 ray00 squid00 angler00 wrasse00 boss00 bg_a bg_b bg_c bg_d bg_dock boat00 fig_merm fig_angl fig_krak flag_pen flag_ref flag_trn dec_barn dec_sqid dec_boss`; plus `F font8x16 95 16`. `V` rows are exactly 12: non-flex `id2 eel00 6->1`, `id3 eel00 6->5`, `id5 tuna00 7->14`, `id6 tuna00 7->10`, `id11 crab00 8->11`, `id12 jelly00 9->5`; flex `id18 anem00 11->5`, `id19 tuna00 7->1`; boss `boss00:sliver 10->2`, `boss00:hoard 10->4`, `boss00:drown 10->13`, `boss00:blur 10->5`. Base defs are identity rows with no `V`: `id1->eel00`, `id4->tuna00`, `id7->crab00`, `id8->jelly00`, `id9->barn00`, `id10->anem00`, `id13->ray00`, `id14->squid00`, `id15->angler00`, `id16->wrasse00`, `id17->boss00`.

**Manifest grammar (binding):** `A <name8.3> <kind> <w> <h> <encoded_bytes> <allowed_ramps_csv>`; `V <variant_id> <base8.3> <from_ramp> <to_ramp>`; `F font8x16 95 16`. `A.name8.3`/`V.base8.3`/`F` are lowercase 8.3 (≤8-char base, ≤3-char extension, no spaces). `A` is the only source of indexed bytes; `V` adds only a 512-byte LUT. The validator must require every `V.base8.3` to be an `A` row, `from_ramp` to equal that row's `.ZSP` header ramp, every demo def exactly one mapping (identity A or one V), and no orphan/duplicate variants.

**No committed tooling outside Z98 + shell (P19)** — no `.py`/`.sh` converter in the repo; the conversion script is transitory, and CI's only asset gate is `undtool --validate-assets`. Palette anchors are **locked** (spec §30 table; shades per the palette contract above). Filenames 8.3 lowercase exactly as the ledger. SVG discipline: no gradients/opacity/filters/text; `shape-rendering="crispEdges"`; 1:1 rasterize only. Font is **not generated** (period 8×16 VGA ROM; `font8x16.zig` already exists from M9 — verify provenance, do not re-import). Validation failures fail the build.

**Budgets (binding):** indexed bytes = sum of `w*h` over distinct `A` `.ZSP` rows (recolors/boss V rows never multiply base pixels); indexed ≤1.35 MB; indexed + LUTs (512 × A + 512 × V) ≤2 MB sprite arena; each background encoded ≤120 KB; demo RLE disk ≤400 KB (not “≈300 KB”).

## File Structure

- `examples/z98/undersanded/palette.zig` — locked 16×16 RGB565 table (anchors 0/5/10/15, interpolation/rounding above, index 255 key).
- `examples/z98/undersanded/zsp.zig` — runtime decoder + `zspRecolorLut` + `zspCanonicalEncode`.
- `examples/z98/undersanded/validate_assets.zig` — committed Z98 validator (header/format, palette conformity, dims, ramp-set + key conformity, creature transparent border, canonical RLE byte-compare, 8.3 names, exact A/V/F ledger, per-asset + cumulative budget).
- `examples/z98/undersanded/assets.zig` — arena loader: reads `assets.man`, decodes A/V `.ZSP`s, owns one resident background, exposes `Sprite`/LUT handles; no I/O in `render_art`.
- `examples/z98/undersanded/assets/*.svg` — authored/transcribed set (11 bases incl. re-authored `boss00` 96×96, boat, 9 overlays, 5 bg).
- `examples/z98/undersanded/assets/out/*.zsp` — committed artifacts of record.
- `examples/z98/undersanded/assets/assets.man` — committed A/V/F manifest.
- `examples/z98/undersanded/undtool.zig` — add `--validate-assets <manifest> [assets_dir]` (exit 0 valid, 2 usage/invalid); no content install.
- `examples/z98/undersanded/render_art.zig` — consume loaded sprites/background; no file I/O; art golden re-pin only here.
- `examples/z98/undersanded/loop_gfx.zig` — load assets at startup and pass them into `render_art`.
- `examples/z98/undersanded/NOTES.md` — regeneration recipe, palette/boss rulings, style sign-off.
- `examples/z98/undersanded/tests/tier_m10_assets.sh` — pure Z98/shell tier (no Python).
- Transitory, **not committed**: the author's ad-hoc conversion script used to produce `assets/out/*.zsp`.

## Review Focus

- Style drift across bases (the #1 content risk): the 11 bases must pass a side-by-side review as one set; reject and regenerate offenders — sign-off recorded in NOTES.md.
- RLE budget blowouts from noisy backgrounds: enforce 8 unique colours + banded depth; hard-fail >120 KB encoded; remeasure cumulative demo budget (≤1.35 MB indexed, RLE ≤400 KB).
- Ramp-snap violations slipping through (validator must fail an off-ramp pixel) and palette drift (embedded palette must equal `palette.zig`).
- Canonical RLE: validator re-encodes decoded pixels and byte-compares the data section; non-canonical runs fail.
- Decoder/encoder endianness/header mismatch (w/h u16 LE, key/ramp u8, flags u16, reserved u32) → golden `.ZSP` decoded to known pixels; flags/reserved must be zero.
- Boss regressions: 96×96, ramp 10, no Armor V row; 4 boss V rows.
- Backgrounds: exactly one resident at a time; zone background drawn in the art fight; switching zones swaps it.
- Art golden: exactly one intentional re-pin in Task 4; terminal/M8/M9 `--dump-grid` goldens byte-identical.
- **Compliance creep:** nobody re-introduces a committed converter — grep the tier/repo for `.py` at review time (P19).

---

### Task 0: Preflight

- [ ] Record the M10 rulings in NOTES.md: palette contract, boss 96×96/ramp 10/no Armor V, exact A/V/F ledger, boat render deferred to M11, backgrounds wired in M10, budget numbers, art-golden re-pin. Derive each asset's `allowed_ramps_csv` from the committed SVG fills and record the expected A table used by the validator. Verify the landed `font8x16.zig` (95 glyphs, 8×16, VGA8.F16 provenance/URL/sha) and record it; do not re-import. Create `assets/` + `assets/out/` skeletons. State P19 and the regeneration recipe stub. Commit `example(undersanded): M10 preflight`.

### Task 1: Palette + `.ZSP` decoder (`palette.zig`, `zsp.zig`)

**Interfaces:** `palette.zig`: `pub const RGB565: [256]u16` built from the locked anchors; index 255 key. `zsp.zig`: `pub fn zspDecode(buf: []const u8, out_sprite: *Sprite, out_lut: *[256]u16, pix: []u8, pix_len: *i32) bool` (magic `ZSP1`, w/h u16 LE, key/ramp, flags/reserved zero, runs bounds; success sets `sprite.w/h/idx/lut/key`, `pix_len=w*h`, all 256 LUT entries from the 512-byte palette; failure writes nothing outside `pix`); `pub fn zspRecolorLut(out: *[256]u16, base: *const [256]u16, from_ramp: u8, to_ramp: u8) void` (exact rule above); `pub fn zspCanonicalEncode(pix: []const u8, w: u32, h: u32, out: []u8) usize` (one run per maximal stretch; >255 greedy 255 + remainder 1..255; returns 0 on overflow).
- [ ] Tests: palette anchors and intermediate shades exact (0/5/10/15, rounding), 255 key, ramp15 shade15 fallback; decode golden pixels/LUT; truncated/garbage/oversize false; recolor LUT exact incl. ramp15 and `from==to`/ramp0 rejection; canonical encode round-trip and non-canonical rejection. PASS. Commit `example(undersanded): palette + ZSP decoder`.

### Task 2: Validator + manifest + `--validate-assets`

**Interfaces:** `validate_assets.zig`: `pub fn validateAsset(buf: []const u8, expect: AssetSpec) ValidateErr` and `pub fn validateManifest(man: []const u8, assets_dir: []const u8) ValidateErr`. `AssetSpec` carries name/kind/w/h/allowed_ramps from the **hardcoded expected A table** (not trusted from the manifest). Validate embedded palette equals `palette.RGB565`; every pixel index within allowed ramps∪key; creature border key; canonical RLE byte-compare; exact A/V/F ledger and def mapping; budget. `undtool.zig` adds `--validate-assets <manifest> [assets_dir]`, exit 0/2, no content install; `undtool_native.zig` already forwards.
- [ ] Tests: accepts the known-good `.ZSP`; rejects bad magic, truncated run, oversized dims, off-ramp pixel, bad palette, non-canonical RLE, bad 8.3 name, missing manifest entry, orphan/duplicate V, wrong `from_ramp`, budget overrun. Produce one test `.ZSP` with the transitory script outside the repo. PASS. Commit `example(undersanded): Z98 asset validator + manifest`.

### Task 3: Author/transcribe the SVG set + convert + commit `.ZSP`

- [ ] Transcribe the available SVG sources into `assets/`; **re-author `boss00.svg` at 96×96 in ramp 10** (do not copy the 160×160 ramp-14 source). Author/verify per §30: 11 creature A files (10 non-boss + boss), 6 non-flex recolors + 2 flex recolors as V rows, 5 backgrounds 640×300 (banded, ≤8 colours; `bg_d` boss route; `bg_dock`), `boat00` 200×150 (hull paint = ramp swap region; porthole circles → polygons), 9 overlays 64×64 at anchors (24,40)/(150,18)/(96,96). No boat render wiring. Convert with the transitory script; run `undtool --validate-assets`; commit the SVGs + `.ZSP` outputs + manifest. **Side-by-side review of the 11 bases as one set** — regenerate any that break it (record sign-off in NOTES.md). Commit `example(undersanded): demo art set (SVG sources + ZSP + manifest)`.

### Task 4: Wire art fight to sprites + backgrounds + budget

- [ ] Add `assets.zig` arena loader (`assets.man` + `.ZSP` decode/recolor LUTs; one resident background; no file I/O in `render_art`). Wire creature sprites (base/recolor LUT per def), the current zone background, and one resident background into the art fight. Keep `render_art` pure; pass decoded `Sprite`s/background in. **Do not wire boat/score here — M11 owns boat render, overlays, and score.** Re-pin `art_fight.golden` exactly once in this commit and update the M9 tier comment to say M10 re-pinned it. Validator/gate: indexed ≤1.35 MB, each bg ≤120 KB encoded, demo RLE disk ≤400 KB, indexed+LUT ≤2 MB. Terminal/M8/M9 `--dump-grid` goldens byte-identical. Commit `example(undersanded): sprites + backgrounds wired`.

### Task 5: `tier_m10_assets.sh`

- [ ] Tier (pure Z98/shell — **assert no Python invocation**): palette/decoder/validator tests + full-manifest validation green + budget assertions + golden decode of 3 sprites + art golden matches the Task 4 re-pin + z9edit/terminal goldens unchanged + `grep -r` compliance check for committed converter files. Non-vacuous. Run PASS. Commit `example(undersanded): M10 assets tier`.

**Gate:** demo asset budget met; Z98 validation green; 11-base style set signed off; no committed non-Z98 tooling; art fight shows real sprites + background; boat/score remain M11.

### Task 6: Next-milestone amendment review (M11)

- [ ] Read `2026-11-12-undersanded-m11-boss-score-plan.md`; confirm the 96×96 ramp-10 `boss00` + 4 V rows, `A`/`V` manifest outputs, boat asset availability, and boat render/score ownership. Amendment or "no amendment needed" in NOTES.md. Commit `example(undersanded): M11 amendment review`.
