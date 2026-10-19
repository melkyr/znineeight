# z9play M9 — Streaming Playback — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make z9play's OGG Vorbis and FLAC playback independent of track size. Replace whole-file `readAll`/`reassemble`/`flac.open(bytes)` with incremental file, page, packet, and frame readers. The player must never hold an entire media track in one buffer.

**Architecture:** `stream.zig` provides a 64 KiB buffered file over `std_file`. `ogg_stream.zig` reads OGG pages incrementally, verifies CRC, assembles one bounded packet at a time, and provides a tail-only duration scan. `player.VorbisCtx` consumes packets from the stream instead of a packet array. `flac.StreamFlacDecoder` reads metadata and frames from the same buffered file (the byte-slice `flac.FlacDecoder` stays as a test oracle). `main.zig` and `ui.zig` stop using `readAll` for media; all modes (`--info`, `--dump-setup`, `--pcm`, `--wav`, interactive, TUI) stream. No compiler or std changes.

**Tech Stack:** Z98 seed v102 (`zig1`, `gcc -m32`, `-fsafe`), `std_file` (`open`/`read`/`seek`/`size`/`close`), existing OGG/Vorbis/FLAC decoders, `Player` ring, existing tiers.

**Spec:** `docs/superpowers/specs/2026-10-19-z9play-streaming-playback-design.md` (binding).
**Base design:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding except where the M9 spec extends it).
**Sequence:** M9, after M8. **NEXT:** none defined; z9torr M6 remains the next example milestone per the M8 handoff.

## Global Constraints

- Example-only: `examples/z98/z9play/**` plus tests/docs under that tree. **No `sf/**` change.** No compiler change. No seed rotation. If a compiler/std change seems necessary, STOP-present before touching it.
- Base seed **v102**: archive md5 `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`. Current defects: **D1/D2 FIXED**, **D3/D4/D5 OPEN** (`examples/torrent_example_defects.md`). Do not claim “D1–D8 all FIXED”.
- Z98 rules: free functions, no generics/`anytype`, no method syntax, strict `@intCast`, typed string literals, `if/else` where the codebase avoids `switch`; `-fsafe`; `edit`/`fastedit` only; read the region before editing; bottom-to-top.
- **No push.** No reset/checkout/restore/clean/stash-drop/force-push. Leave untracked `run.err`/`run.out` and dirty `progress.md` alone; the controller owns the ledger.
- Plan is the only authority. Better alternative/ambiguity → STOP-present (`I found the intention is X, but this is impossible given Y`).
- Reports under `.superpowers/sdd/2026-10-19-z9play-streaming-playback-plan/`. Commit code as `example(z9play): ...`; reports as `docs(sdd): ... report`; docs as `docs(z9play): ...`. `git add -f` explicit paths for ignored reports.
- Do not commit the operator's `lin_bin/*.ogg` or personal media. `lin_bin/` is an untracked output directory.

## File Structure

- `examples/z98/z9play/stream.zig` — new: `BufferedFile` over `std_file`.
- `examples/z98/z9play/ogg_stream.zig` — new: incremental pages, packets, tail granule.
- `examples/z98/z9play/player.zig` — `VorbisCtx` consumes `*OggStream`.
- `examples/z98/z9play/flac.zig` — file-backed `openStream`/`decode`; keep byte-slice API for tests.
- `examples/z98/z9play/decoder.zig` — selector unchanged in shape; FLAC/Vorbis adapters use streaming contexts.
- `examples/z98/z9play/main.zig` — incremental CLI modes and `--pcm` streaming.
- `examples/z98/z9play/ui.zig` — streaming `playTrack`; stream arena replaces file arena.
- `examples/z98/z9play/tests/stream_test.zig` — `BufferedFile` unit tests.
- `examples/z98/z9play/tests/ogg_stream_test.zig` — page/packet/tail tests vs `ogg.reassemble`.
- `examples/z98/z9play/tests/flac_test.zig` — add file-stream test; keep byte-slice oracle.
- `examples/z98/z9play/tests/make_large_ogg.py` — deterministic large-file fixture generator.
- `examples/z98/z9play/tests/tier_stream.sh` — new gate.
- `examples/z98/z9play/NOTES.md`, `README.md` — streaming behavior and current pins.

