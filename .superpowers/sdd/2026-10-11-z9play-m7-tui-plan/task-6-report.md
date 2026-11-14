# M7 Task 6 report — M8 amendment review (report-only)

**Status:** DONE — review complete; **amendment required before any M8 execution**.
**Verdict:** M8's decoder boundary is compatible with M7 at the `Decoder` vtable,
but M8's plan state and its "player core selects" wording are stale. Do not start
M8 unamended.

No source/plan/script edits were made. No M8 implementation, no battery, no push.

---

## 1. Boundary judgment

### Actual M7 boundary (binding)

M7's decoder abstraction is **not** a `union(enum)` selector inside the player
core. It is a concrete vtable struct:

- `examples/z98/z9play/player.zig:67-74` — `Decoder` struct:
  `ctx: *void`, `next_fn: fn (*void, []i16) DecoderError!usize`,
  `max_frames: u32`, `sample_rate: u32`, `channels: u8`,
  `total_frames: u64`.
- `examples/z98/z9play/player.zig:98` — `Player.decoder: *const Decoder`
  (held by pointer).
- `examples/z98/z9play/player.zig:208-233` — `playerDecodeStep` calls
  `p.decoder.next_fn(...)`; the Player core never selects a codec.
- `examples/z98/z9play/player.zig:13` — the source itself says "M8 can add a
  FLAC backend."

Selection is assembled by each frontend, not by `player.zig`:

- `examples/z98/z9play/main.zig:497-504` — `--wav` path assembles the Vorbis
  `player.Decoder` literal.
- `examples/z98/z9play/main.zig:753-760` — interactive CLI path assembles the
  same literal.
- `examples/z98/z9play/ui.zig:521-528` — TUI path assembles the same literal.

There is **no** `examples/z98/z9play/decoder.zig` in the delivered tree.

### Where M8's wording diverges

- `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:7` says selection is
  by signature/extension **"in the player core."** False for M7; the core is
  codec-agnostic and only consumes `*const Decoder`.
- `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:26,34` proposes a
  new `decoder.zig` with `DecoderKind = union(enum){ vorbis, flac }`. That is a
  valid **frontend-side selector/adapter**, but it must ultimately assemble the
  existing `player.Decoder` vtable; it must not be described as replacing or
  living in the player core.
- The M8 File Structure (`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:23-28`)
  omits the two files that must actually switch on format:
  `examples/z98/z9play/main.zig` and `examples/z98/z9play/ui.zig`. Task 1's
  "route the Vorbis path through it" (`...m8...:34`) cannot be done without
  changing both assembly sites.

### Compatibility conclusion

**Compatible abstraction shape; incompatible plan description/touch-set.** FLAC
can slot in by providing a FLAC `next_fn` plus the metadata fields and assembling
the same `Decoder` literal. No player-core change is needed. M8 must be amended
to put the `union(enum)`/selector in a frontend `decoder.zig` adapter and to add
`main.zig`/`ui.zig` to its touch set. The selector must also preserve the
existing pointer-vtable/caller-owned discipline (`player.zig:93-100`), i.e. do
not embed `player.Decoder` by value in a struct field or return such a struct by
value.

Current TUI evidence that `.flac` is accepted but not decodable:
`examples/z98/z9play/ui.zig:284-287` filters `.flac`; `ui.zig:488` still calls
`ogg.reassemble` unconditionally and `ui.zig:496-519` parses only Vorbis.

---

## 2. Plan-state staleness (must be amended even with a compatible boundary)

### Seed is stale

- M8 says base seed **v98**, fixed point
  `f18b69ece1917bf970a036b276e5e403`
  (`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:21`).
