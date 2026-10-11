# Task 1 Report — z9play M1 setup header skeleton (`vorbis_setup.zig` + unit harness)

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m1-setup-codebooks-plan.md` (Task 1)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): parse Vorbis setup header skeleton` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/vorbis_setup.zig` — `Setup`/`Codebook` + `parseSetup`.
- `examples/z98/z9play/tests/setup_test.zig` — deterministic unit harness.

Scoped to Task 1 only: `\x05vorbis` signature, `codebook_count+1`, and per
codebook `sync 0x564342` / `dimensions` / `entries` / ordered+sparse flags /
code lengths; the lookup-type tail is consumed (not stored) so traversal
reaches the next codebook. No Huffman tables, floors, residues, mappings or
modes (Tasks 2–3).

## TDD sequence

1. **RED.** `tests/setup_test.zig` written first; `-fsafe` compile failed
   `error[3048]: could not resolve imported file '../vorbis_setup.zig'` —
   the expected not-implemented failure.
2. **GREEN.** `vorbis_setup.zig` implemented; `-fsafe` compile (0 diagnostic
   lines) + link + run →
   `setup_test: PASS fixtures=5 stereo_codebooks=38 mono_codebooks=35 cb0_dim=1 cb0_entries=64 ordered=ok lookup2=ok`.

## Interface (as specified)

- `pub const Codebook = struct { dimensions: u16, entries: u32, ordered: bool,
  sparse: bool, lengths: []u8 }` — `lengths` is one entry per codebook entry
  (raw 1-based code length; 0 = unused/sparse), arena-owned.
- `pub const Setup = struct { codebooks: []Codebook }`.
- `pub fn parseSetup(arena: *std.arena.Arena, packet: []const u8) ogg.OggError!Setup`.

Internal LSB-first `BitReader` (`brRead`/`brSkip`), `ilog`, `lookup1Values`.
No `switch`; free functions only.

## Independent derivation of expected values

Fixtures carry no dumpable codebook metadata (`ogginfo -v` prints stream info
but **not** codebooks), so the values were derived with a small `python3`
bit-reader over packet index 2 of each fixture (`/tmp/parse_setup2.py`),
implementing Vorbis spec §3.2.1 codebook decode (LSB-first bits) and skipping
each lookup tail per spec. The reader verified every one of the 38/35 `BCV`
sync patterns, so the counts are full-list, not a prefix:

| fixture | codebooks | cb0 dims | cb0 entries |
|:--|--:|--:|--:|
| `sine_stereo_44100.ogg` | 38 | 1 | 64 |
| `sine_mono_44100.ogg` | 35 | 1 | 64 |
| `sine_stereo_48000.ogg` | 38 | 1 | 64 |
| `tagged_unicode.ogg` | 38 | 1 | 64 |
| `short.ogg` | 35 | 1 | 64 |

`ogginfo` was built from the extracted `vorbis-tools` prefix
(`tests/get_vorbis_tools.sh`); it confirms the stream but not the codebooks.

## Test coverage (`tests/setup_test.zig`)

- All five committed fixtures: `codebooks.len` and cb0 `dimensions`/`entries`.
- Synthetic **ordered** codebook (no fixture has one): count 1, dims 4,
  entries 3, `ordered==true`, `lengths==[2,2,3]`. Bytes emitted by an
  independent python bit-writer and embedded verbatim.
- Synthetic **lookup type 2** followed by a second codebook: asserts cb0
  dims/entries and cb1 dims 7 / entries 5 — i.e. the lookup-2 skip lands cb1's
  `BCV` on the correct bit.
- Negatives: wrong packet type, 7-byte (no count) packet, bad codebook sync
  all return `OggError` (no crash).

Because `parseSetup` re-checks `0x564342` at each codebook boundary, the
fixture PASS proves every lookup-1 skip across all 38/35 codebooks is exact.

## Verification

- Seed already built at `/tmp/z9play_seed` (v97, `bafbba9454cd2b134bdc3d50c65384e0`); no rotation.
- `zig1_5_clean -fsafe` compile: **0 diagnostic lines**; link + run rc 0.
- Deterministic: recompiled twice → identical stdout **and** byte-identical `prog`.
- Regression: `ogg_test` PASS (`pages=4 ... packets=91`), `info_test` PASS,
  `tier_info.sh` **20/20 PASS**.
- All runs from repo root; `-fsafe` throughout.

## Z98 conformance

Free functions; no generics/`anytype`/`@Type`/`@cImport`; strict `@intCast`
(shift amounts are `u32` — a `u5`/`u8` runtime shift amount triggers
`warning[3000] source: void` in zig1 even though codegen is correct); no
`switch`; string literals via `var s: []const u8`; D1 (no union tags); D2
(`[]Codebook` named struct, `[]u8` primitive); D3/D4 (no suspensions). Only
`std.arena` / `std_file` / `std.io` / `std.os` used; no compiler change.

## Concerns

1. **Task 2 will need the lookup tail.** `Codebook` intentionally discards the
   lookup type + VQ fields (min/delta/value_bits/sequence_p/lookup values);
   Task 2's `decodeVector` (lookup types 1/2) needs them, so the struct/parser
   must grow in Task 2. This is within-plan (Task 1 is explicitly the skeleton)
   but is the main forward-facing interface note.
2. **Plan says Task 2 uses an "MSB-first bit reader"; the setup header is
   LSB-first** (verified against all fixtures). The two can coexist if MSB-first
   refers to Huffman code accumulation rather than byte unpacking, but Task 2
   should reconcile this before implementing.
3. **Ordered / lookup-2 branches are fixture-absent** — covered only by the two
   synthetic vectors; consider a hand-verified real-world fixture in a later
   milestone if these paths become load-bearing.
4. `entries` is taken at face value (up to 2^24) for the length allocation; a
   crafted header can request a large arena block and get `OutOfMemory` (clean,
   never an overrun). Code lengths >255 in the ordered branch return
   `BadVersion` (avoids a `@intCast` trap).
