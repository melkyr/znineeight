# Task 2 Report — z9play M3 floor decode (`floor.zig` + unit harness)

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m3-audio-decode-plan.md` (Task 2)
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements`
**Commit:** `example(z9play): floor1 decode` (hash in the SDD return)
**Status:** COMPLETE — `floor_test` PASS under `-fsafe`; no regression.

## Deliverables

- `examples/z98/z9play/floor.zig` — Vorbis **floor type 1** decode +
  `renderLine` curve synthesis; floor type 0 rejected with
  `error.UnsupportedFloor`; the 256-entry `floor1_inverse_dB_table` included
  verbatim (spec 10.1).
- `examples/z98/z9play/tests/floor_test.zig` — deterministic unit harness
  (crafted exact vector + zero-floor + floor-0 error + committed-fixture smoke).

Scoped to Task 2 only: floor Y decode, amplitude unwrap, curve synthesis, and
the floor-0 rejection. No residue, mapping/coupling, IMDCT or PCM (Tasks 3–4).

## TDD sequence

1. **RED.** `tests/floor_test.zig` written against the intended
   `floor.decodeFloor1` / `floor.decodeFloor` API before `floor.zig` existed.
2. **GREEN.** `floor.zig` implemented; `-fsafe` compile (0 diagnostics) + link +
   run →
   `floor_test: PASS table=spec+monotone crafted=exact+monotone zerofloor=ok floor0=unsupported fixture=curve`
   Run 3×: byte-identical output (deterministic).

Build/run from the repo root (binding seed recipe, seed v97 at
`/tmp/z9play_seed/zig1_5_clean`):

```
mkdir -p /tmp/ft_out
timeout 120 /tmp/z9play_seed/zig1_5_clean -fsafe -o /tmp/ft_out \
    examples/z98/z9play/tests/floor_test.zig
sh /tmp/ft_out/build_target.sh linux /tmp/ft_out/prog
./tmp/ft_out/prog   # exit 0
```

## Interface (concrete signature chosen)

```zig
pub const FloorError = error{ UnsupportedFloor, BadVersion };

pub const FLOOR1_INVERSE_DB_TABLE: [256]f64 = .{ ... }; // spec 10.1

// Returns true  = floor used (curve rendered into `out_curve`);
//         false = floor unused (nonzero flag clear, or end-of-packet during
//                 curve decode, spec 7.2.3) -> `out_curve` zeroed.
pub fn decodeFloor1(
    arena: *std.arena.Arena,
    tables: []const cbk.DecodeTable,   // codebook k, in setup order
    bits: *vs.BitReader,               // over the audio packet, positioned at floor data
    floor: vs.Floor,                   // M1 floor-1 struct (floor_type == 1)
    out_curve: []f64,                  // length = block size / 2
) FloorError!bool;

// Dispatcher: type 0 -> error.UnsupportedFloor; type 1 -> decodeFloor1.
pub fn decodeFloor(
    arena: *std.arena.Arena,
    tables: []const cbk.DecodeTable,
    bits: *vs.BitReader,
    floor: vs.Floor,
    out_curve: []f64,
) FloorError!bool;
```

`arena` is accepted for signature stability with the other decoder stages and
is unused: the floor-1 x_list is capped at 65 entries (spec 7.2.2) and all
working state (`floor1_Y`/`floor1_final_Y`, the sort order) fits in fixed
`[65]` blocks, so decode allocates nothing and cannot fail with OutOfMemory.

## Algorithm (spec 7.2.3 / 7.2.4 + helpers 9.2.4–9.2.7)

Ported exactly from the Vorbis I specification and cross-checked against
xiph/vorbis `lib/floor1.c` (the reference used by `oggdec`, the golden
generator). No constant was guessed.

1. **nonzero** = 1 bit; clear → unused (return false, zero the curve).
2. **`range` = {256, 128, 86, 64}[multiplier-1]** (spec 7.2.3 step 1), and the
   two initial Y values are read with **`ilog(range-1)`** bits each (steps 2–3).
   I confirmed this precisely against the spec text (`tool` fetch of Vorbis I
   §7.2.3: `[range] = vector { 256, 128, 86, 64 } element
   ([floor1_multiplier]-1)` and `read ilog([range]-1) bits`).
