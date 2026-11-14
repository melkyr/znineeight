# Task 2 Report — z9play M0 Vorbis identification header

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 2)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): parse Vorbis identification header` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/vorbis_info.zig` — Vorbis identification header parser
  (`IdHeader` struct + `parseId`). (First file in this module; comment header
  lands in Task 3.)
- `examples/z98/z9play/tests/info_test.zig` — deterministic unit harness for
  `parseId`.

The plan allowed either extending `tests/ogg_test.zig` or adding a new
`tests/info_test.zig`. A **new** file was chosen so the Task-1 harness stays
byte-identical and its `pages=4 last_granule=88200 packets=91` PASS line is
provably unaffected.

## Interface (as specified)

- `pub const IdHeader = struct { version: u32, channels: u8, sample_rate: u32,
  bitrate_max: i32, bitrate_nom: i32, bitrate_min: i32, blocksize_0: u8,
  blocksize_1: u8 };`
- `pub fn parseId(packet: []const u8) ogg.OggError!IdHeader`.

Layout consumed (little-endian): `0x01` + `"vorbis"` + version u32 + channels
u8 + sample_rate u32 + 3×i32 bitrates + blocksize byte (low nibble = exp0, high
= exp1) + framing flag (bit 0 set). `parseId` uses `ogg.zig`'s `OggError` by
importing the sibling module (no cycle: `ogg.zig` does not import
`vorbis_info.zig`).

### Error mapping

- `packet.len < 30` → `error.Truncated`.
- first byte != `0x01`, `"vorbis"` mismatch, `version != 0`, or framing bit
  clear (`packet[29] & 1 == 0`) → `error.BadVersion`.

i32 bitrates are read via `@bitCast(i32, u32)` (bit pattern, not a checked
cast) so negative bitrate fields round-trip correctly; `u32`/`u8` fields use
`@intCast` per the Z98 strictness rule.

## TDD sequence

1. **RED.** `info_test.zig` written first; `zig1_5_clean -fsafe` failed
   `error[3048]: could not resolve imported file '../vorbis_info.zig'` (rc 2) —
   the expected not-implemented failure (same pattern documented in Task 1).
2. **GREEN.** `vorbis_info.zig` implemented; compile rc 0 (zero zig1
   diagnostics), link rc 0, run rc 0 →
   `info_test: PASS channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11`.

## Exact golden values (sine_stereo_44100.ogg, packet 0; 30 bytes)

| field | value |
|:--|:--|
| version | 0 |
| channels | 2 |
| sample_rate | 44100 |
| bitrate_max | 0 |
| bitrate_nom | 112000 |
| bitrate_min | 0 |
| blocksize byte | 0xB8 → blocksize_0 exponent **8**, blocksize_1 exponent **11** |
| framing bit | 1 |

The values were independently confirmed by a throwaway `python3` OGG
page/packet walk (91 packets; packet 0 begins `\x01vorbis`) before writing the
assertions; they match `testdata/expected/sine_stereo_44100.meta`
(`channels=2`, `sample_rate=44100`).

## Test coverage (`tests/info_test.zig`)

Positive: `parseId(packet 0)` equals all eight golden fields exactly.

Negative (Task-2 gate "malformed framing/version → error"):
- framing bit cleared (`bad[29] &= 0xFE`) → rejected;
- non-zero version (`bad[7] = 1`) → rejected;
- bad capture signature byte (`bad[1] = 'X'`) → rejected.

A `parseFails` helper returns true when `parseId` returns any error.

## Verification

- Seed: `/tmp/z9play_seed/zig1_5_clean` already at the Task-0 fixed point
  `bafbba9454cd2b134bdc3d50c65384e0` (v97); no rebuild needed.
- `-fsafe` compile of `tests/info_test.zig`: rc 0, **0** diagnostic lines.
- Link + run: rc 0 → `info_test: PASS channels=2 sample_rate=44100
  blocksize_0=8 blocksize_1=11`.
- Existing Task-1 harness unaffected: `tests/ogg_test.zig` compile rc 0, link
  rc 0, run rc 0 → `ogg_test: PASS pages=4 last_granule=88200 packets=91`.
- Deterministic: two independent `-fsafe` compiles of `info_test.zig` into
  `/tmp/z9play_info_out` and `/tmp/z9play_info_out2` produce byte-identical
  `.c`/`.h` (per-file `cmp` clean).

## Z98 conformance

Only `examples/z98/z9play/**` touched; no compiler/`sf/src` change. Free
functions; no generics/`anytype`/`@Type`/`@cImport`; strict `@intCast` (with
`@bitCast` only for the signed bitrate fields); no `switch`; string literal via
`var sig: []const u8 = "vorbis"`; D1 (no union tags); D2 (`[]const u8`
primitive); D3/D4 (no suspensions). Uses `std`, `std_file`, `std.io`,
`std.arena`, `std.os`.

## Concerns

1. `parseId` does not validate the framing flag beyond bit 0, nor require
   `packet.len == 30` exactly; extra trailing bytes are ignored. Harmless for
   the fixture set and consistent with the plan's minimal validation.
2. `OggError.BadVersion` is reused for every structural mismatch (capture,
   version, framing) because the shared error set has no more specific member.
   Acceptable for M0; the CLI (Task 5) only needs "decoder error" (exit 3).
3. No compiler/seed change; the interface matches the plan, so Task 3's
   `parseComment` can extend this module directly.