---

### Task 0: Preflight — anchors, call-site census, stream API reality check

**Purpose:** Freeze the baseline and prove the planned APIs exist before writing code.

- [ ] Read `sf/src/std_file.zig` `File`/`open`/`read`/`seek`/`size`/`close`, `examples/z98/z9play/ogg.zig`, `flac.zig`, `player.zig`, `decoder.zig`, `main.zig`, `ui.zig`.
- [ ] Record exact anchors for every media `readAll`, `ogg.reassemble`, `ogg.lastGranule`, `flac.open`, `flac.decode`, `player.vorbisCreate`, and `decoder.detectKind` call site.
- [ ] Record both `FILE_ARENA_SIZE` declarations and every arena used for media bytes.
- [ ] Verify on seed v102 with a disposable probe: `std_file.open` + `read` + `seek` + `size` on a >4 MiB file works; `read` returns short only at EOF; `seek` accepts `u64`-range offsets via `i64` conversion.
- [ ] Record OGG fixture page sizes and max packet sizes from `repro`/testdata; confirm `OGG_PAGE_MAX = 65,307` and that 1 MiB packet cap exceeds every committed packet.
- [ ] Record the current tier baselines and dump pins: `tier_info` 20/0, `tier_setup` 21/0, `tier_cli` 23/0, `tier_tui` 40/0, `tier_audio` 27/0, `tier_flac` 59/0; `main`/`ui` dump pins from M8 T4 (`e56af7916edd199e796f3ef11d5e49c4` / `22676fd997471df1c4c3a3f04397121d`).
- [ ] STOP-present if `std_file` cannot read/seek a >4 MiB file on the seed, or if any committed Vorbis packet exceeds 1 MiB.

**Deliverable:** `task-0-report.md` with the census, anchors, probe commands/output, and baseline. No source edits. Commit `docs(sdd): M9 T0 preflight report`.

**Precision requirements:** every claim has `file:line`; the >4 MiB probe states the compiler/seed and exact command; no assumption that `readAll`/`reassemble` can stay in production.

---

### Task 1: `stream.zig` — bounded buffered file

**Interfaces (exact):** see M9 spec §4.1.

- [ ] Add `examples/z98/z9play/stream.zig` with `BufferedFile`, `StreamError`, and the seven free functions from the spec.
- [ ] Buffer size `STREAM_BUF_SIZE = 64 * 1024`; allocate `buf` from the caller arena; `open` uses `std_file.open(arena, path, .Read)`.
- [ ] `bufferedFileReadByte`: refill when `pos == len`; return `null` at EOF.
- [ ] `bufferedFileRead`: copy available bytes; refill and continue until `out` is full or EOF; return the count (0 at EOF); never allocate.
- [ ] `bufferedFileSeek`: `std_file.seek` to `@intCast(i64, offset)`, reset `start/len/pos`.
- [ ] `bufferedFileClose`: close and make a second close a no-op (guard on `file.handle`).
- [ ] `bufferedFileTell`: file offset of `buf[pos]`; `bufferedFileSize`: `std_file.size` (cached in `File`).
- [ ] Add `tests/stream_test.zig`: create a >4 MiB temp file, read across buffer boundaries, `readByte` at EOF, `seek` backwards/forwards, `tell`, short `read`, and confirm no allocation beyond the fixed buffer.
- [ ] Compile/run the test with the seed and emitted `build_target.sh linux`.

**Gate:** test PASS; no frontend behavior change yet. Commit `example(z9play): bounded buffered file stream`.

**Precision requirements:** define whether `BufferedFile` owns `std_file.File` by value (yes) and whether the arena must outlive it (yes, document in comments); state exact EOF/short-read semantics; do not use `readAll`.

