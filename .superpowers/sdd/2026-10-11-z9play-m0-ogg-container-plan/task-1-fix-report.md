# Task 1 Fix Report — bound `reassemble` against unterminated packets

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m0-ogg-container-plan.md` (Task 1)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `fix(z9play): bound reassemble against unterminated packets (+ continuation/OOB tests)` (hash in the SDD return)
**Status:** COMPLETE

## Problem (HIGH, from M0 final review)

`ogg.zig` `reassemble` sized its copy buffer (`blob`, `total`) from **terminated
packets only** (pass 1, old lines 168-171), but pass 2 copied **every** segment
byte into `blob[w++]` with no upper bound. A stream whose final packet never
terminates (left open by a trailing `255` lace at EOF) therefore wrote past the
allocation:

- ~3.9 MiB all-continuation input → `--info` SIGSEGV (rc 139);
- a small unterminated tail silently scribbled into arena slack, then exited 3.

This violated the plan/spec "malformed → `OggError`" contract.

## Fix

Two changes in `reassemble`:

1. **Reject the unterminated tail before allocating.** At the end of pass 1, an
   in-progress packet is exactly `cur != 0`; return `error.Truncated`
   (`ogg.zig:179-182`). This is the spec-consistent choice (plan `OggError`
   includes `Truncated`; `main.zig` maps any `reassemble` error to exit code 3).
2. **Hard-bound the pass-2 copy.** `if (w >= total) return error.Truncated;`
   before each `blob[w]` store (`ogg.zig:203-209`) — unreachable for accepted
   input, but guarantees no OOB write even if the pass-1/pass-2 logic ever
   diverges.

Well-formed input is byte-identical: pass 1 leaves `cur == 0` at EOF for any
stream whose last packet is terminated, so the new check is inert, and `w`
never reaches `total` before all terminated packets are copied.

## Regression tests (`tests/ogg_test.zig`, hand-crafted, no new tooling)

- **(e) multi-page continuation** (`testContinuationReassembly`): page A (BOS)
  with one `255`-laced segment, page B (continuation flag) with laces `[45, 3]`.
  Asserts exactly 2 packets: packet 0 length 300 with the `0xAA`/`0xBB` boundary
  at byte 255, packet 1 = `"xyz"`. Exercises the cross-page carry path the
  fixtures never hit. (This path was already correct pre-fix; now locked in.)
- **(f) unterminated trailing packet** (`testUnterminatedReassembly`): a page
  with laces `[3, 255]` — one closed `"abc"` packet then a 255-byte open tail.
  Asserts `reassemble` returns `error.Truncated`. Non-vacuous: pre-fix this
  returned success with 1 packet (writing 255 bytes past the 3-byte
  allocation), so the assertion fails on the old code and passes on the new.

TDD: tests added first, built against the unmodified `ogg.zig` → **RED**
(`ogg_test: FAIL: unterminated trailing packet did not return Truncated`,
rc 1, *no crash* — the crafted small case is the silent-slack variant).
After the fix → **GREEN**.

## Verification

- Seed rebuilt: `bash scripts/seed/build_from_seed.sh release/seed/zig1-seed.tgz
  /tmp/z9m0_seed` → two-hop closure
  `bafbba9454cd2b134bdc3d50c65384e0` (expected). rc 0.
- `tests/ogg_test.zig` (`-fsafe`): compile rc 0, run **PASS** →
  `ogg_test: PASS pages=4 last_granule=88200 packets=91`; two runs
  byte-identical.
- `tests/tier_info.sh` (`ZIG=/tmp/z9m0_seed/zig1_5_clean`): **20 passed, 0
  failed** — `TIER_INFO PASS`. All five goldens still byte-identical.
- **Reported repro re-run**: 60-page / 3.9 MiB all-continuation synthetic file →
  `z9play: not an OGG Vorbis stream`, **rc 3** (was SIGSEGV 139).
- `git diff --stat -- sf/src` empty → **no compiler/seed change**.

## Concerns

1. Returning `error.Truncated` for an unterminated tail is stricter than merely
   dropping the partial packet; chosen because the plan/spec phrase the contract
   as "malformed → error" and `OggError` already carries `Truncated`. If a later
   milestone wants tolerant tail-dropping, it should be a deliberate change.
2. `reassemble` still assumes a single logical stream (no serial filtering), per
   the original plan; unchanged here.
3. The defensive `w >= total` bound returns `Truncated` mid-copy only if
   pass 1/pass 2 ever disagree; no accepted input reaches it.
