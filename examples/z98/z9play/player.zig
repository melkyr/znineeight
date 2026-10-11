// player.zig — z9play Player core + double-buffer PCM ring (M4 Task 3).
//
// Blueprint §3 (examples/z9play.txt), spec §4: the shared, display-agnostic
// playback core. One job: decode the next block when the ring has room, and
// flush the ring to the audio output when a half (or the end of stream) is
// ready. No coroutines (spec §2 VERIFY-3 is moot; blueprint §3.3): v1 is a
// blocking loop — `playerPump` advances it one step at a time.
//
// Two vtables (blueprint §2.2/§3.1):
//   - `audio.AudioOut` (platform/audio.zig) is passed in by the frontend.
//   - `Decoder` (defined here) abstracts the codec: the next decoded block of
//     interleaved s16 plus the stream's frame metadata. The M3 Vorbis backend
//     (`vorbisCreate`/`vorbisNext`) implements it; M8 can add a FLAC backend.
//
// Ring buffer (blueprint §3.2, spec §4): 2 x 0.5 s @ 44.1 kHz stereo s16 =
// 176,400 bytes = 88,200 interleaved i16 samples, allocated once from the
// player arena. Because OSS / `waveOut` consume synchronously, v1 is a
// double buffer (the name "ring" is kept for future flexibility): one half
// plays while the other fills. `flush_threshold` is half the capacity; the
// ring is written to audio whenever a half is ready, or at end of stream.
//
// Granule trim (M3 residual): the decoder emits the final block's padding past
// the Ogg granule; the Player stops handing samples to audio at exactly
// `decoder.total_frames` frames, so its output matches M3's `--pcm` (which
// trims to `ogg.lastGranule`).
//
// Per-packet scratch (M3 residual): `vorbisNext` resets its scratch arena
// before every packet, so a long song does not grow the arena (decode.zig's
// per-codeword allocations are temporary and do not escape a packet).
//
// Assembly note (compiler defect D8): the vtables are held BY POINTER and the
// `Player` is caller-owned, never returned by value. A struct field whose type
// is a vtable struct — or a function returning a struct that embeds one —
// makes the emitter write the error-union-returning function-pointer typedef
// before its error-union typedef (invalid C89). `vorbisCreate` returns an
// opaque context pointer and the caller assembles the `Decoder` literal
// (exactly as the audio backends do for `AudioOut`). See
// examples/torrent_example_defects.md (D8).
//
// Pure Z98: free functions only (no method syntax), no generics/`anytype`,
// strict `@intCast`, no `switch` here (if/else), string literals via typed
// `var` (AGENTS.md X.5).

const std = @import("std");
const audio = @import("platform/audio.zig");
const ogg = @import("ogg.zig");
const vs = @import("vorbis_setup.zig");
const dec = @import("decode.zig");

// Player lifecycle (blueprint §3.1). `error_state` is entered when a pump step
// fails; `ended` when the stream is drained.
pub const PlayerState = enum(u8) { stopped, playing, paused, ended, error_state };

// Ring capacity in interleaved i16 samples: 2 x 0.5 s @ 44.1 kHz stereo s16 =
// 176,400 bytes (blueprint §3.2). Fixed regardless of rate, per spec §4.
pub const RING_SAMPLES: u32 = 88200;

// Errors `playerPump` can report. BadConfig is a malformed decoder descriptor.
pub const PlayerError = error{ DecodeFailed, AudioFailed, OutOfMemory, BadConfig };

// Errors a decoder vtable `next_fn` may report.
pub const DecoderError = error{ DecodeFailed, OutOfMemory };

// Decoder interface (blueprint §3.1). `next_fn` decodes the next chunk of
// interleaved s16 into `pcm_out` and returns frames (samples per channel); 0
// means end of stream. The caller assembles the literal (D8).
pub const Decoder = struct {
    ctx: *void,
    next_fn: fn (*void, []i16) DecoderError!usize,
    max_frames: u32, // upper bound of frames one next_fn call emits
    sample_rate: u32,
    channels: u8,
    total_frames: u64, // stream granule; 0 = unbounded
};

