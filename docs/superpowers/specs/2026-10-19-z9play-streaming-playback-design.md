# z9play M9 — Streaming Playback — Design

**Status:** Approved direction (operator, 2026-10-19: option **C**, streaming/mmap)
**Goal:** Play OGG Vorbis and FLAC files of arbitrary practical size with **bounded memory**. The player must never allocate or read an entire media track into one buffer. File bytes are consumed incrementally; only the current OGG page, one packet, decoder tables, and the PCM ring are resident.
**Base design:** `docs/superpowers/specs/2026-10-11-z9play-ogg-player-design.md` (binding except where this document explicitly extends it).
**Plan:** `docs/superpowers/plans/2026-10-19-z9play-streaming-playback-plan.md`.
**Sequence:** M9, after M8. Base seed: v102 (archive md5 `702f34d87b7e6bf401dd206d2517dbee`, fixed point `b299b4b435e624d0ddbd2edde681cbc3`).

## §1 Problem

The M5/M7/M8 frontends call `std_file.readAll` and then `ogg.reassemble` (which copies every packet) or `flac.open` (which slices the full file). `ui.zig` and `main.zig` both reserve a 4 MiB file arena. A valid 8,205,755-byte OGG therefore fails with `OutOfMemory`, surfaced as “cannot open track” (`ui.zig:487-489`). The same limit affects the CLI and FLAC.

Raising the arena is not acceptable: it scales with track size and defeats the player's bounded-memory design.

## §2 Scope

**In scope:**
- Incremental file reading (`BufferedFile`) over `std_file` (`open`/`read`/`seek`/`size`/`close`).
- Incremental OGG page parsing and packet assembly for the existing single-logical-stream Vorbis subset.
- Incremental Vorbis decode: the decoder pulls one packet at a time from the stream.
- Incremental FLAC decode: metadata and frames are read from the file; the existing subframe/Rice/decorrelation logic is reused.
- All frontend modes:
  - `--info`: headers + tail granule only.
  - `--dump-setup`: headers only.
  - `--pcm`: decode to a file incrementally; write the WAV header first, patch sizes at end.
  - `--wav` / interactive CLI / TUI: stream through `Player`.
- Duration via a bounded tail scan (last OGG page), not a full-file scan.
- Linux and Win9x (`std_file` only; no mmap/PAL addition).
- A large-file regression gate proving a media file far larger than any arena can be inspected without loading it.

**Out of scope (unchanged from the base design):**
- Network streaming, chained/multiplexed OGG, seeking by granule, persistent playlists, tag editing.
- Changing the OGG/FLAC/Vorbis bitstream semantics.
- New compiler features or `sf/**` changes.
- Memory-mapping as the implementation mechanism. mmap was considered; it does not solve the problem by itself because packet reassembly and FLAC frame access still copy the stream. `std_file` streaming is portable to Win9x and keeps the design testable.

## §3 Memory model

Fixed, file-size-independent budgets:

| Buffer | Size | Owner |
|---|---:|---|
| `BufferedFile` read buffer | 64 KiB | stream/decoder arena |
| OGG page buffer (max page = 27 + 255 + 65025 = 65,307 B) | 65,536 B | stream arena |
| OGG packet assembly buffer | 1 MiB (`OGG_PACKET_MAX`) | stream arena |
| Tail-scan buffer | 256 KiB | temporary/stream arena |
| FLAC frame bit reader | no frame-sized buffer; reads through `BufferedFile` | decoder arena |
| Vorbis decoder tables / scratch | unchanged (M1/M3) | decoder/scratch arenas |
| PCM ring | unchanged (M4) | player arena |

The 4 MiB “file arena” is removed from media paths. Metadata arenas may remain (setup/comment/ID and tag copies); they no longer scale with file size. `OGG_PACKET_MAX` is a correctness bound, not a memory target: a packet larger than 1 MiB is rejected with a clean `PacketTooLarge` error (the Vorbis headers and audio packets in the supported subset are far below it).

## §4 Interfaces

### §4.1 `examples/z98/z9play/stream.zig` (new)

Pure Z98 free functions; no generics.

```zig
pub const StreamError = error{ OpenFailed, ReadFailed, SeekFailed, SizeFailed, OutOfMemory };

pub const BufferedFile = struct {
    file: std_file.File,
    arena: *std.arena.Arena,
    buf: []u8,        // 64 KiB
    start: u64,       // file offset of buf[0]
    len: usize,       // valid bytes in buf
    pos: usize,       // next byte in buf
    closed: bool,     // close is idempotent
};

pub fn bufferedFileOpen(arena: *std.arena.Arena, path: []const u8) StreamError!BufferedFile;
pub fn bufferedFileClose(bf: *BufferedFile) void;
pub fn bufferedFileReadByte(bf: *BufferedFile) StreamError!?u8; // null = EOF
pub fn bufferedFileRead(bf: *BufferedFile, out: []u8) StreamError!usize; // 0 = EOF
pub fn bufferedFileSeek(bf: *BufferedFile, offset: u64) StreamError!void;
pub fn bufferedFileTell(bf: *BufferedFile) u64;
pub fn bufferedFileSize(bf: *BufferedFile) u64;
```