- Current seed is **v102**: archive md5
  `702f34d87b7e6bf401dd206d2517dbee`, archived binary/fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`
  (`docs/sf/QUICK_REF.md:27-31`; `release/seed/CHANGELOG.md:14,28`).
- M8's "no seed rotation" statement is still correct **if M8 proceeds on v102**
  and makes no `sf/**`/compiler change, because M7 already rotated v101 → v102.

### Defect status is stale

- M8 says "**D1–D8 are all FIXED**"
  (`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:21`).
- Current numbering: D1/D2 FIXED (`examples/torrent_example_defects.md:17,117`);
  D3 OPEN/DEFERRED (`:192`), D4 OPEN (`:208`), D5 OPEN (`:234`).
- The M7 binding amendment explicitly forbids "D1–D8 are all FIXED": see
  `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/task-6-brief.md:22-27` and
  `docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md:85-90`.

### Win9x hardware status is stale/incomplete

- M8's final handoff says "feature-complete ... Linux + Win9x"
  (`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:53`).
- Actual status is design-verified, hardware verification operator-pending:
  `examples/z98/z9play/NOTES.md:248-249` and
  `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/task-5-report.md:45-46`.
  M8's final note must not imply Win98/Me hardware verification.

---

## 3. STOP-present and required M8 amendment

I found the intention is M8 on seed v98 with "D1–D8 all FIXED" and decoder
selection inside the player core, but this is impossible given the delivered M7
tree (v102; D1/D2 FIXED, D3/D4/D5 OPEN; `Player` consumes a `*const Decoder`
vtable; selection is assembled in `main.zig`/`ui.zig`). M8 must not execute until
the operator approves the amendment below, or drops the optional M8.

### Required replacement text

**Replace `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:21`
(Global Constraints) with:**

> Same as prior milestones: example-only `examples/z98/z9play/**`; **no compiler
> change**; no seed rotation expected (M8 adds no `sf/**`/compiler surface); Z98
> rules (base seed is **v102** — archive md5
> `702f34d87b7e6bf401dd206d2517dbee`, fixed point
> `b299b4b435e624d0ddbd2edde681cbc3`, superseding v98/v97; current defect
> numbering is **D1/D2 FIXED**, **D3/D4/D5 OPEN** — see
> `examples/torrent_example_defects.md`; do not claim "D1–D8 are all FIXED"; if
> M8 ever needs an `sf/**`/compiler change, STOP-present before touching it and
> rotate the seed per `docs/sf/QUICK_REF.md`; this class of compiler defects can
> still surface in new shapes — if one is hit, STOP-present, apply a minimal
> example-only workaround, and record it in
> `examples/torrent_example_defects.md` for a later compiler pass); `-fsafe`;
> `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority
> (STOP-present). Reports under
> `.superpowers/sdd/2026-10-11-z9play-m8-flac-plan/`.

**Replace `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:7`
(Architecture) with:**

> **Architecture:** A `flac.zig` decoder implementing the same decode contract
> as the Vorbis path (`decodePacket`-style → interleaved s16 PCM). A new
> frontend-side `decoder.zig` selects Vorbis vs FLAC by signature/extension and
> assembles the existing `player.Decoder` vtable (`ctx`/`next_fn`/metadata); the
> `Player` core remains selection-agnostic. Reuses `std_math` (M2) for any
> needed fixed/float math and the same `Player`/ring/audio path (M4).

**Add to the File Structure
(`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:23-28`):**

> - `examples/z98/z9play/main.zig` — route the CLI `--wav`/interactive assembly
>   sites through `decoder.zig` (no player-core change).
> - `examples/z98/z9play/ui.zig` — route `playTrack` through `decoder.zig` (no
>   player-core change).

**Replace `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:34`
(Task 1) with:**

> - [ ] Introduce `decoder.zig` with a
>   `DecoderKind = union(enum){ vorbis: VorbisDecoder, flac: FlacDecoder }`-style
>   selector that assembles the existing `player.Decoder` vtable; route the
>   Vorbis path through it in `main.zig` and `ui.zig` with **no behaviour
>   change** (existing tiers stay green). Do not move selection into
>   `player.zig`; keep the vtable caller-owned/by-pointer. Commit
>   `example(z9play): decoder abstraction (vorbis via selector)`.

**Append to Task 5 (`docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:53`)
or its final status note:**

> Win9x behavior is design-verified; Win98/Me hardware verification remains
> operator-pending.

---

## 4. Recommendation

**(b) M8 state-truth-up + boundary-placement amendment required before
execution.** The decoder abstraction itself does **not** need a shape change:
FLAC fits the existing `Decoder` vtable. M8 must be amended for (i) the v102 seed
and current D1/D2/D3/D4/D5 status, (ii) frontend-side selector placement and the
`main.zig`/`ui.zig` touch-set, and (iii) the Win9x hardware caveat. Because M8 is
optional, the operator may instead choose **(c) drop M8**; there is no
missing-compiler-feature or boundary reason to drop it.

---

## 5. Evidence index

| Claim | Evidence |
|---|---|
| `Decoder` vtable contract | `examples/z98/z9play/player.zig:67-74` |
| Player holds vtable by pointer, never selects | `examples/z98/z9play/player.zig:93-100`, `:208-233` |
| CLI `--wav` assembles Vorbis literal | `examples/z98/z9play/main.zig:497-504` |
| CLI interactive assembles Vorbis literal | `examples/z98/z9play/main.zig:753-760` |
| TUI assembles Vorbis literal | `examples/z98/z9play/ui.zig:521-528` |
| TUI accepts `.flac` but still OGG-parses | `examples/z98/z9play/ui.zig:284-287`, `:488`, `:496-519` |
| No `decoder.zig` delivered | `ls examples/z98/z9play/` (no such file) |
| Spec says FLAC behind decoder vtable | `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md:65` |
| M8 says "player core" selects | `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:7` |
| M8 `decoder.zig`/union assumption | `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:26,34` |
| M8 stale v98/D1–D8 clause | `docs/superpowers/plans/2026-10-11-z9play-m8-flac-plan.md:21` |
| Current seed v102 + pins | `docs/sf/QUICK_REF.md:27-31`; `release/seed/CHANGELOG.md:14,28` |
| Current defect status | `examples/torrent_example_defects.md:17,117,192,208,234` |
| Win9x hardware operator-pending | `examples/z98/z9play/NOTES.md:248-249`; `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/task-5-report.md:45-46` |
| Binding M7 amendment | `docs/superpowers/plans/2026-10-11-z9play-m7-tui-plan.md:73-90`; `.superpowers/sdd/2026-10-11-z9play-m7-tui-plan/task-6-brief.md:9-27` |