3. **Partitions** (steps 5–19): for each partition, class `c`, `cdim`, `cbits`;
   if `cbits > 0`, decode `cval` from the class masterbook in scalar context;
   for each dimension, `book = subclass_books[c][cval & (csub-1)]`,
   `cval >>= cbits`; a non-negative `book` decodes one Y through it
   (`cbk.decodeScalar`), a negative `book` yields Y = 0. `decodeScalar` treats
   every read past end-of-packet as a 0 bit (it never errors), so for a
   TRUNCATED packet a scalar decode normally still walks the tree and may
   return a valid leaf, rendering a bogus "used" curve; only the no-leaf code
   path returns −1, which maps to unused. A truncated packet is therefore an
   invalid-stream case for the M3 Task 5 gate (tolerance/exit-3), not something
   this stage can reliably detect.
4. **Step 1 unwrap** (spec 7.2.4): `low_neighbor`/`high_neighbor` (spec
   9.2.4/9.2.5, computed over the setup x_list in its natural order), then
   `predicted = render_point(...)` (spec 9.2.6), `highroom`/`lowroom`/`room`,
   and the four-case unwrap. Predicted (zero-difference) points are flagged
   (bit `0x8000`, libvorbis's convention) and skipped in step 2. Integer
   division truncates toward zero (spec 9.2.7).
5. **Step 2 curve synthesis** (spec 7.2.4): sort x_list ascending (selection
   sort; spec guarantees unique x values), render contiguous `render_line`
   segments between successive anchors (`ly` seeded from Y[0]*multiplier),
   then the constant tail `render_line(hx, hy, n, hy)` out to `n`. Each integer
   Y is substituted through `floor1_inverse_dB_table` (clamped to 0..255, as
   libvorbis does for the multiplier-3 overflow); the lookup is applied at each
   sample directly into the f64 output (equivalent to the spec's
   integer-then-substitute form).

## Curve convention consumed by M3 Task 4 (documented in the file header)

- `out_curve.len == block_size / 2` = the number of spectral coefficients
  `dsp.imdct(arena, n, spectra, out)` consumes (`n/2` for transform size `n`).
- Every entry is the linear-domain floor amplitude in **(0, 1]** — already
  includes the `floor1_multiplier` scaling and the table lookup.
- Task 4 forms the channel spectrum by multiplying the decoded residue by
  `out_curve` element by element (spec 4.3.3 / "dot product").
- A `false` return (or floor-0 rejection) means the channel is unused for the
  frame; `out_curve` is zeroed.

## Test coverage (`tests/floor_test.zig`)

1. **Table** — spot-checks (strict equality) against spec 10.1 values at
   indices 0, 20, 46, 80, 127, 128 and 1.0 at 255; asserts strict
   monotonicity across all 256 entries.
2. **Crafted floor 1 (exact)** — a hand-built `Floor1` (multiplier 2,
   rangebits 4, one dimension-1, zero-subclass partition class, one 4-entry
   all-length-2 subclass codebook) plus a hand-written LSB-first packet
   (`nonzero=1`, `Y0=10`, `Y1=40`, subclass codeword `11` → entry 3). The
   expected integer Y at every x is derived by hand from spec 9.2.7
   (`Y=[20,23,26,29,33,36,39,42,46,50,54,58,63,67,71,75,80,80,80,80]`) and
   asserted at every sample; the anchors `out[0]`, `out[8]`, `out[16]` and the
   tail `out[19]` are additionally checked against absolute spec table values
   (`3.7516214e-07`, `1.9282195e-06`, `1.6400004e-05`), so the check is not
   circular. The curve is asserted monotone non-decreasing (monotone between
   anchor points).
3. **Zero floor** — nonzero flag clear → returns `false` and zeroes a
   sentinel-filled output.
4. **Floor 0** — the synthetic floor-0 setup pinned in `setup_test.zig` parses,
   then `decodeFloor` returns `error.UnsupportedFloor`.
5. **Fixture smoke** — `sine_stereo_44100.ogg`: parse the real setup, build all
   decode tables, and decode channel 0's floor for EVERY audio packet from the
   correct bit offset (1-bit packet type, mode bits, long-window window-shape
   bits). Expected mode/spec_len/nonzero values come from an independent
   python3 probe; every one of the 88 audio packets asserts used=true, the
   right spectral length (128 for pkt3, 1024 for the rest), a positive envelope
   in (0,1], and bit-identical re-decode. (Fixed in Fix round 1 — see below.)


## Constraints compliance

- Z98: free functions only, no generics/`anytype`/`@Type`, strict `@intCast`,
  no `switch`, no `@cImport`/externs, pure Z98. D1–D6 not needed (fixed in
  seed v97).
- Example-only (`examples/z98/z9play/**`, plus the SDD report). No compiler or
  seed change. Build under `-fsafe`.
- No push. No destructive git; commit created fresh.

## No regression

Re-built and re-ran the neighboring M3/M1 harnesses with the same seed:
`dsp_test: PASS ...` and
`setup_test: PASS fixtures=5 stereo_codebooks=38 mono_codebooks=35 ...`.
`floor.zig` imports only `vorbis_setup`/`codebook` and is imported by nothing
pre-existing, so existing gates are unaffected.

## Notes / concerns

- The spec's step-2 formulation writes integer Y into an over-allocated vector
  then truncates to `n`; `renderLine` instead clamps each segment to
  `min(x1, n)` (as libvorbis does), so writes never exceed `out_curve.len` and
  the truncate step is a no-op. Output is identical.
- Table values are single-precision literals (as in the spec/libvorbis) parsed
  as f64. Task 4's golden is produced by libvorbis float math, so exact
  bit-equality is not expected; the values match the reference table exactly as
  written.
- `decodeFloor1` returns `false` (unused) when the `nonzero` flag is clear and
  when a scalar book decode returns −1 (a no-leaf code path); it does NOT
  reliably detect a truncated packet, because `decodeScalar` reads every past-
  EOF bit as 0 and usually still reaches a valid leaf. A truncated packet can
  therefore render a bogus "used" curve; that is an invalid-stream case for the
  Task 5 gate, not detectable here. A structurally impossible setup (bad
  codebook index, x_list length, partition overflow) is `BadVersion`.

## Fix round 1

**Review finding (MEDIUM, test defect; decoder correct):** `checkFixtureFloor`
read the mode bit without first consuming the 1-bit Vorbis audio-packet type
flag (spec 4.3.1), so it decoded the floor from a wrong offset and its per-packet
used/unused assertions were unreliable. It also omitted the two window-shape
bits that long windows (mode 1) carry before the floor.

**Fix:** `checkFixtureFloor` now, for every audio packet, reads the 1-bit
packet-type (asserting 0), the `ilog(mode_count-1)` mode bits, and — when the
mode has `blockflag` set — the two window-shape bits, before decoding channel
0's floor. Expected per-packet values were derived independently with a python3
LSB-first OGG-reassembly probe (`/tmp/floor_probe.py`):

- 91 packets total, 88 audio (index 3..90).
- `pkt3`: mode 0 → `spec_len` 128 (blocksize_0 = 256).
- `pkt4..pkt90`: mode 1 → `spec_len` 1024 (blocksize_1 = 2048).
- Every audio packet's floor `nonzero` bit = 1.

The test asserts, for all 88 audio packets, `packet_type == 0`, the exact
expected mode (0 for pkt3, 1 thereafter, which a misaligned offset would fail at
pkt4), the exact expected spectral length, `used == true`, a positive curve ≤ 1,
and bit-identical re-decode from the same offset. The crafted exact vector and
all other checks are unchanged. The decoder (`floor.zig`) was not modified.

**TDD:** RED — the corrected per-packet assertions (mode/spec_len/used) fail on
the old offset. GREEN — with the packed offset the harness passes. The run:
`floor_test: PASS table=spec+monotone crafted=exact+monotone zerofloor=ok
floor0=unsupported fixture=curve`, 3× deterministic; `dsp_test` PASS
(no regression). Seed v97 rebuilt via `scripts/seed/build_from_seed.sh`.

**Report correction:** the earlier claim that a truncated packet maps to
`false`/unused "matching libvorbis goto eop" was inaccurate and is corrected in
place above: `decodeScalar` reads every past-EOF bit as 0, so a truncated packet
usually still reaches a valid leaf and can render a bogus "used" curve; only the
no-leaf path returns −1. Truncation is an invalid-stream case for the Task 5
gate, not reliably detectable at this stage.

