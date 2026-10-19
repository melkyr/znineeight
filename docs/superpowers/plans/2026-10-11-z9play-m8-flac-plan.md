# z9play M8 — FLAC decoder (optional) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal (optional, operator-gated):** Add a native FLAC decoder behind the player's decoder abstraction, so `z9play` can play `.flac` as well as `.ogg`.

**Architecture:** A `flac.zig` decoder implementing the same decode contract as the Vorbis path (`decodePacket`-style → interleaved s16 PCM). A new frontend-side `decoder.zig` selects Vorbis vs FLAC by signature/extension and assembles the existing `player.Decoder` vtable (`ctx`/`next_fn`/metadata); the `Player` core remains selection-agnostic. Reuses `std_math` (M2) for any needed fixed/float math and the same `Player`/ring/audio path (M4).

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_math`, `Player` (M4), `flac`/`flac`-tools (no-root) for goldens.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding; FLAC listed as optional M8).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m7-tui-plan.md`. NEXT: none (final).

## Scope gate (read first)

M8 is **optional**. The operator confirmed it on 2026-10-18 (M7 Task 6 Amendment 1 approval) and M8 begins on seed v102. If the operator later drops it, record "M8 dropped by operator" and stop.

## Global Constraints

Same as prior milestones: example-only `examples/z98/z9play/**`; **no compiler change**; no seed rotation expected (M8 adds no `sf/**`/compiler surface); Z98 rules (base seed is **v102** — archive md5 `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`, superseding v98/v97; current defect numbering is **D1/D2 FIXED**, **D3/D4/D5 OPEN** — see `examples/torrent_example_defects.md`; do not claim "D1–D8 are all FIXED"; if M8 ever needs an `sf/**`/compiler change, STOP-present before touching it and rotate the seed per `docs/sf/QUICK_REF.md`; this class of compiler defects can still surface in new shapes — if one is hit, STOP-present, apply a minimal example-only workaround, and record it in `examples/torrent_example_defects.md` for a later compiler pass); `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m8-flac-plan/`.

## File Structure

- `examples/z98/z9play/flac.zig` — FLAC stream + frame decode → PCM.
- `examples/z98/z9play/decoder.zig` — frontend-side selector/adapter (`union(enum)`/vtable) selecting Vorbis vs FLAC by signature and assembling `player.Decoder`.
- `examples/z98/z9play/main.zig` — route the CLI `--wav`/interactive assembly sites through `decoder.zig` (no player-core change).
- `examples/z98/z9play/ui.zig` — route `playTrack` through `decoder.zig` (no player-core change).
- `examples/z98/z9play/tests/get_flac_tools.sh` — no-root `flac` acquisition.
- `examples/z98/z9play/tests/tier_flac.sh`.

---

### Task 1: Decoder abstraction

- [ ] Introduce `decoder.zig` with a `DecoderKind = union(enum){ vorbis: VorbisDecoder, flac: FlacDecoder }`-style selector that assembles the existing `player.Decoder` vtable; route the Vorbis path through it in `main.zig` and `ui.zig` with **no behaviour change** (existing tiers stay green). Do not move selection into `player.zig`; keep the vtable caller-owned/by-pointer. Commit `example(z9play): decoder abstraction (vorbis via selector)`.

### Task 2: FLAC stream + frame decode

**Interfaces:** `flac.open(arena, bytes) !FlacDecoder` (parse `fLaC` + `STREAMINFO`); `flac.decode(arena, out: []i16) !usize` (frame header + subframes: constant/verbatim/fixed/LPC + Rice residual, channel decorrelation), yielding interleaved s16 like the Vorbis path.
- [ ] Unit test: decode `sine_stereo_44100.flac` (generated via `flac`) → matches the WAV golden within tolerance; determinism 3×. Implement. PASS. Commit `example(z9play): native FLAC decoder`.

### Task 3: `tier_flac.sh`

- [ ] Build `-fsafe`; decode each `.flac` fixture; compare to the `flac -d` golden (tolerance per M3) + determinism; assert mixed `.ogg`/`.flac` selection works. Run PASS. Commit `example(z9play): M8 FLAC tier`.

**Gate:** `tier_flac.sh` green; `.ogg` tiers unaffected.

### Task 4: Docs + commit

- [ ] Update `NOTES.md`/`README.md` (FLAC support, `--dump-c89` md5). Commit `docs(z9play): M8 FLAC`.

### Task 5: Final handoff

- [ ] Record that z9play is feature-complete per the spec (OGG Vorbis + optional FLAC; CLI + TUI; Linux + Win9x), list any deferred arms, and note the next example (per the repo's example roadmap). No further milestone. Win9x behavior is design-verified; Win98/Me hardware verification remains operator-pending — do not claim hardware verification.

**Gate:** a final status note; no open Critical/Important items.