// Optional track metadata supplied by the frontend (blueprint §3.1).
pub const Meta = struct {
    title: ?[]const u8,
    artist: ?[]const u8,
    album: ?[]const u8,
};

// Double-buffered PCM staging (blueprint §3.2).
pub const RingBuffer = struct {
    data: []i16,
    write_pos: u32,
    read_pos: u32,
    filled: u32, // interleaved samples available to flush
    capacity: u32, // interleaved samples total
};

pub const Player = struct {
    // The vtables are held BY POINTER, never embedded by value: a struct field
    // whose type is a vtable struct triggers compiler defect D8 (the emitter
    // writes the error-union-returning function-pointer typedef before the
    // error-union typedef it references). See
    // examples/torrent_example_defects.md (D8).
    decoder: *const Decoder,
    audio: *const audio.AudioOut,
    arena: *std.arena.Arena,

    ring: RingBuffer,
    state: PlayerState,
    volume: u8, // 0..100
    position_ms: u64, // frames written to audio / (rate) * 1000
    started_ms: u32, // reserved for M5 (no clock in M4)
    duration_ms: u64,
    sample_rate: u32,
    channels: u8,

    // Metadata (blueprint §3.1)
    title: ?[]const u8,
    artist: ?[]const u8,
    album: ?[]const u8,

    // Internal bookkeeping.
    frames_written: u64, // frames handed to the audio backend
    frames_decoded: u64, // frames taken from the decoder (capped at total)
    decoding_done: bool,
    flush_threshold: u32, // interleaved samples in a half (capacity/2)
    block_buf: []i16, // scratch for one decoded block (max_frames * channels)
};

// Allocate the ring + block scratch from `arena` and initialise caller-owned
// `p` in the `playing` state. `decoder`/`ao` are held by pointer; `meta` is
// optional (null fields).
//
// Caller-owned output + pointer vtables (compiler defect D8): the `Player`
// struct must NOT be returned by value and must NOT embed a vtable struct by
// value. A struct field of vtable type (or returning a struct that embeds one)
// makes the emitter write the error-union-returning function-pointer typedef
// before the error-union typedef it references (invalid C89). The caller
// assembles the vtable literals and passes their addresses. See
// examples/torrent_example_defects.md (D8).
pub fn playerInit(p: *Player, arena: *std.arena.Arena, decoder: *const Decoder, ao: *const audio.AudioOut, meta: Meta) PlayerError!void {
    if (decoder.channels == 0) return error.BadConfig;
    var ch: usize = @intCast(usize, decoder.channels);

    var cap: usize = @intCast(usize, RING_SAMPLES);
    var rraw: [*]u8 = std.arena.alloc(arena, cap * @sizeOf(i16)) catch return error.OutOfMemory;
    var rdata: []i16 = @ptrCast([*]i16, rraw)[0..cap];

    var mf: usize = @intCast(usize, decoder.max_frames);
    if (mf == 0) mf = 1;
    var braw: [*]u8 = std.arena.alloc(arena, mf * ch * @sizeOf(i16)) catch return error.OutOfMemory;
    var bdata: []i16 = @ptrCast([*]i16, braw)[0 .. mf * ch];

    var dur: u64 = 0;
    if (decoder.sample_rate > 0) {
        dur = decoder.total_frames * 1000 / @intCast(u64, decoder.sample_rate);
    }

    p.* = Player{
        .decoder = decoder,
        .audio = ao,
        .arena = arena,
        .ring = RingBuffer{ .data = rdata, .write_pos = 0, .read_pos = 0, .filled = 0, .capacity = @intCast(u32, cap) },
        .state = PlayerState.playing,
        .volume = 80,
        .position_ms = 0,
        .started_ms = 0,
        .duration_ms = dur,
        .sample_rate = decoder.sample_rate,
        .channels = decoder.channels,
        .title = meta.title,
        .artist = meta.artist,
        .album = meta.album,
        .frames_written = 0,
        .frames_decoded = 0,
        .decoding_done = false,
        .flush_threshold = @intCast(u32, cap / 2),
        .block_buf = bdata,
    };
}

