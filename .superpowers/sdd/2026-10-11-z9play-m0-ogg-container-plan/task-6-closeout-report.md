# Task 6 + M0 Closeout Report — z9play M0

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 6 + Self-Review)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**M0 working commit:** `27b1fddf` (`example(z9play): z9play --info CLI + tier_info gate`)
**Status:** COMPLETE

## Part A — Next-milestone (M1) amendment review

**Verdict: NO AMENDMENT NEEDED.** M0's actual implementation does not invalidate
any assumption in `2026-10-11-z9play-m1-setup-codebooks-plan.md`. The M1 plan
file is **unmodified** (as required when no amendment is needed).

Checks (the five required, plus two incidental):

1. **`ogg.zig` packet API shape.** M0 exports
   `pub const Packet = struct { bytes: []const u8 };` and
   `pub fn reassemble(arena: *std.arena.Arena, data: []const u8) OggError![]Packet`.
   `tests/ogg_test.zig` asserts packet 0 = `\x01vorbis`, packet 1 = `\x03vorbis`,
   **packet 2 = `\x05vorbis`**. M1 consumes packet index 2 with
   `parseSetup(arena, packet: []const u8) OggError!Setup` — it receives the setup
   header as the same `[]const u8` (the arena-owned contiguous `Packet.bytes`).
   **Confirmed.**
2. **`OggError` / arena conventions.** `ogg.zig` exports
   `pub const OggError = error{ BadCapture, BadVersion, Truncated, Crc, OutOfMemory }`.
   M1's signatures return `OggError!...` and take an arena; M0's convention is
   `*std.arena.Arena` (module `std_arena`, re-exported as `std.arena` in
   `std.zig`; both `@import("std_arena")` and `std.arena` are used in-tree). M1's
   plan spells the tech stack `std_arena`, matching the direct-import form, and
   its pseudo-signatures do not name a concrete arena type, so it follows M0's
   actual convention. `vorbis_info.zig` (shared by M1) already models this.
   **Confirmed.**
3. **Fixture set.** Five committed fixtures
   (`sine_mono_44100`, `sine_stereo_44100`, `sine_stereo_48000`,
   `tagged_unicode`, `short`) all carry a Vorbis setup header (packet 2), which
   the M0 `ogg_test` already proves for `sine_stereo_44100`. M1's plan requires
   no additional/different fixtures (it asserts codebook/floor/residue/mapping/
   mode facts "for the fixtures"). Note (non-blocking, not an amendment): all
   fixtures were encoded by the same `oggenc` defaults, so their setup headers
   may be near-identical — coverage is real but narrow; M1 may add a fixture
   later if it wants setup diversity, but its plan does not require one.
   **Confirmed sufficient.**
4. **Build recipe / `-fsafe` tier conventions.** M0's binding recipe is:
   seed via `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
   <dir>` (two-hop closure `bafbba9454cd2b134bdc3d50c65384e0`, v97), then
   `<seed>/zig1_5_clean -fsafe -o <out> examples/z98/z9play/main.zig` +
   `sh <out>/build_target.sh linux <out>/prog`; tiers take `ZIG=` and run under
   `-fsafe` (`tier_info.sh`). M1's plan says "build `-fsafe`", records
   `--dump-c89` md5, and introduces `tests/tier_setup.sh`, which naturally
   mirrors `tier_info.sh`. **Confirmed.**
5. **Type/name references.** The only M0-owned name M1 references is `OggError`.
   Every other type M1 names (`Setup`, `DecodeTable`, `BitReader`) is M1-owned
   and new. No M0 type is named differently in M1. (Incidental: M0's
   `vorbis_info.zig` header comment loosely says "Extend `vorbis_info.zig` with
   a `setup.zig` parser", while the M1 plan's File Structure names
   `vorbis_setup.zig` + `codebook.zig`; M0 created neither file, so this is a
   comment wording nuance, not a M1-assumption conflict — M1 owns its files.)
   **Confirmed.**
6. *(Incidental)* **Gate.** M0's gate is `tests/tier_info.sh` (metadata vs
   golden); M1's gate is `tests/tier_setup.sh` (codebook invariants) — no
   overlap. **Confirmed.**
7. *(Incidental)* **Sequence/precondition.** M1 Task 0 requires re-confirming
   against M0's actual `ogg.zig` output; this report satisfies that from M0's
   side and M1 Task 0 re-confirms before starting. **Confirmed.**

## Part B — M0 closeout gates (all fresh)

Seed built from `release/seed/zig1-seed.tgz` into `/tmp/z9m0_seed` (seed v97):

- **Seed closure:** `[seed] two-hop closure OK: hop1 == hop2 ==
  bafbba9454cd2b134bdc3d50c65384e0` — **matches expected**.
- **`tests/tier_info.sh`** (`ZIG=/tmp/z9m0_seed/zig1_5_clean`):
  `== tier_info summary: 20 passed, 0 failed ==` → **TIER_INFO PASS**.
- **`tests/ogg_test.zig`**: `ogg_test: PASS pages=4 last_granule=88200
  packets=91` (rc 0).
- **`tests/info_test.zig`**: `info_test: PASS channels=2 sample_rate=44100
  blocksize_0=8 blocksize_1=11` (rc 0).
- **Corpus discovery:** `bash scripts/corpus/list_corpus_dirs.sh` lists
  `examples/z98/z9play/` (line 25 of 1123).
- **`--dump-c89` md5:** `timeout 120 /tmp/z9m0_seed/zig1_5_clean --dump-c89
  examples/z98/z9play/main.zig | md5sum` =
  `ba86cbe8b2229667f4c8084a0b0e75da` — **matches the recorded NOTES value** (v97).

### Closeout edits

- `examples/z98/z9play/NOTES.md` — `Working commit` pinned to `27b1fddf`; M1
  review verdict ("no amendment needed") recorded. Build recipe + `--dump-c89`
  md5 verified accurate.
- `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` — all
  task checkboxes marked done; an "**M0 status: complete (Tasks 0–6)**" note
  added; M1 plan left unchanged.

## Concerns

- None blocking. One observation carried forward from Task 5 (not this task's
  scope): M0 `--info` does not reject sample rates ∉ {44100, 48000}; that is a
  playback/decoder (M3/M5) concern, flagged for later.
- M1 setup-fixture diversity is narrow (all fixtures from one `oggenc` config);
  M1 may add a fixture if it wants broader codebook coverage, but its plan does
  not require it. Not an amendment.