---

### Task 2: `ogg_stream.zig` — incremental OGG pages and packets

**Interfaces (exact):** see M9 spec §4.2.

- [ ] Add `ogg_stream.zig` with `OGG_PAGE_MAX = 27 + 255 + 65025 = 65307`, `OGG_PAGE_BUF = 65536`, `OGG_PACKET_MAX = 1024 * 1024`.
- [ ] Page read: read 27-byte header, parse `nseg`, read segment table + body, require `27 + nseg + body <= OGG_PAGE_BUF`, verify capture/version/length, reuse `ogg.crcOk` on the page buffer.
- [ ] Maintain `serial` from the first page; reject a page with a different serial (`SerialMismatch`); reject a non-continuation page while a packet is pending and a continuation page with no pending packet.
- [ ] `nextPacket`: walk segment laces; append body bytes to the packet buffer; `<255` terminates and returns `packet[0..len]`; `255` continues across pages. Reject `packet_len + lace > OGG_PACKET_MAX`.
- [ ] `oggStreamLastGranule`: open a second read handle, read at most 256 KiB from EOF, find the last complete page for `serial`, return its granule; handle a page straddling the tail window by expanding backwards (bounded by file size) or returning `Truncated`.
- [ ] Add `tests/ogg_stream_test.zig`: for every committed OGG fixture, compare every streamed packet byte-for-byte with `ogg.reassemble`; compare `lastGranule` with `ogg.lastGranule`; synthetic tests for CRC failure, continuation, `PacketTooLarge`, serial mismatch, and EOF mid-page.
- [ ] Run the tests under `-fsafe`.

**Gate:** unit tests PASS; `ogg.reassemble`/`lastGranule` remain only as test oracles. Commit `example(z9play): incremental OGG packet stream`.

**Precision requirements:** state packet-buffer lifetime (until next `nextPacket`); verify CRC over the page bytes with the CRC field zeroed; no full-file reads; tail scan uses a bounded buffer and never mutates the decode cursor.

---

### Task 3: FLAC file-backed streaming

**Purpose:** Land the second codec's stream path before the frontends switch, so Task 4 can remove `readAll` in one step.

- [ ] Add `flac.StreamFlacDecoder` per spec §4.4: `bf: *stream.BufferedFile`, metadata fields, fixed `samples`, `eof`; keep `flac.FlacDecoder`/`open(arena, bytes)`/`decode` **unchanged** as the byte-slice test oracle.
- [ ] `openStream` parses `fLaC` + metadata with bounded reads; `decodeStream` uses a file-backed MSB bit reader and reads the frame header/subframes/CRC-16; `closeStream` closes the file.
- [ ] `decoder.zig`: add a `StreamFlacDecoder` arm/adapter (`flacStreamNext`) without changing the existing vtable shape or D8 pointer discipline.
- [ ] `tests/flac_test.zig`: add a file-stream test; compare decoded PCM/frames with the byte-slice path (max_delta 0 for the committed fixture); keep 3× determinism.
- [ ] Run `tier_flac` 59/0; keep the byte-slice oracle test green.

**Gate:** FLAC streaming exact; no FLAC `readAll` in production after Task 4; `tier_flac` green. Commit `example(z9play): stream FLAC frames`.

**Precision requirements:** metadata block lengths are bounded and skipped without allocation; frame CRC-16 may remain skipped (as M8) but must be read; `max_block` scratch stays fixed; no per-frame growth; `openStream` failure closes the file.

---

### Task 4: Vorbis streaming + `main.zig` all modes

**Purpose:** Switch the CLI from whole-file reads to streams for both codecs, including `--pcm`.

