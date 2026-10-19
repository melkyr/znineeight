# M8 Task 5 report — final handoff

**Status:** COMPLETE (report-only; no source/test/docs/plan changes).

**Commit (report):** `docs(sdd): M8 T5 report` (this file only).

## Feature-complete status

z9play is **feature-complete per the spec**
(`docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`):
OGG Vorbis playback plus optional FLAC (M8), with both the CLI and TUI
frontends, on Linux and Win9x.

- OGG Vorbis: native Z98 decode through the CLI (`--wav`, interactive) and TUI.
- FLAC (optional M8): native decode behind the frontend selector; works through
  `--wav`, interactive CLI, and the TUI, including mixed `.ogg`/`.flac`
  directories.
- Frontends: CLI and TUI both complete in M5/M7 and exercised by the M8 tier.
- Platforms: Linux is gate-verified. **Win9x is design-verified only**; the
  emitted Win9x build is PE32 i386 with exactly `KERNEL32.DLL`/`WINMM.DLL`
  imports and passes the 9x import whitelist. **Win98/Me hardware verification
  remains operator-pending and is not claimed.**

No further z9play milestone: the M8 plan notes `NEXT: none (final)`.

## Deferred arms (truthful)

- `--info`, `--dump-setup`, and `--pcm` remain **Vorbis-only**; a FLAC input is
  rejected with `not an OGG Vorbis stream` and **exit 3**.
- FLAC limits: 32-bit streams are rejected mid-decode; frame **CRC-16 is
  skipped** (header CRC-8 is verified); FLAC tags/comment metadata are not
  parsed; only the **16-bit PCM** target is supported.
- TUI limits: `d` removes the current track (no playlist cursor); the playlist
  index has a gap after removal; the arena is not reset; non-tty behavior is
  limited; extra `=`/Ctrl-C key aliases exist.
- Win98/Me **hardware verification pending** (as above).
- Compiler defects **D3/D4/D5 remain OPEN**; they are not z9play blockers.
  (D1/D2 are FIXED in seed v102.)

## Next example / milestone

The next planned example milestone is **z9torr M6 — seed & upload**
(`docs/superpowers/plans/2026-10-11-z9torr-m6-seed-upload-plan.md`). Its plan
has the seed-v102 truth-up applied (`44cd1237`); execution is pending. There is
no further z9play milestone.

## Gate check

All M8 task reviews have **no open Critical/Important** items:

| Task | Implementation commit | Report commit | Review status |
|---|---|---|---|
| T1 decoder abstraction | `c4b53d84` | `9024d433` | Approved; 0 Critical / 0 Important (3 Minor) |
| T2 FLAC stream/frame decode | `07d92393` | `73991c5b` | Approved; 0 Critical / 0 Important (6 Minor) |
| T3 `tier_flac.sh` | `903ea2ab` | `c6f9bedb` | Approved; 0 Critical / 0 Important (5 Minor) |
| T4 docs | `808355d3` + fix `ee485934` | `67ba38dd` / `0772f3ee` | Needs-fixes resolved; fix round 1 scoped re-review: all 3 findings ADDRESSED, no new breakage; 0 Critical / 0 Important |

The remaining items are deferred Minor limits only (listed above). Task 5 adds
no review debt.

## Seed / tier evidence

- T5 changes no source, tests, docs, plans, or seed; this commit is the report
  only.
- Seed v102 (unchanged): archive `release/seed/zig1-seed.tgz` md5
  `702f34d87b7e6bf401dd206d2517dbee`; fixed point
  `b299b4b435e624d0ddbd2edde681cbc3`.
- FLAC tier (`tests/tier_flac.sh`) from T3: **59 passed, 0 failed**, twice,
  byte-identical logs. It covers `-fsafe` `main.zig`/`ui.zig` builds, three
  regenerated `.flac` fixtures, byte-exact `--wav` payloads vs `flac -d`,
  3x raw-PCM determinism, mixed `.ogg`/`.flac` TUI selection (18/18), and the
  Win9x PE32/import gate.
- OGG regression tiers in the same T3 runs: `tier_cli` **23/0**,
  `tier_tui` **40/0**, `tier_audio` **27/0**; `tier_win9x` **14/0** in the
  T1/T2 runs.
- T4 measured current `--dump-c89` pins: `main.zig`
  `e56af7916edd199e796f3ef11d5e49c4`, `ui.zig`
  `22676fd997471df1c4c3a3f04397121d`; `-osw` `main.zig`
  `aa68782328c001c1f72d03f8ab1282d7`.

T5 did not rerun the tiers (report-only); the counts above cite the T3 report.

## Caveat

Win9x support is design-verified and emission/build/import-gated. Real
Win98/Me hardware verification is operator-pending and is not claimed by this
handoff.