// Advance playback one step. Decodes at most one block when the ring has room,
// then flushes a ready half (or the remainder at end of stream) to audio. Sets
// `ended` when the stream is fully drained, or `error_state` on a failure.
pub fn playerPump(p: *Player) PlayerError!void {
    if (p.state != PlayerState.playing) return;

    if (!p.decoding_done and p.ring.filled < p.ring.capacity) {
        playerDecodeStep(p) catch |e| {
            p.state = PlayerState.error_state;
            return e;
        };
    }

    if (p.ring.filled >= p.flush_threshold or (p.decoding_done and p.ring.filled > 0)) {
        playerFlush(p) catch |e| {
            p.state = PlayerState.error_state;
            return e;
        };
    }

    if (p.decoding_done and p.ring.filled == 0) {
        p.state = PlayerState.ended;
    }
}

// Monotonic playback position within the track, in milliseconds.
pub fn playerPositionMs(p: *const Player) u64 {
    return p.position_ms;
}

// Decode one block from the decoder, cap it at the stream granule, and append
// it to the ring. Marks `decoding_done` at end of stream or granule.
fn playerDecodeStep(p: *Player) PlayerError!void {
    var ch: usize = @intCast(usize, p.channels);
    var got: usize = p.decoder.next_fn(p.decoder.ctx, p.block_buf) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.DecodeFailed;
    };

    var frames: usize = got;
    if (p.decoder.total_frames > 0) {
        if (p.frames_decoded >= p.decoder.total_frames) {
            p.decoding_done = true;
            return;
        }
        var avail: u64 = p.decoder.total_frames - p.frames_decoded;
        if (@intCast(u64, frames) > avail) frames = @intCast(usize, avail);
    }

    var samples: usize = frames * ch;
    playerRingAppend(p, p.block_buf[0..samples]);
    p.frames_decoded += @intCast(u64, frames);

    if (got == 0) p.decoding_done = true;
    if (p.decoder.total_frames > 0 and p.frames_decoded >= p.decoder.total_frames) {
        p.decoding_done = true;
    }
}

// Append interleaved samples at `write_pos`, wrapping at capacity. The caller
// guarantees the block fits (`filled` never exceeds `flush_threshold + a
// block`, well under capacity).
fn playerRingAppend(p: *Player, samples: []const i16) void {
    var cap: usize = @intCast(usize, p.ring.capacity);
    var i: usize = 0;
    while (i < samples.len) : (i += 1) {
        var w: usize = @intCast(usize, p.ring.write_pos);
        p.ring.data[w] = samples[i];
        var nw: usize = w + 1;
        if (nw >= cap) nw = 0;
        p.ring.write_pos = @intCast(u32, nw);
        p.ring.filled += 1;
    }
}

// Write every filled sample (from `read_pos`, wrapping) to the audio backend,
// then mark the ring empty and update the position.
fn playerFlush(p: *Player) PlayerError!void {
    var filled: usize = @intCast(usize, p.ring.filled);
    if (filled == 0) return;

    var cap: usize = @intCast(usize, p.ring.capacity);
    var rp: usize = @intCast(usize, p.ring.read_pos);
    var first: usize = cap - rp;
    if (first > filled) first = filled;

    var end1: usize = rp + first;
    var n1: usize = p.audio.write_fn(p.audio.state, p.ring.data[rp..end1]) catch return error.AudioFailed;
    if (n1 != first) return error.AudioFailed;

    var rest: usize = filled - first;
    if (rest > 0) {
        var n2: usize = p.audio.write_fn(p.audio.state, p.ring.data[0..rest]) catch return error.AudioFailed;
        if (n2 != rest) return error.AudioFailed;
    }

    p.ring.read_pos = p.ring.write_pos;
    p.ring.filled = 0;

    var ch: u64 = @intCast(u64, p.channels);
    p.frames_written += @intCast(u64, filled) / ch;
    if (p.sample_rate > 0) {
        p.position_ms = p.frames_written * 1000 / @intCast(u64, p.sample_rate);
    }
}

