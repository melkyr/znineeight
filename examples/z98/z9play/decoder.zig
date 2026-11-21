// decoder.zig — frontend-side decoder selector/adapter (M8 Task 1).
//
// The `Player` core (player.zig) is codec-agnostic: it holds a
// `*const player.Decoder` vtable and calls `next_fn`. This module owns the
// frontend-side choice between codecs and assembles that vtable. The selector
// lives here (not in player.zig) so the core stays selection-agnostic; the
// vtable remains caller-owned/by-pointer (compiler defect D8: never return a
// `player.Decoder`, or a struct embedding one, by value — fill a caller-owned
// `*player.Decoder` out-param instead).
//
// Task 1 routes the existing Vorbis path through the selector with no behavior
// change. Task 2 fills in the `flac` arm and signature selection; the FLAC
// stream/frame decoder lives in `flac.zig`.
//
// Pure Z98: free functions only (no method syntax), no generics/`anytype`,
// strict `@intCast`.

const player = @import("player.zig");
const flac = @import("flac.zig");

// The Vorbis arm of the selector. `vc` is the context built by
// `player.vorbisCreate`; the frontend still parses the OGG/Vorbis headers and
// owns the persistent/scratch arenas.
pub const VorbisDecoder = struct {
    vc: *player.VorbisCtx,
};

// The FLAC arm of the selector. `fd` is the streaming context built by
// `flac.openStream`; the frontend owns the underlying file and the arena that
// backs the decoder scratch. The byte-slice `flac.FlacDecoder` is test-only
// and is never wrapped by this selector.
pub const FlacDecoder = struct {
    fd: *flac.StreamFlacDecoder,
};

// Frontend-side codec choice.
pub const DecoderKind = union(enum) {
    vorbis: VorbisDecoder,
    flac: FlacDecoder,
};

// Container detection by signature. Returns KIND_UNKNOWN for anything that is
// neither OGG nor FLAC; extension fallback is not needed by the frontends.
pub const KIND_UNKNOWN: u8 = 0;
pub const KIND_OGG: u8 = 1;
pub const KIND_FLAC: u8 = 2;

pub fn detectKind(data: []const u8) u8 {
    if (data.len >= 4) {
        if (data[0] == 'O' and data[1] == 'g' and data[2] == 'g' and data[3] == 'S') {
            return KIND_OGG;
        }
        if (data[0] == 'f' and data[1] == 'L' and data[2] == 'a' and data[3] == 'C') {
            return KIND_FLAC;
        }
    }
    return KIND_UNKNOWN;
}

// Fill the caller-owned `out` vtable from an already-created Vorbis context.
// This is exactly the literal the `--wav`/interactive/`playTrack` sites built
// inline before Task 1; keeping it here is the selector boundary.
pub fn decoderOpenVorbis(out: *player.Decoder, vc: *player.VorbisCtx) void {
    out.* = player.Decoder{
        .ctx = @ptrCast(*void, vc),
        .next_fn = player.vorbisNext,
        .max_frames = vc.max_frames,
        .sample_rate = vc.sample_rate,
        .channels = vc.channels,
        .total_frames = vc.total_frames,
    };
}

// `Decoder.next_fn` adapter for the FLAC arm.
fn flacStreamNext(ctx: *void, pcm_out: []i16) player.DecoderError!usize {
    var fd: *flac.StreamFlacDecoder = @ptrCast(*flac.StreamFlacDecoder, ctx);
    var f: usize = flac.decodeStream(fd, fd.arena, pcm_out) catch |e| {
        if (e == error.OutOfMemory) return error.OutOfMemory;
        return error.DecodeFailed;
    };
    return f;
}

// Fill the caller-owned `out` vtable from an already-opened streaming FLAC
// decoder. Like the Vorbis path, this never returns a `player.Decoder` by
// value (D8).
pub fn decoderOpenFlac(out: *player.Decoder, fd: *flac.StreamFlacDecoder) void {
    out.* = player.Decoder{
        .ctx = @ptrCast(*void, fd),
        .next_fn = flacStreamNext,
        .max_frames = fd.max_frames,
        .sample_rate = fd.sample_rate,
        .channels = fd.channels,
        .total_frames = fd.total_frames,
    };
}
