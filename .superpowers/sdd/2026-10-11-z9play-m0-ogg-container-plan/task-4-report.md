# Task 4 Report — z9play M0 duration from last-page granule

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 4)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): derive duration from last-page granule` (hash in the SDD return)
**Status:** COMPLETE

## Deliverables

- `examples/z98/z9play/ogg.zig` — added `durationMs`, `lastGranule`, and the
  private `pageStartsWith` helper (appended after `reassemble`; existing
  `Page`/`Packet`/`OggError`/`pageAt`/`nextPage`/`isCompletePacket`/`crcOk`/
  `reassemble` untouched).
- `examples/z98/z9play/tests/ogg_test.zig` — extended with a `checkDuration`
  helper and a `(d) duration` section covering all five fixtures plus the
  zero-sample-rate guard; also imports `vorbis_info` to obtain the sample rate
  from packet 0.

## Interface (as specified)

- `pub fn lastGranule(arena: *std.arena.Arena, data: []const u8) OggError!u64`
- `pub fn durationMs(last_granule: u64, sample_rate: u32) u64`
  (`duration_ms = last_granule * 1000 / sample_rate`, integer math; a zero
  `sample_rate` returns 0 so a malformed/absent id cannot trap under `-fsafe`).

`lastGranule` scans the pages twice: pass 1 identifies the audio serial as the
serial of the BOS page whose first packet body begins `\x01vorbis` (the Vorbis
identification header), returning `error.BadCapture` when none is present;
pass 2 keeps the maximum granule over pages of that serial, skipping the
"no completed packet" sentinel `0xFFFFFFFFFFFFFFFF`. Restricting to the audio
serial keeps a stray non-audio logical stream from inflating the duration;
chained/multiplexed OGG remains out of scope per the spec. The `arena`
parameter is retained for the plan's fixed signature and reserved for a future
streaming form — the scan is allocation-free (`_ = arena;`, exactly as
`nextPage` does `_ = data;`).

## Exact duration values (integer ms, from committed fixtures)

| fixture | last granule | sample rate | `durationMs` | golden | tolerance |
|:--|--:|--:|--:|:--|:--|
| `sine_stereo_44100.ogg` | 88200 | 44100 | 2000 | 2.000 | exact |
| `sine_mono_44100.ogg`   | 44100 | 44100 | 1000 | 1.000 | ±1 ms |
| `sine_stereo_48000.ogg` | 48000 | 48000 | 1000 | 1.000 | ±1 ms |
| `tagged_unicode.ogg`    | 44100 | 44100 | 1000 | 1.000 | ±1 ms |
| `short.ogg`             | 13230 | 44100 |  300 | 0.300 | ±1 ms |

Granules were confirmed by an independent `python3` OGG page walk before writing
the assertions (each fixture is a single logical stream; first page is BOS with
first packet `\x01vorbis`). All five land exactly on the golden milliseconds, so
the ±1 ms tolerance is never actually needed for these fixtures.

## Test coverage (`tests/ogg_test.zig`)

Positive: `checkDuration` reads each fixture, derives the granule via
`ogg.lastGranule`, obtains the rate via `vi.parseId(packets[0].bytes).sample_rate`
(container + id integration), computes `ogg.durationMs`, and asserts the
absolute difference is within tolerance (0 ms for `sine_stereo_44100`, 1 ms for
the rest). Edge: `ogg.durationMs(500, 0) == 0` guards the zero-rate case. The
existing page-walk / reassembly / CRC assertions are unchanged.

## TDD sequence

1. **RED.** Duration assertions added first; `zig1_5_clean -fsafe` failed with
   `error[3042]: non-value base expression in field access` (×3) plus
   `warning[3023]: module used as value expression` and two `warning[3000]`
   type-mismatch notes (`source: void`, `target: u64`) on the
   `ogg.lastGranule` / `ogg.durationMs` lines — the expected not-implemented
   failure (rc 2), the same pattern as Tasks 1–3.
2. **GREEN.** `ogg.zig` implemented; compile rc 0 (zero zig1 diagnostics),
   link rc 0, run rc 0 →
   `ogg_test: PASS pages=4 last_granule=88200 packets=91`.

## Verification

- Seed: `/tmp/z9play_seed/zig1_5_clean`, md5
  `bafbba9454cd2b134bdc3d50c65384e0` (v97 fixed point); no rebuild needed.
- `-fsafe` compile of `tests/ogg_test.zig`: rc 0, **0** diagnostic lines;
  link rc 0; run rc 0 →
  `ogg_test: PASS pages=4 last_granule=88200 packets=91`.
- Regression: `tests/info_test.zig` compile rc 0, link rc 0, run rc 0 →
  `info_test: PASS channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11`.
- Deterministic: two independent `-fsafe` compiles of `ogg_test.zig` into
  `/tmp/z9play_t4_det1` and `/tmp/z9play_t4_det2` produce byte-identical
  generated `.c`/`.h` (30/30 files `cmp` clean). Only the internal
  `.zig1_ast.tmp` / `.zig1_lir.tmp` IR dumps differ (they embed the output
  path); this is pre-existing driver behaviour, not a source nondeterminism.
- Scope: `git diff --name-only` = `examples/z98/z9play/ogg.zig`,
  `examples/z98/z9play/tests/ogg_test.zig` only.

## Z98 conformance

Only `examples/z98/z9play/**` touched; no compiler/`sf/src` change, no seed
rotation. Free functions; no generics/`anytype`/`@Type`/`@cImport`; strict
`@intCast` (`@intCast(usize, page.body_start)`, `@intCast(u64, sample_rate)`);
no `switch` (so no `else` needed); string literal via
`var id: []const u8 = "\x01vorbis";`; D1 (no union tags); D2 (only
`[]const u8` slices, no slice-of-synthetic); D3/D4 (no suspensions, no
global-struct-across-suspension). `@import` direction unchanged
(`vorbis_info → ogg`, never the reverse), so no cycle. The link log's
`-Wunused-function` / non-compatible-call warnings are the pre-existing
`zig_runtime.h` / `std_net` / `std_os` runtime warnings seen in Tasks 1–3; no
new warning is attributable to this change.

## Concerns

1. `lastGranule` identifies the audio serial from the Vorbis id header on a
   BOS page. Chained/multiplexed OGG is explicitly out of scope (spec §1), so
   this is sufficient for M0; a stream whose id page is not flagged BOS would
   be rejected as `error.BadCapture`, which is the correct strict behaviour.
2. The granule is a sample count (per-channel, not interleaved) per the Vorbis
   mapping, so no channel factor belongs in `durationMs`; the CLI (Task 5)
   consumes `durationMs` directly.
3. `durationMs` truncates toward zero; for the committed fixtures the division
   is exact. A hypothetical sub-millisecond remainder is dropped, which matches
   the golden's 3-decimal seconds within 1 ms.
4. The `arena` parameter of `lastGranule` is currently unused (discarded). It
   is mandated by the plan's fixed signature; if a later milestone needs
   streaming, the allocation path is already in place. No compiler/seed change;
   the interface matches the plan, so Task 5's `--info` block can consume
   `durationMs` directly.