// --- M3 Vorbis backend for the Decoder vtable ------------------------------
//
// An opaque context that owns the persistent decoder state (codebook tables +
// overlap tail) and the packet cursor, plus a per-packet scratch arena that is
// reset on every `vorbisNext`. The frontend parses the stream and builds the
// state (`vs.parseSetup` + `dec.initDecoderState`), then assembles the
// `Decoder` literal from `vorbisCreate` and the context's metadata fields.

pub const VorbisCtx = struct {
    scratch: *std.arena.Arena,
    setup: vs.Setup,
    state: dec.DecoderState,
    packets: []ogg.Packet,
    next_packet: usize,
    tmp: []i16, // one decoded block before it is copied to pcm_out

    max_frames: u32,
    sample_rate: u32,
    channels: u8,
    total_frames: u64,
};

// Build a Vorbis decoder context. `persistent` must outlive playback (it holds
// `setup`, the state's tables, the context itself and `tmp`); `scratch` is
// reset per packet. All of `packets` is retained; decoding starts at
// `first_packet` (the header packet count: id, comment, setup -> 3 for a bare
// Vorbis stream).
pub fn vorbisCreate(persistent: *std.arena.Arena, scratch: *std.arena.Arena, packets: []ogg.Packet, setup: vs.Setup, state: dec.DecoderState, first_packet: usize, sample_rate: u32, channels: u8, total_frames: u64) DecoderError!*VorbisCtx {
    if (channels == 0) return error.DecodeFailed;

    var mf: u32 = state.max_n / 2;
    if (mf == 0) mf = 1;

    var craw: [*]u8 = std.arena.alloc(persistent, @sizeOf(VorbisCtx)) catch return error.OutOfMemory;
    var c: *VorbisCtx = @ptrCast(*VorbisCtx, craw);

    var ch: usize = @intCast(usize, channels);
    var n: usize = @intCast(usize, mf) * ch;
    var traw: [*]u8 = std.arena.alloc(persistent, n * @sizeOf(i16)) catch return error.OutOfMemory;
    var tmp: []i16 = @ptrCast([*]i16, traw)[0..n];

    c.* = VorbisCtx{
        .scratch = scratch,
        .setup = setup,
        .state = state,
        .packets = packets,
        .next_packet = first_packet,
        .tmp = tmp,
        .max_frames = mf,
        .sample_rate = sample_rate,
        .channels = channels,
        .total_frames = total_frames,
    };
    return c;
}

// `Decoder.next_fn`: decode packets until one yields output frames (the priming
// packet yields none), resetting the scratch arena per packet. Returns 0 at end
// of stream.
pub fn vorbisNext(ctx: *void, pcm_out: []i16) DecoderError!usize {
    var c: *VorbisCtx = @ptrCast(*VorbisCtx, ctx);
    var ch: usize = @intCast(usize, c.state.channels);
    while (c.next_packet < c.packets.len) {
        var idx: usize = c.next_packet;
        c.next_packet += 1;
        std.arena.reset(c.scratch);
        var f: usize = dec.decodePacket(c.scratch, c.setup, &c.state, c.packets[idx].bytes, c.tmp) catch |e| {
            if (e == error.OutOfMemory) return error.OutOfMemory;
            return error.DecodeFailed;
        };
        if (f > 0) {
            var n: usize = f * ch;
            var i: usize = 0;
            while (i < n) : (i += 1) pcm_out[i] = c.tmp[i];
            return f;
        }
    }
    return 0;
}
