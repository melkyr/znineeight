# Task 1 Report — z9play M0 OGG container (`ogg.zig` + unit harness)

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 1)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): OGG container page parse + packet reassembly` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/ogg.zig` — page framing + packet reassembly.
- `examples/z98/z9play/tests/ogg_test.zig` — deterministic unit harness.

## TDD sequence

1. **RED.** `ogg_test.zig` written first; build with the seed recipe failed
   `error[3048]: could not resolve imported file '../ogg.zig'` (rc 2) —
   expected not-implemented failure.
2. **GREEN.** `ogg.zig` implemented; `-fsafe` compile + link + run → PASS:
   `ogg_test: PASS pages=4 last_granule=88200 packets=91`.

## Interface (as specified)

- `Page = struct { granule:u64, serial:u32, seq:u32, header_type:u8, body_start:u32, body_len:u32 }`.
- `Packet = struct { bytes: []const u8 }`.
- `OggError = error{ BadCapture, BadVersion, Truncated, Crc, OutOfMemory }`.
- `pageAt(data,off)`, `nextPage(data,page)`, `isCompletePacket(page)`,
  `crcOk(data,page)`, `reassemble(arena,data) OggError![]Packet`.

`pageAt` validates the `OggS` capture pattern, version 0, and that header +
segment table + body all lie inside `data` (else `Truncated`). `nextPage`
returns `body_start + body_len`.

## CRC-32: local table required (plan-anticipated fallback)

The OGG CRC is **not** IEEE 802.3: it uses polynomial `0x04c11db7`, init `0`,
**no** input/output reflection, **no** final XOR. `std_crypto` exposes only the
reflected IEEE CRC-32 (init/xorout `0xFFFFFFFF`), which does **not** verify the
fixtures (confirmed: stored `fbe86412` vs IEEE `4faf8e05` on page 0). So the
plan's "else a local table" branch applies; the OGG CRC is implemented locally
(`oggCrcPage`, bitwise with `0x04c11db7`). Not a blocker — the plan explicitly
allows it.

**`-fsafe` shift caveat (fix round 1).** The first implementation used
`crc << 1`; Z98's `<<` is overflow-checked under `-fsafe`
(`zig_overflow_flag_shl_u` → `pal_trap()`), so the program SIGTRAPped inside
`oggCrcPage`. Replaced both shifting left-shifts with the wrapping multiply
`crc *% 2`. The `b << 24` term never shifts a bit out (`b ≤ 0xFF`), so it is
safe. Verified by gdb backtrace before the fix and PASS after.

### `crcOk` page-start recovery (interface consequence)

The fixed `Page` shape (no page offset, no segment count) means `crcOk` cannot
trivially locate the header. It recovers the page start by scanning candidate
`nseg` in `0..=255` for the offset `body_start - 27 - nseg` where `OggS` +
version 0 hold and the candidate segment table sums to `body_len`
(`pageStartOf`). The true page start satisfies all three uniquely for real
pages. This keeps the `Page` fields exactly as the plan fixes them.

## `isCompletePacket` semantics (interface ambiguity, documented)

The signature has no `data` parameter, so it cannot inspect lacing; it can only
use `header_type`. Implemented as "the page's first packet is not a continuation
carried over from the previous page" — i.e. `(header_type & 0x01) == 0`.
Documented in the source.

## Reassembly

Two passes over the page walk:
1. count packets and total packet bytes (segment length `< 255` terminates a
   packet, `255` means continue);
2. copy every segment body **segment-by-segment** into one contiguous arena blob
   and slice each packet out at its terminator.

Copying per segment (not as a contiguous file range) is deliberate: a packet
spanning pages would otherwise pick up the interstitial page header + segment
table. `[]Packet` is a slice of the named struct `Packet` (D2-safe).

## Test coverage (`tests/ogg_test.zig`)

Against `testdata/sine_stereo_44100.ogg`:
- (a) page walk → exactly **4** pages, first granule **0**, last granule
  **88200**, `crcOk` true on every page;
- (b) `reassemble` → the first three packets begin `\x01vorbis`, `\x03vorbis`,
  `\x05vorbis` (91 packets total).

Plus (c) `crcAllPages` across **all five** committed fixtures
(`sine_mono_44100`, `sine_stereo_48000`, `tagged_unicode`, `short`,
`sine_stereo_44100`) — satisfies the Step-4 gate "CRC verify true on all fixture
pages".

## Verification

- Seed: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
  /tmp/z9play_seed` → fixed point
  `bafbba9454cd2b134bdc3d50c65384e0` (expected).
- `zig1_5_clean -fsafe` compile: rc 0, **zero** diagnostic lines.
- Link + run: rc 0 → `ogg_test: PASS pages=4 last_granule=88200 packets=91`.
- Deterministic: two runs byte-identical (`cmp` clean).
- Independent `python3` OGG-CRC re-check: all pages of all five fixtures
  `crc_all_ok=True` (3/3/4/3/3 pages).

## Z98 conformance

Free functions; no generics/`anytype`/`@Type`/`@cImport`; strict `@intCast`;
no `switch`; string literals via `var s: []const u8`; D1 (no union tags); D2
(`[]Packet` named struct, `[]const u8` primitive); D3/D4 (no suspensions). Only
`std.arena` / `std_file` / `std.io` / `std.os` used; no compiler changes.

## Concerns

1. `reassemble` assumes a single logical stream (per plan, "per logical
   stream"); it does not filter by serial. Fixtures are single-stream. M1+
   should keep the stream single.
2. `pageAt` bounds-checks header/table/body but `crcOk`'s `pageStartOf` is a
   bounded backward scan; a malicious file with a false `OggS`+matching-sum
   combination could confuse page-start recovery, but this affects only CRC
   verification, not packet extraction, and is not exercised by the fixtures.
3. No compiler/seed change; interface matches the plan exactly, so M1's
   `--dump-setup` consumption of `reassemble` is unblocked.
