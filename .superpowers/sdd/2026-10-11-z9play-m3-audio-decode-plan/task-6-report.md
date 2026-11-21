# Task 6 Report — z9play M3 next-milestone (M4) amendment review + M3 closeout

**Plan:** `docs/superpowers/plans/2026-10-11-z9play-m3-audio-decode-plan.md` (Task 6 + Global Constraints)
**Next plan reviewed:** `docs/superpowers/plans/2026-10-11-z9play-m4-audio-out-plan.md`
**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md`
**Repo:** `/workspace/znineeight` **Branch:** `zig1_improvements` **No push.**
**Commit:** `docs(z9play): M3 closeout + M4 amendment review` (hash in the SDD return)

**Status:** COMPLETE — Part A: no amendment needed. Part B: M3 closed out; all gates re-run green.

## Part A — M4 amendment review — **no amendment needed**

### What M3's `decode.zig` contract actually is

`examples/z98/z9play/decode.zig`:

```zig
pub const DecoderState = struct { ... };  // codebook tables, block sizes,
                                          // prev_n, per-channel overlap tail, scratch
pub fn initDecoderState(arena, setup, channels: u8, bs0_exp: u8, bs1_exp: u8) DecodeError!DecoderState;
pub fn decodePacket(arena, setup, state: *DecoderState, packet: []const u8, pcm_out: []i16) DecodeError!usize;
```

- **One audio packet per call.** `decodePacket` parses one packet's mode/window
  bits, floors, residues, inverse coupling, IMDCT, window + overlap-add, and
  writes finished **interleaved s16 L,R,…** into the caller's `pcm_out`.
- **Returns frames (samples per channel) this packet produced.** `pcm_out` must
  hold `frames*channels` i16. The **priming packet returns 0** (it only seeds the
  overlap tail); later packets return a variable count (short/long block sized).
- **Caller-owned `*DecoderState`.** All cross-packet state — the built
  codebook decode tables, previous block size, and the per-channel windowed
  overlap tail — lives in the caller's struct, which is arena-sized once and
  does not grow through this struct across a stream.
- **Framing/block boundaries are internal.** Each call consumes exactly one Ogg
  audio packet; block size and window flags come from the packet's mode. There is
  no framing assumption the caller must satisfy beyond "one packet per call".

The M3 T5 reviewer's observation is correct and confirmed by reading the code:
`decode.zig` is already **streaming-capable**. The only whole-stream buffering is
in `examples/z98/z9play/main.zig`'s `--pcm` path (`big: []i16` sized
`audio_packets * blocksize_1/2 * channels`, plus the dedicated 16 MiB
`dec_arena_buf`), a CLI convenience that decodes every packet in a loop and then
trims to the stream granule at write time.

### Why this does not invalidate M4's `Player` / ring-buffer / audio-out assumptions

M4 (`player.zig` Task 3) is specified as: `playerPump(p) !void` "decode one block
when room; flush ring to audio when full" with a double-buffer ring, and its unit
test pumps `sine_stereo_44100.ogg` to completion and asserts the WAV-sink bytes
are **byte-identical** to M3's `--pcm` output for the same file.

That is exactly what M3's contract supports:

1. **Per-packet drive.** `playerPump` calls `decodePacket` once per audio packet;
   a returned `0` (priming) is just a `0`-sample append, and any `frames*channels`
   is appended to the ring. Variable per-packet framing is absorbed by the loop.
2. **Byte-identical sink.** M3's `--pcm` path *itself* drives `decodePacket`
   packet-by-packet with a single `DecoderState` (main.zig:280–294). A ring that
   concatenates the same per-packet outputs, in the same order, with the same
   state, reproduces the identical PCM sequence — so M4's Task 3 byte-identity
   target holds without any change to the M3 contract.
3. **Granule trim.** M3 trims to `ogg.lastGranule` at WAV-write time; M4 owns the
   same length/duration bookkeeping in its `Player` fields
   (`duration_ms`/`position_ms`), matching the spec §4 field list. No contract
   change needed.
4. **No new std/build/gate dependency.** M4 adds `platform/audio.zig` etc.; it
   consumes `decode.zig` unchanged. M3 added no std surface (M2's
   `sqrt`/`sin`/`cos` already cover it), so M4's Global Constraints are intact.

### Non-assertion note (flagged, not an amendment)

M3's Task 4/5 reports flag that `residue.zig`'s `entryToVector` allocates
per-codeword vectors from the arena, so a *long-running* player over a full song
should reset a per-packet scratch arena or reuse buffers rather than accumulate.
M4's unit gate pumps a 2 s fixture, so this does not block M4, and M4's plan
already scopes its gate as fixture-completion; the note is recorded here and in
`NOTES.md`. It is a performance/memory consideration, not an invalidation of
M4's `Player`/ring/audio-out assumptions.

**Verdict: no amendment to the M4 plan is required.** (Recorded "no amendment
needed" per the spec §9 amendment rule.)

## Part B — M3 closeout

### Docs pinning

- `examples/z98/z9play/NOTES.md` **working commit pinned to `c7af78ac`**
  (`example(z9play): M3 --pcm + tier_decode`), with prior closeouts
  (M2 `b5ca08d2`, M1 `100c35ce`, M0 `27b1fddf`) and the full M3 decode chain.
- M3 `--dump-c89` md5 `a5f208b5c8034e9c9f2be9c6800913f4` and the binding build
  recipe are recorded in **both** `NOTES.md` (build recipe §, md5 note) and
  `README.md` (Build and Run §, Notes §).
- `NOTES.md`/`README.md` M3 status updated to "complete and closed out
  (Tasks 0–6)" + a Task 6 closeout log entry.

### Final gates (re-run under seed v97, `-fsafe`, example-only)

Seed build (binding recipe `scripts/seed/build_from_seed.sh
release/seed/zig1-seed.tgz /tmp/z9play_seed`):

```
[seed] hop2 binary md5: bafbba9454cd2b134bdc3d50c65384e0
[seed] two-hop closure OK: hop1 == hop2 == bafbba9454cd2b134bdc3d50c65384e0
```

| gate | result |
|:--|:--|
| `tests/tier_decode.sh` | **24 passed, 0 failed** — `TIER_DECODE PASS` |
| `tests/tier_info.sh` | **20 passed, 0 failed** — `TIER_INFO PASS` |
| `tests/tier_setup.sh` | **21 passed, 0 failed** — `TIER_SETUP PASS` |
| `tests/tier_math.sh` | **8 passed, 0 failed** — `TIER_MATH PASS` |

Unit tests (seed-built + linked, run from repo root):

```
ogg_test:     PASS pages=4 last_granule=88200 packets=91
info_test:    PASS channels=2 sample_rate=44100 blocksize_0=8 blocksize_1=11
setup_test:   PASS fixtures=5 stereo_codebooks=38 mono_codebooks=35 cb0_dim=1 cb0_entries=64 ordered=ok lookup2=ok cbtables=ok setup=ok
dsp_test:     PASS imdct=analytic window=closed+tdac vwin64=ok overlap=ok deterministic=ok
floor_test:   PASS table=spec+monotone crafted=exact+monotone zerofloor=ok floor0=unsupported fixture=curve
residue_test: PASS type0=exact type1=exact type2=deinterleave eop_empty=zero eop_partial=stop dnd=skip
decode_test:  PASS frames=88640 golden_frames=88200 max_delta=1 rms_milli=36 sha1=f891394376e3012753ddcb6e4a18cf1cfe321b14 deterministic=3x
```

`--dump-c89` md5 confirmed:

```
a5f208b5c8034e9c9f2be9c6800913f4  -   (stable)
```

Seed closure: `bafbba9454cd2b134bdc3d50c65384e0` (unchanged; M3 is example-only,
no compiler/seed rotation).

## Constraints compliance

- Example-only (`examples/z98/z9play/**`) plus the SDD report path; no compiler
  or seed change; no seed rotation. Build under `-fsafe`.
- **No push.** No destructive git; no amend needed in this task.
- Edits via `edit` (AGENTS.md X.7). No new compiler defect encountered.

## Notes / concerns

- `decode_test` emits 88640 frames vs the 88200-frame golden (final-page granule
  padding, < one block); `--pcm` trims to the granule at write time. M4 must do
  the equivalent length/duration bookkeeping in the `Player` (already in its
  field list).
- The per-codeword residue arena scratch noted above is the one long-run memory
  consideration for M4; it does not alter M4's contract.