Semantics:
- `bufferedFileRead` returns short only at EOF or when `out.len` exceeds the remaining file; it refills as needed until `out` is full or EOF.
- `bufferedFileSeek` resets the buffer; `Tell` reports the file offset of `buf[pos]`.
- Close is idempotent; all allocation comes from `arena`.

### §4.2 `examples/z98/z9play/ogg_stream.zig` (new)

```zig
pub const OggStreamError = error{
    BadCapture, BadVersion, Truncated, Crc, OutOfMemory,
    PacketTooLarge, SerialMismatch,
};

pub const OggStream = struct {
    bf: stream.BufferedFile,
    page: []u8,          // 65,536
    page_len: usize,
    page_seg: usize,
    page_body: usize,
    packet: []u8,        // 1 MiB
    packet_len: usize,
    serial: u32,
    have_serial: bool,
    // ...page/segment cursor fields...
};

pub fn oggStreamOpen(arena: *std.arena.Arena, path: []const u8) OggStreamError!OggStream;
pub fn oggStreamClose(s: *OggStream) void;
pub fn oggStreamNextPacket(s: *OggStream) OggStreamError!?[]const u8;
pub fn oggStreamLastGranule(arena: *std.arena.Arena, path: []const u8, serial: u32) OggStreamError!u64;
```

Semantics:
- Pages are read one at a time; the 27-byte header, segment table, and body must fit the page buffer. CRC-32 is verified per page using the existing `ogg` polynomial.
- `nextPacket` returns a slice valid until the next call. Lacing values `<255` terminate a packet; `255` continues (including across pages). A packet larger than `OGG_PACKET_MAX` is `PacketTooLarge`.
- The first page's serial becomes the stream serial; subsequent pages with a different serial are `SerialMismatch` (multiplexed/chained is out of scope).
- `oggStreamLastGranule` opens a separate read handle, reads at most the last 256 KiB, locates the last complete page for `serial`, and returns its granule. It does not consume the decode stream. If no page is found, return `0`? No: return `Truncated` unless the file is empty (callers map to duration 0).
- The existing `ogg.reassemble` and `ogg.lastGranule` remain for unit tests only; production frontends must not call them.

### §4.3 `player.VorbisCtx` (changed)

```zig
pub const VorbisCtx = struct {
    scratch: *std.arena.Arena,
    setup: vs.Setup,
    state: dec.DecoderState,
    stream: *ogg_stream.OggStream, // replaces packets/next_packet
    tmp: []i16,
    max_frames: u32,
    sample_rate: u32,
    channels: u8,
    total_frames: u64,
};

pub fn vorbisCreate(
    persistent: *std.arena.Arena,
    scratch: *std.arena.Arena,
    stream: *ogg_stream.OggStream,
    setup: vs.Setup,
    state: dec.DecoderState,
    sample_rate: u32,
    channels: u8,
    total_frames: u64,
) DecoderError!*VorbisCtx;
```

`vorbisNext` pulls one packet at a time (`oggStreamNextPacket`), resets `scratch` per packet, and calls `dec.decodePacket` unchanged. The three header packets are consumed by the frontend before `vorbisCreate`; the stream cursor then points at the first audio packet. `total_frames` is the tail-scan granule.

### §4.4 `flac.StreamFlacDecoder` (new; byte-slice API stays)

The existing `flac.FlacDecoder`/`open(arena, bytes)`/`decode` remain unchanged as the unit-test oracle. Streaming uses a separate context so a byte-slice decoder never has to pretend to own a file.

```zig
pub const StreamFlacDecoder = struct {
    bf: *stream.BufferedFile,
    arena: *std.arena.Arena,
    sample_rate: u32,
    channels: u8,
    bits_per_sample: u8,
    min_block: u16,
    max_block: u16,
    max_frames: u32,
    total_frames: u64,
    samples: []i64,
    eof: bool,
};

pub fn openStream(arena: *std.arena.Arena, path: []const u8) FlacError!StreamFlacDecoder;
pub fn closeStream(d: *StreamFlacDecoder) void;
pub fn decodeStream(d: *StreamFlacDecoder, arena: *std.arena.Arena, out: []i16) FlacError!usize;
```

`openStream` reads `fLaC` plus metadata blocks; `STREAMINFO` is parsed; other blocks are skipped with bounded reads. `decodeStream` reads the next frame through `BufferedFile` with an MSB-first bit reader; it does not require a frame-sized byte buffer. The existing `flac.open(arena, bytes)` and byte-slice `BitReader` remain for unit tests only. Frontends use `openStream`/`decodeStream`.

### §4.5 `decoder.zig` selector

The selector keeps its current shape and D8 pointer discipline. Its FLAC arm points at the streaming decoder; the byte-slice `flac.FlacDecoder` is never wrapped by the selector:

```zig
pub const FlacDecoder = struct { fd: *flac.StreamFlacDecoder };
pub fn decoderOpenFlac(out: *player.Decoder, fd: *flac.StreamFlacDecoder) void;
```