- [ ] Change `player.VorbisCtx` to the spec §4.3 shape: replace `packets`/`next_packet` with `stream: *ogg_stream.OggStream`; remove the old `first_packet` argument.
- [ ] `vorbisCreate(persistent, scratch, stream, setup, state, sample_rate, channels, total_frames)`.
- [ ] `vorbisNext`: `oggStreamNextPacket(c.stream)`; `null` → 0; decode packet; map `PacketTooLarge`/CRC/Truncated to `DecodeFailed`; reset scratch per packet.
- [ ] `decoder.zig`: `decoderOpenVorbis(out, vc)` unchanged in shape; no packet array.
- [ ] `main.zig`: replace the initial `readAll` with `BufferedFile`: read 4 bytes for `detectKind`, seek to 0, then dispatch.
- [ ] OGG `--info`: stream id/comment/setup packets; parse tags/id; `oggStreamLastGranule`; print exactly as today.
- [ ] OGG `--dump-setup`: stream the three headers; print counts; no audio.
- [ ] OGG `--pcm`: open the output with `std_file.open(.Write)`, write a 44-byte WAV header with zero sizes, decode packets incrementally, write PCM bytes (little-endian s16), then seek to offsets 4 and 40 and patch RIFF/data sizes. Reject >4 GiB payloads explicitly.
- [ ] OGG `--wav`/interactive: create `VorbisCtx` from the stream; `Player` unchanged.
- [ ] FLAC `--wav`/interactive: use `flac.openStream` (Task 3); no `readAll`.
- [ ] Preserve exit codes 0/1/2/3/4/5 and existing messages; map read/CRC/packet errors to the existing decoder/“corrupt” exit.
- [ ] Add a `--pcm` golden check: output byte-identical to the committed golden for the existing fixture.

**Gate:** `tier_info` 20/0, `tier_setup` 21/0, `tier_cli` 23/0; `--pcm` byte-exact; no `readAll` in `main.zig`. Commit `example(z9play): stream CLI modes`.

**Precision requirements:** WAV header patching uses `seek` and writes exactly 4 bytes at offsets 4 and 40; 32-bit size fields are checked for overflow; the output file is closed on decode failure; `--info` does not decode audio; header packets are consumed exactly once; the stream outlives `VorbisCtx`/`Player`.

---

### Task 5: `ui.zig` streaming TUI

- [ ] Replace `g_file_arena`/`readAll` with a stream arena sized for `BufferedFile` (64 KiB) + page (64 KiB) + packet (1 MiB) + header/tag copies + slack; keep `g_dec_arena`, `g_scratch_arena`, `g_player_arena`.
- [ ] Add per-track stream state: `g_ogg_stream`, `g_flac`, `g_stream_open`; open in `playTrack`, close in `stopPlayback` and on every failure.
- [ ] OGG: stream headers; parse id/comment/setup; tail granule; create `VorbisCtx`; metadata as today.
- [ ] FLAC: `flac.openStream`; metadata; selector.
- [ ] Keep the TUI layout/keys/status unchanged; status errors distinguish “cannot open”, “unsupported”, “out of memory” where practical.
- [ ] Add/extend a TUI test that plays a fixture and confirms `Now:`/`Ended`; run `tier_tui` 40/0.

**Gate:** `tier_tui` 40/0; no `readAll`/`reassemble` in `ui.zig`; stream closes on track change/`d`/`q`. Commit `example(z9play): stream TUI playback`.

**Precision requirements:** the stream/decoder lifetime spans `playTrack`; `stopPlayback` is idempotent; no reset of an arena that owns the live stream; file handle leaks checked by repeated play/stop.

---

### Task 6: Large-file gate, `lin_bin` rebuild, docs

- [ ] Add `tests/make_large_ogg.py`: parse the committed 2 s OGG fixture; emit a valid single-stream OGG ≥64 MiB by repeating audio pages with monotonic sequence numbers, correct granule positions, EOS on the last page, and recomputed CRCs. It must not use a third-party OGG library. Include a `--size` argument and deterministic output.
- [ ] Add `tests/tier_stream.sh`:
  - build `main.zig`/`ui.zig` `-fsafe`;
  - run the existing tiers (info/setup/cli/tui/audio/flac);
  - run `--info` on the ≥64 MiB generated OGG under a virtual-memory limit that fails a full-file allocation (document the exact `ulimit -v`; choose a value that still runs the 32-bit streaming binary);
  - assert exit 0, rate/channels, duration; assert `--pcm` on a small fixture is byte-exact;
  - optional: if `Z9PLAY_LARGE_OGG` is set, run `--info` on the operator's real track; never commit it.
