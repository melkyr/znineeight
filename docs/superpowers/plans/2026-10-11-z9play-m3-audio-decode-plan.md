# z9play M3 — Audio decode to PCM — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decode OGG Vorbis audio packets to interleaved signed-16-bit PCM in pure Z98 (window/IMDCT/overlap-add, floor, residue, mapping/channel coupling), exposed via `z9play --pcm <in.ogg> <out.wav>`.

**Architecture:** Extend the z9play library: `dsp.zig` (window + IMDCT + overlap-add), `floor.zig`, `residue.zig`, `decode.zig` (packet → PCM frames). Consumes `vorbis_setup.zig`/`codebook.zig` (M1) and `std.math` f64 (M2). This is the hardest milestone; it is gated against a third-party decode of the same fixtures.

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_math` (M2), `std_arena`, `std_crypto` (SHA-1), `vorbis-tools` (`oggdec`) for goldens.

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m2-native-math-plan.md`. NEXT: `2026-10-11-z9play-m4-audio-out-plan.md`.

## Global Constraints

Same as prior milestones: example-only `examples/z98/z9play/**`; no compiler change; no seed rotation; Z98 rules (free functions, no generics, `@intCast`, `switch` has `else`; NOTE 2026-10-11: compiler defects D1–D6 are FIXED in seed v97 — no workarounds needed); build `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m3-audio-decode-plan/`.

## Gate note (decoder-equivalence, read before Task 5)

A correct Vorbis decoder need not be **bit-identical** to libvorbis (float rounding differs). The golden is produced by `oggdec` (libvorbis, no-root). The gate therefore compares z9play PCM to the golden with a **bounded tolerance** (per-sample max |Δ| and RMS), **plus** a self-consistency `SHA-1` (3× identical) for determinism. Exact SHA-1 equality with the golden is a **stretch** target, recorded but not required; if the tolerance cannot be met, STOP-present.

## File Structure

- `examples/z98/z9play/dsp.zig` — window slope, IMDCT, overlap-add.
- `examples/z98/z9play/floor.zig` — floor0 (reject in v1) / floor1 decode.
- `examples/z98/z9play/residue.zig` — residue type 0/1/2 decode.
- `examples/z98/z9play/decode.zig` — packet → per-channel floor/residue → IMDCT → overlap-add → interleaved s16.
- `examples/z98/z9play/tests/tier_decode.sh` — gate.
- `examples/z98/z9play/tests/get_vorbis_tools.sh` — already produces `oggdec` (extend if needed).

---

### Task 0: Preflight — golden PCM + baseline

- [ ] Extend `tests/mkfixtures.sh` to also run `oggdec` on each fixture → `testdata/expected/<name>.pcm` (raw s16 interleaved) + record channels/rate/duration. Confirm `oggdec` is in the acquired `vorbis-tools`. Record the baseline.

### Task 1: Window + IMDCT + overlap-add (`dsp.zig`)

**Interfaces:** `pub fn imdct(arena, n: u32, spectra: []const f64, out: []f64) void`; window from blocksize exponents (M1); `pub fn overlapAdd(prev: []f64, cur: []f64, out: []f64) void`.
- [ ] Unit test: an IMDCT of a single non-zero coefficient cross-checks against the analytic basis value (computed with `std.math`). Implement. PASS. Commit `example(z9play): IMDCT + window + overlap-add`.

### Task 2: Floor decode (`floor.zig`)

**Interfaces:** `pub fn decodeFloor1(dt_tables, packet_bits, floor: Floor1, out_curve: []f64) bool` (decode `y` values, `decodeY`/`renderLine` with the `floor1_inverse_dB_table`); floor0 → `error.UnsupportedFloor` in v1.
- [ ] Unit test: floor1 curve monotone/interpolated for a fixture floor; floor0 fixture (if created) → clean error. Implement. PASS. Commit `example(z9play): floor1 decode`.

### Task 3: Residue decode (`residue.zig`)

**Interfaces:** `pub fn decodeResidue(arena, dt_table, packet_bits, residue: Residue, doNotDecode: []bool, ...) !void` — types 0 (with the type-2 end-of-packet rule) and 1 (no interleave); type 2 optional; decode partitioned vectors over the affected channels via the codebook.
- [ ] Unit test: residue decode fills exactly the partitioned ranges; type-0 end flag handled. Implement. PASS. Commit `example(z9play): residue type 0/1/2 decode`.

### Task 4: Packet → PCM (`decode.zig`)

**Interfaces:** `pub fn decodePacket(arena, setup, packet: []const u8, pcm_out: []i16, channels: u8) !usize` — mode select, floor per channel, `nonzero` coupling/mapping, residue per submap, inverse coupling, IMDCT, window, overlap-add, clamp/round to s16. Keep two saved overlap buffers (one per channel).
- [ ] Unit test: decode `sine_stereo_44100.ogg` fully → sample count == golden; max |Δ| vs golden ≤ 2 LSB; RMS ≤ threshold. Implement. PASS. Commit `example(z9play): packet decode to PCM`.

### Task 5: `z9play --pcm` + decode gate

**Files:** `cli.zig`/`main.zig`; `tests/tier_decode.sh`.
- [ ] Add `--pcm <in.ogg> <out.wav>` writing a canonical 44-byte-header PCM WAV. `tests/tier_decode.sh`: for each fixture, decode, compare to `testdata/expected/*.pcm` by tolerance (max |Δ|, RMS) + assert 3× deterministic (SHA-1 of raw PCM identical); report the exact-match SHA-1 vs golden as informational. Run PASS. Commit `example(z9play): M3 --pcm + tier_decode`.

**Gate:** all fixtures decode within tolerance; deterministic; malformed/unsupported → exit 3; `--dump-c89` md5 recorded.

### Task 6: Next-milestone amendment review (M4)

- [ ] Read `2026-10-11-z9play-m4-audio-out-plan.md`. Judge whether M3's `decode.zig` output contract (interleaved s16, framing/block boundaries, how many samples per call, buffering expectations) invalidates M4's `Player`/ring-buffer assumptions. If so, **STOP-present** the M4 amendment; else record "no amendment needed".

**Gate:** approved M4 amendment or justified "no amendment needed".
