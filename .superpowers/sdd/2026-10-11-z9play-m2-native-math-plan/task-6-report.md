# Task 6 Report — z9play M2 next-milestone (M3) amendment review + M2 closeout

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m2-native-math-plan.md` (Task 6)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding §3, §9)
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Seed:** v97, two-hop closure `bafbba9454cd2b134bdc3d50c65384e0` (unchanged)
**Pinned M2 implementation commit:** `b5ca08d2` (`feat(std_math): f64 sin/cos (pure Z98)`)
**Status:** COMPLETE

## Part A — M3 amendment review

**Verdict: NO AMENDMENT NEEDED.** M2's actual `std_math` f64 surface
`{sqrt, sin, cos}` covers every function M3 actually calls, and M3's largest
phase angle is ~25× inside the `sin`/`cos` argument-reduction domain cap.

### (1) Exact functions M3 calls (enumerated from the M3 plan + spec)

| M3 task / path | math used | needed M2 f64 fn |
|:--|:--|:--|
| Task 1 IMDCT (`dsp.zig`) | inverse-MDCT basis `cos(π/n·(2i+1+n/2)(2k+1))` | **`cos`** |
| Task 1 window (`dsp.zig`) | Vorbis window `sin(π/2 · sin²(π/(2n)·(i+0.5)))` | **`sin`** |
| Task 1 overlap-add | `+` only | — (baseline) |
| Task 2 floor1 (`floor.zig`) | committed static `floor1_inverse_dB_table` + linear interpolation (integer / baseline `+ - * /`) | — |
| Task 2 floor0 | **rejected in v1** → `error.UnsupportedFloor` | — |
| Task 3 residue (`residue.zig`) | codebook Huffman decode (M1) + VQ `min + delta·multiplicand + last` (baseline f64) | — |
| Task 4 packet→PCM (`decode.zig`) | mode/floor/coupling/residue/IMDCT/window/overlap-add + clamp/round to s16 | **`sin`, `cos`** |

`π` is a compile-time constant local to the example (spec §3), not a std
function. `sqrt` is in M2's set but is on **no** M3 path (harmless, future-proof).

### (2) Functions explicitly checked for additional need

- `exp` / `log` — floor0 `bark()` only; floor0 rejected in v1 → **not needed**.
- `atan` / `atan2` — floor0 `bark()` / LSP only → **not needed**.
- `pow` — the window's `sin²` is `sin(x)*sin(x)` → **not needed**.
- `floor` — s16 rounding is `+0.5` then `@intCast` truncation + integer clamp → **not needed**.

### (3) Argument-reduction domain (the real question M3 must not violate)

- M2 cap (from `sf/src/std_math.zig:349,381`, threshold `0x413921fb`):
  `|x| ≤ 2^20·(π/2) ≈ 1.647e6` rad; **NaN beyond**.
- Largest M3 phase: the IMDCT. For the maximum Vorbis block `n = 8192`
  (blocksize exponent ≤ 13), with `i ≤ n-1`, `k ≤ n/2-1`:
  `max|arg| = π/n·(2(n-1)+1+n/2)·(2(n/2-1)+1) = π/8192·20479·8191 ≈ 6.43e4` rad.
- The window's outer `sin` argument is ≤ `π/2 ≈ 1.571` rad.
- `1.647e6 / 6.43e4 ≈ 25.6×` headroom; even an (illegal) block size up to
  `~2^18` stays under the cap. **No M3 block size reaches the NaN region.**

**Covered list (final):** `{sin, cos}` load-bearing, `{+,-,*,/}` baseline, `π`
constant; `sqrt` present but unused. Exactly M2's delivered surface → **M3 needs
no amendment.**

## Part B — M2 closeout

- **Working commit pinned (NOTES `b5ca08d2`).** `examples/z98/z9play/NOTES.md`
  "Working commit" is now the M2 `std_math` implementation commit `b5ca08d2`
  (`feat(std_math): f64 sin/cos (pure Z98)`), with the full M2 chain recorded
  (`4d6fb5dd` sqrt → `b5ca08d2` sin/cos → `52958705` tier → `6844aad5` docs)
  and the prior M0/M1 pins retained.
- **`--dump-c89` md5 — recorded; and it DID change (premise corrected).** The
  M2 plan/closeout instruction assumed "M2 is std-only so the z9play
  `--dump-c89` is unchanged". Empirically **false**, and the mechanism is now
  proven:
  - `--dump-c89 examples/z98/z9play/main.zig` emits the whole imported `std`
    module; `std` re-exports `std_math`, so the new `sqrt`/`sin`/`cos` bodies
    (and their helpers) appear in the dump.
  - The binding seed recipe (`scripts/seed/build_from_seed.sh` line 145)
    **copies the current `sf/src/std_*.zig` into the compiler's `lib/`**; the
    dump resolves `std` from there. So the md5 tracks the repo `std_math.zig`
    at seed-build time, even though the z9play *example source* is unchanged.
  - Direct experiment (swap `lib/std_math.zig`): M1-era integer-only std_math
    → `344c26ed89dd0830443fa5e16b870ec0` (the recorded M1 value, reproduced);
    M2 std_math → `88ad559ce5e4a3dae6f11a0c52b35792` (stable 3×).
  - `NOTES.md` + `README.md` now record the **M2** md5
    `88ad559ce5e4a3dae6f11a0c52b35792` and state the change and its cause.
  - The compiler-seed fixed point is unaffected (std-only, no compiler change):
    still `bafbba9454cd2b134bdc3d50c65384e0`.
- **M2 plan status field:** none (`grep` confirms); `- [ ]` checkboxes left
  untouched, consistent with Tasks 1–5.

## Gate summary (seed v97, `-fsafe`, example-only; no compiler/seed change)

| Gate | Result |
|:--|:--|
| `tests/tier_math.sh` | **8 passed, 0 failed** — `TIER_MATH PASS` |
| `scripts/stdlib/verify_stdlib.sh <seed>` | **285 PASS / 0 FAIL** — `STDLIB GATE OK` |
| `tests/tier_setup.sh` | **21 passed, 0 failed** — `TIER_SETUP PASS` |
| `tests/tier_info.sh` | **20 passed, 0 failed** — `TIER_INFO PASS` |
| seed closure (two-hop) | **`bafbba9454cd2b134bdc3d50c65384e0`** (hop1 == hop2) |
| `--dump-c89` md5 (z9play) | **`88ad559ce5e4a3dae6f11a0c52b35792`** (was M1 `344c26ed…`) |

## Concerns

1. **The closeout instruction's `--dump-c89` premise was wrong.** M2's std-only
   change *does* alter the z9play `--dump-c89` md5, because the dump transitively
   embeds `std_math` via `std` and the seed snapshots `sf/src` into `lib/`. This
   is not a regression (the example source and the compiler fixed point are
   unchanged); it is recorded correctly. If a future milestone wants a
   *std-independent* example dump hash, it must pin the seed's `lib/` to a fixed
   `std_math` or hash only the example-owned functions.
2. **`sqrt` is on no M3 path.** Kept in M2 (spec §3 minimum + future-proof); not
   a mismatch.
3. **`π` not a std symbol.** M3 defines it locally; no M2 surface impact.