`decoderOpenVorbis(out, vc)` is unchanged in shape. `detectKind` remains a 4-byte signature check; frontends read the first four bytes through `BufferedFile` and seek back to 0.

## §5 Frontend behavior

**`main.zig`**
- Open a `BufferedFile`; read 4 bytes; `decoder.detectKind`; seek back to 0 (or use a separate header read).
- OGG modes:
  - `--info`: read id/comment/setup packets; parse tags/id; `oggStreamLastGranule`; print as today.
  - `--dump-setup`: read the three headers; print counts.
  - `--pcm`: open output file, write a 44-byte WAV header with zero sizes, decode packet-by-packet and write PCM bytes, then `seek` to 4/40 and patch RIFF/data sizes. Never allocate the whole output.
  - `--wav`/`--play`: create the `Player` with a streaming `VorbisCtx`.
- FLAC modes (`--wav`/`--play` only, per M8): `flac.openStream`; metadata; `Player`.
- All error exits keep codes 0/1/2/3/4/5 and existing messages where possible. `OutOfMemory` during stream setup maps to the existing “out of memory”/decoder error paths, not “not an OGG”.
- `--start` keeps its discard-until-position behavior; it now discards through the streaming decoder.

**`ui.zig`**
- `playTrack` opens an `OggStream` or `StreamFlacDecoder`; stores it in a global/per-track slot so it outlives `playTrack`; `stopPlayback` closes it.
- Remove `readAll`/`reassemble` from `playTrack`.
- Replace the 4 MiB `g_file_arena` with a stream arena sized for page + packet + read buffer + ID/comment/setup/tags. Keep `g_dec_arena`, `g_scratch_arena`, `g_player_arena`.
- TUI metadata/status behavior is unchanged; duration comes from the tail granule.

## §6 Tests and gates

**Unit tests**
- `BufferedFile`: reads across the 64 KiB boundary, short reads, EOF, seek/tell, file >4 MiB.
- `OggStream`: packet bytes equal `ogg.reassemble` for every committed OGG fixture; multi-page continuation; CRC failure; packet-cap rejection; last granule equals the existing full-scan value.
- `FlacStream`: `flac_test` opens the same fixture through `openStream`; decoded PCM and frame counts equal the existing byte-slice path.

**Tiers**
- Existing: `tier_info` 20/0, `tier_setup` 21/0, `tier_cli` 23/0, `tier_tui` 40/0, `tier_audio` 27/0, `tier_flac` 59/0.
- New `tests/tier_stream.sh`:
  1. Build `main.zig` and `ui.zig` with `-fsafe`; run existing OGG/FLAC smoke.
  2. Generate a large valid OGG (`tests/make_large_ogg.py`) by repeating audio pages from a committed fixture with correct sequence numbers, granules, EOS placement, and CRCs. Target ≥ 64 MiB.
  3. Run `z9play --info` on the large file under `ulimit -v` low enough that a full-file `readAll` cannot pass but the streaming build can. Assert exit 0, expected rate/channels, and duration.
  4. Optionally (`Z9PLAY_LARGE_OGG` env) run the same check on the operator's real 8.2 MB track; do not commit that file.
  5. Run `--pcm` on a small fixture and byte-compare with the existing golden.

**Battery**
- No compiler/seed change; do not run/rotate the compiler seed.
- Keep `verify_stdlib` out of scope unless a std file changes (it must not).

## §7 Error and lifetime rules

- Every frontend path that opens a stream closes it on success and on every error/exit path; `Player` does not own the file handle, the frontend does.
- A decoder context borrows the stream; the stream must outlive the decoder and `Player`.
- `next_fn` returning 0 means clean EOF. Truncated/CRC errors map to `DecodeFailed` (exit 3 for `--pcm`; playback error state for CLI/TUI).
- A packet > `OGG_PACKET_MAX` fails with a clear “unsupported packet size” message, not `OutOfMemory`.
- Tail scan failure yields duration 0 only for an empty/unparseable tail; otherwise preserve the existing “cannot locate the audio granule” error where the mode requires duration.

## §8 Risks

1. **Packet cap**: 1 MiB is far above normal Vorbis packets but must be tested; a legal pathological stream may exceed it. Cost: clean reject.
2. **FLAC bit-level streaming**: the byte-slice `BitReader` must become file-backed; frame boundaries are determined by decoded subframe lengths, so this is a mechanical reader substitution, but it is the riskiest correctness change. Existing byte-slice tests remain the oracle.
3. **Tail granule**: last-page scan must handle a page straddling the tail window; 256 KiB covers the 65,307-byte maximum page, and the scan must retry/expand if the last `OggS` is not a complete page.
4. **`--pcm` streaming**: WAV header patching must preserve byte-exact output; compare to the committed golden.
5. **Win9x**: only `std_file` read/seek is used; no new imports. Hardware verification remains operator-pending.
6. **Do not regress OGG/FLAC**: the existing tiers and byte-exact goldens are the gate.

## §9 Amendment rule

The plan may be amended only by the operator. Any discovered need for an `sf/**` or std change requires STOP-present before touching it. This milestone must not change compiler behavior or rotate the seed.