- [ ] Rebuild `lin_bin/z9play-console` from the final `ui.zig` using seed v102 and `build_target.sh linux`; verify under pty with the 8,205,755-byte track (status/playing; no “cannot open track”).
- [ ] Update `lin_bin/instructions.txt` (no file-size caveat; bounded memory; mention 32-bit build).
- [ ] Update `NOTES.md`/`README.md`: streaming playback, no whole-track buffer, `--pcm` streamed, new stream/OGG/FLAC APIs, current dump pins, seed v102 unchanged, D3/D4/D5 OPEN, Win9x hardware pending.

**Gate:** `tier_stream.sh` PASS; all prior tiers green; the operator's 8.2 MB track plays in the TUI; `lin_bin` rebuilt. Commit `example(z9play): streaming playback tier + large-file gate` and `docs(z9play): streaming playback`; rebuild output stays untracked unless the operator asks.

**Precision requirements:** large OGG is genuinely valid (CRC, sequence, granule, EOS); the memory limit is justified and reproducible; no full media allocation in the test path; instructions do not claim a file-size cap that the implementation no longer has; no compiler seed rotation.

---

### Task 7: Final review / handoff

- [ ] Run the full M9 gate once from a clean tree: `tier_stream`, `tier_flac`, `tier_cli`, `tier_tui`, `tier_audio`, `tier_info`, `tier_setup`.
- [ ] Confirm no production `readAll`/`ogg.reassemble`/`flac.open(bytes)` remains (test-only oracles allowed; grep and report exact hits).
- [ ] Confirm no `sf/**` change and seed v102 unchanged.
- [ ] Write `task-7-report.md` with commands, observed outputs, remaining risks, and the deferred list.
- [ ] Review the diff against the M9 spec; fix or STOP-present.

**Gate:** report complete; no open Critical/Important; no push. Commit `docs(sdd): M9 final handoff report`.

---

## Task precision summary (review checklist)

| Task | Must be decided before coding | Evidence required |
|---|---|---|
| T0 | Exact std_file semantics; all call sites; packet caps | Probe + `file:line` census |
| T1 | `BufferedFile` ownership/EOF/seek semantics | Unit test with >4 MiB file |
| T2 | Page/packet cursor, CRC, continuation, tail window | Packet equality vs `reassemble` |
| T3 | File-backed FLAC bit reader; metadata skip bounds | `tier_flac` + oracle equality |
| T4 | Vorbis header consumption; mode-by-mode streaming; WAV patching; exit codes | Tier + `--pcm` byte compare |
| T5 | TUI stream lifetime/close paths | `tier_tui` + repeated play/stop |
| T6 | Large OGG validity + memory limit | `tier_stream` under `ulimit -v` |
| T7 | No hidden whole-file path; seed untouched | grep + full gate |

## Risks

1. Packet >1 MiB: clean reject; test the bound.
2. FLAC frame boundary without a full frame buffer: the file bit reader is byte-oriented and sequential; no rewind is needed.
3. `--pcm` WAV size patching on 32-bit: reject >4 GiB output explicitly.
4. Tail granule when the last page straddles the 256 KiB window: expand/retry; never scan the whole file.
5. TUI file handle lifetime: close on track change, `d`, `q`, and all failure paths.
6. No compiler/std/seed change. Win9x remains design-verified; hardware verification operator-pending.

## Out of scope

- Network streaming, chained/multiplexed OGG, sample-accurate seeking, resumed playback, playlist persistence.
- mmap/PAL work.
- Changing the OGG/Vorbis/FLAC decode algorithms.
- Any compiler or std change.
