# Task 3 Report — z9play M0 Vorbis comment header (tags)

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 3)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): parse Vorbis comment header (tags)` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/vorbis_info.zig` — extended with `Tag`, `Comment`, and
  `parseComment` (plus the `dupBytes` arena helper). `parseId` unchanged.
- `examples/z98/z9play/tests/info_test.zig` — extended with the comment-header
  positive case (`tagged_unicode.ogg` packet 1) and five malformed cases, via
  new `commentFails` / `tagValue` helpers.

The plan allowed "modify the test"; the existing `info_test.zig` was extended
(not a new file) because it already owns the `vorbis_info` surface, and the
Task-1 `ogg_test.zig` PASS line stays provably untouched.

## Interface (as specified)

- `pub const Tag = struct { key: []const u8, value: []const u8 };`
- `pub const Comment = struct { vendor: []const u8, tags: []Tag };`
- `pub fn parseComment(arena: *std.arena.Arena, packet: []const u8) ogg.OggError!Comment`.

Layout consumed (little-endian): `0x03` + `"vorbis"`; vendor length u32 + bytes;
comment count u32; each comment = length u32 + `key=value` bytes; final framing
bit (bit 0 set). Keys are uppercased with `std.str.toUpper` per the Vorbis
convention. Every returned slice (`vendor`, each `key`, each `value`, and the
`[]Tag`) is allocated from `arena`; the parser never aliases the caller's packet
bytes. `parseComment` reuses `ogg.zig`'s `OggError` (no import cycle), as
`parseId` does.

### Error mapping

- packet < 11 bytes, vendor/tag length runs past the packet, comment count
  (`0xFFFFFFFF`) or comment length (`0xFFFFFFFF`) that cannot fit, or end of
  packet before the framing byte → `error.Truncated`.
- wrong packet-type byte, `"vorbis"` signature mismatch, a comment with no `=`,
  or framing bit clear (`packet[off] & 1 == 0`) → `error.BadVersion`.
- `dupBytes` / tag-array allocation failure → `error.OutOfMemory`.
- `count` is bounded by `packet.len` before `count * @sizeOf(Tag)` so the
  allocation size cannot overflow `usize` on 32-bit.

## Exact golden values (`tagged_unicode.ogg`, packet 1; 137 bytes)

| field | value |
|:--|:--|
| vendor (52 bytes) | `Xiph.Org libVorbis I 20200704 (Reducing Environment)` |
| comment count | 3 (packet order: `ALBUM`, `title`, `artist`) |
| `TITLE`  | `Café déjà vu` (`Caf\xc3\xa9 d\xc3\xa9j\xc3\xa0 vu`) |
| `ARTIST` | `Naïve 日本` (`Na\xc3\xafve \xe6\x97\xa5\xe6\x9c\xac`) |
| `ALBUM`  | `Ünïcodé` (`\xc3\x9cn\xc3\xafcod\xc3\xa9`) |
| framing bit | 1 |

Confirmed by an independent `python3` OGG page/packet walk before writing the
assertions: packet 1 begins `\x03vorbis`, vendor length 52, count 3, and the
values match `testdata/expected/tagged_unicode.meta` byte-for-byte. The fixture
stores lowercase keys (`title`/`artist`/`album`); the test looks them up as
`TITLE`/`ARTIST`/`ALBUM`, so it directly exercises the uppercasing requirement.

## Test coverage (`tests/info_test.zig`)

Positive: vendor, `tags.len == 3`, and `TITLE`/`ARTIST`/`ALBUM` values all equal
the golden byte-for-byte, including the non-ASCII UTF-8.

Negative (Task-3 gate "malformed → error"):
- wrong packet-type signature (`0x02`) → rejected;
- framing bit clear → rejected;
- truncated before the vendor length → rejected;
- comment count `0xFFFFFFFF` → rejected (no overflow panic);
- comment length `0xFFFFFFFF` → rejected (no overflow panic).

A `commentFails` helper returns true when `parseComment` returns any error.

## TDD sequence

1. **RED.** `info_test.zig` extended first; `zig1_5_clean -fsafe` failed
   `error[20]: identifier 'Tag' is not declared or imported in this module`
   (rc 2) — the expected not-implemented failure (same pattern as Tasks 1–2).
2. **GREEN.** `vorbis_info.zig` implemented; compile rc 0 (zero zig1
   diagnostics), link rc 0, run rc 0 →
   `info_test: PASS channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11`.

## Verification

- Seed: `/tmp/z9play_seed/zig1_5_clean` already at the Task-0 fixed point
  `bafbba9454cd2b134bdc3d50c65384e0` (v97); no rebuild needed.
- `-fsafe` compile of `tests/info_test.zig`: rc 0, **0** diagnostic lines.
- Link + run: rc 0 → `info_test: PASS channels=2 sample_rate=44100
  blocksize_0=8 blocksize_1=11`.
- Existing Task-1 harness unaffected: `tests/ogg_test.zig` compile rc 0, link
  rc 0, run rc 0 → `ogg_test: PASS pages=4 last_granule=88200 packets=91`.
- Deterministic: two independent `-fsafe` compiles of `info_test.zig` into
  `/tmp/z9play_info_green` and `/tmp/z9play_info_det2` produce byte-identical
  generated `.c`/`.h` (28/28 files `cmp` clean).
- The gcc `-Wunused-function` / non-compatible-call warnings in the link log are
  the pre-existing `zig_runtime.h` / `std_net` / `std_os` runtime warnings seen
  in Tasks 1–2; no new warning is attributable to this change.

## Z98 conformance

Only `examples/z98/z9play/**` touched; no compiler/`sf/src` change. Free
functions; no generics/`anytype`/`@Type`/`@cImport`; strict `@intCast`; no
`switch` (so no `else` needed); string literals via `var s: []const u8`;
`@ptrCast` used exactly as `ogg.zig` does for the `[]Tag` backing store; D1 (no
union tags); D2 (`[]Tag` of the named `Tag` type, `[]const u8` primitives);
D3/D4 (no suspensions). Optionals use `if (eq) |e|` (spec-listed). The previously
unused `const std = @import("std");` is now genuinely used (`std.arena.Arena`,
`std.str`), so it is retained rather than removed.

## Concerns

1. Vorbis does not define a comment's value for a field with no `=`; this
   parser rejects it as `error.BadVersion`. Fine for the fixture set and the
   M0 gate; a real-world file with a looser tag would be rejected by design.
2. Keys are uppercased but values are stored raw (not trimmed/normalized) — the
   CLI/TUI (Task 5) is the right place for display normalization.
3. `BadVersion` is reused for comment signature / missing-`=` / framing-clear
   (the shared `OggError` has no comment-specific member), consistent with
   `parseId`; the CLI only needs "decoder error" (exit 3).
4. No compiler/seed change; the interface matches the plan, so Task 4's
   duration work and Task 5's CLI can consume `Comment`/`Tag` directly.
