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
// Task 1 (this milestone) routes only the existing Vorbis path through the
// selector, with no behavior change. Task 2 fills in the `flac` arm and the
// signature/extension selection; `flac.zig` does not exist yet.
//
// Pure Z98: free functions only (no method syntax), no generics/`anytype`,
// strict `@intCast`.

const player = @import("player.zig");

// The Vorbis arm of the selector. `vc` is the context built by
// `player.vorbisCreate`; the frontend still parses the OGG/Vorbis headers and
// owns the persistent/scratch arenas.
pub const VorbisDecoder = struct {
    vc: *player.VorbisCtx,
};

// The FLAC arm of the selector. Empty in Task 1: FLAC stream/frame decode and
// its context land in Task 2 (`flac.zig`).
pub const FlacDecoder = struct {};

// Frontend-side codec choice. Task 1 only constructs/uses the `.vorbis` arm;
// Task 2 extends `decoderOpen` with the `.flac` arm.
pub const DecoderKind = union(enum) {
    vorbis: VorbisDecoder,
    flac: FlacDecoder,
};

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
