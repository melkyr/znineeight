# z9play M4 — Audio output + ring buffer + Player core — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the application-level audio output layer (vtable + OSS `/dev/dsp` backend + a WAV/null file sink), the double-buffer PCM ring, and the shared `Player` core that drives decode → ring → audio.

**Architecture:** `platform/audio.zig` defines the `AudioOut` vtable (blueprint §2.2); `platform/audio_oss.zig` implements it on Linux OSS; `platform/audio_wavfile.zig` is a hermetic sink that writes the same PCM to a WAV file (used by tests). `player.zig` owns the `Player` struct + `RingBuffer` and the blocking v1 loop (no coroutines).

**Tech Stack:** Z98 (`zig1`, `gcc -m32`, `-fsafe`), `std_file`, `std_arena`, `extern "c"` OSS ioctls (Linux backend only).

**Spec:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding).

**Sequence:** PREVIOUS: `2026-10-11-z9play-m3-audio-decode-plan.md`. NEXT: `2026-10-11-z9play-m5-cli-plan.md`.

## Global Constraints

Same as prior milestones: example-only `examples/z98/z9play/**`; no compiler change; Z98 rules (free functions, `@intCast`, `switch` `else`; NOTE 2026-10-11: compiler defects D1–D6 are FIXED in seed v97 — no workarounds needed for those; but this class of cumulative compiler defects can still surface (e.g. D7, an unqualified type name / `@sizeOf` colliding with a same-named imported type) — if one is hit, STOP-present, apply a minimal example-only workaround, and record it in `examples/torrent_example_defects.md` for a later compiler pass); build `-fsafe`; `edit`/`fastedit` only; **NO push**; git hard rule; plan is the only authority (STOP-present). Reports under `.superpowers/sdd/2026-10-11-z9play-m4-audio-out-plan/`.

## File Structure

- `examples/z98/z9play/platform/audio.zig` — `AudioOut` vtable + `AudioError`.
- `examples/z98/z9play/platform/audio_oss.zig` — Linux OSS `/dev/dsp` backend (best-effort on host).
- `examples/z98/z9play/platform/audio_wavfile.zig` — WAV/null sink (hermetic).
- `examples/z98/z9play/player.zig` — `Player`, `PlayerState`, `RingBuffer`.
- `examples/z98/z9play/tests/tier_audio.sh` — gate.

---

### Task 0: Preflight

- [ ] Confirm the environment: `/dev/dsp` absent ⇒ OSS is best-effort only; the WAV sink is the gate. Confirm M3's decode output contract from its Task 6 review. Record baseline.

### Task 1: Audio vtable + WAV sink

**Interfaces:** `pub const AudioError = error{ OpenFailed, WriteFailed, ConfigUnsupported, DeviceError };` `pub const AudioOut = struct { open_fn, write_fn, close_fn, drain_fn, state };` (sig per blueprint §2.2). `audio_wavfile.open(rate: u32, channels: u8) AudioError!AudioOut` + `write` appends interleaved s16 to a WAV.
- [ ] Unit test: open(44100,2), write N samples, drain/close → file has the 44-byte header + N×2 bytes. Implement. PASS. Commit `example(z9play): audio vtable + WAV sink`.

### Task 2: OSS `/dev/dsp` backend

**Interfaces:** `audio_oss.open/write/close/drain` via `extern "c"` `open`/`ioctl`/`write`/`close` (OSS ioctls `SNDCTL_DSP_*`); configure rate/channels/format; `write` blocks until consumed. On non-Linux or missing device → `OpenFailed` (tests skip with a reason).
- [ ] Build under `-fsafe`; a best-effort host smoke (open `/dev/dsp`; if absent, expect `OpenFailed` cleanly). Commit `example(z9play): OSS /dev/dsp audio backend`.

### Task 3: Player core + ring buffer (`player.zig`)

**Interfaces:** `RingBuffer{data:[]i16, write_pos, read_pos, filled, capacity}`; `Player` per blueprint §3.1; `pub fn playerInit(arena, decoder, audio, meta) !Player`; `pub fn playerPump(p: *Player) !void` (decode one block when room; flush ring to audio when full); `pub fn playerPositionMs(p) u64`.
- [ ] Unit test: with the WAV sink, pump to completion of `sine_stereo_44100.ogg` → WAV bytes equal the M3 `--pcm` output for the same file (byte-identical). Implement. PASS. Commit `example(z9play): Player core + double-buffer ring`.

### Task 4: `tier_audio.sh` gate

- [ ] Build under `-fsafe`; run the player into the WAV sink for each fixture; compare sink bytes to the M3 `--pcm` golden (tolerance per M3) and assert completion + position monotonicity; assert the OSS backend reports `OpenFailed` cleanly when the device is absent. Run PASS. Commit `example(z9play): M4 audio tier`.

**Gate:** `tier_audio.sh` green; ring/double-buffer correct; no device required.

### Task 5: Docs + commit

- [ ] Update `NOTES.md`/`README.md` (audio layer, `--dump-c89` md5). Commit `docs(z9play): M4 audio core`.

### Task 6: Next-milestone amendment review (M5)

- [ ] Read `2026-10-11-z9play-m5-cli-plan.md`. Judge whether M4's `Player` API (pump/position/volume/state) and the audio vtable satisfy the CLI's needs (status line, key handling, volume changes mid-playback, clean stop). If not, **STOP-present** the M5 amendment; else record "no amendment needed".

**Gate:** approved M5 amendment or justified "no amendment needed".
