// piece.zig — z9torr: block/piece bookkeeping, request pipelining, verification.
//
// Spec 2026-10-08 §6/§7, blueprint `piece`/`peer` sections. A piece is split
// into fixed 16 KiB blocks (the last block is shorter). Requests are pipelined
// to a depth of 4 (`RequestQueue.in_flight[4]`). `onBlock` writes each received
// block through to disk immediately (spec §7 write-through), and when every
// block of the piece is present it reads the whole piece back, SHA-1s it, and
// compares against `t.piece_hashes[index*20 .. index*20+20]`:
//   match    -> every block `verified`, state `verified`, return `.Complete`;
//   mismatch -> state `failed`, every block re-queued (`missing`), `.Corrupt`.
//
// Z98 rules: free functions only, no generics/`anytype`, strict `@intCast`,
// `switch` needs `else`, string literals via `var s: []const u8 = "x";`.
// D2: `[]PieceState`/`[]BlockState` are slices of *named* types (safe); the
// only other slice is the primitive `[]u8` verification scratch buffer.

const std = @import("std");
const disk = @import("disk.zig");
const torrent = @import("torrent.zig");
const filemod = @import("std_file.zig");
const crypto = @import("std_crypto");

// One block is 16 KiB (blueprint §6; the request pipeline quantum).
pub const BLOCK_SIZE: u32 = 16384;
// In-flight request depth (spec §6 `RequestQueue.in_flight: [4]Request`).
pub const DEPTH: u32 = 4;

pub const HASH_LEN: usize = 20;

pub const BlockState = enum(u8) {
    missing,
    requested,
    received,
    verified,
    failed,
};

// Per-piece state (spec §6). `blocks` has one entry per 16 KiB block; `hash` is
// the expected SHA-1 copied from `t.piece_hashes`; `length` is the true piece
// length (the last piece may be shorter than `t.piece_length`).
pub const PieceState = struct {
    index: u32,
    state: BlockState,
    blocks: []BlockState,
    received_bytes: u32,
    hash: [20]u8,
    length: u32,
    nblocks: u32,
};

pub const Request = struct { index: u32, begin: u32, length: u32 };

// Depth-4 request queue. `in_flight[0..tail]` holds the requests `nextRequests`
// produced this call (`head` is always 0 in this single-window design).
pub const RequestQueue = struct {
    in_flight: [4]Request,
    head: u32,
    tail: u32,
};

pub const BlockResult = enum(u8) { Continue, Complete, Corrupt };

pub const PieceError = error{ OutOfMemory, BadPiece, DiskFailed };

// Ambient context `onBlock` needs to write-through and verify (arena for the
// read-back scratch, the torrent for offsets/hashes, the open target file).
// Kept out of `PieceState` so the spec §6 struct stays data-only.
pub const PieceIO = struct {
    arena: *std.arena.Arena,
    t: torrent.Torrent,
    f: *filemod.File,
};

fn pieceHashOffset(index: u32) usize {
    return @intCast(usize, index) * HASH_LEN;
}

// --- completed-piece bitset helpers (shared by peer.zig and main.zig) -------
//
// Bit `i` is MSB-first (BEP 3 bitfield order): byte `i / 8`, mask
// `1 << (7 - (i % 8))`. The peer's `bitfield` message and the client's own
// completed-piece bitset use the same order; `resume.zig`'s bitmap helpers
// mirror this so the shared `completed_bits` buffer is decoded identically.

pub fn bitGet(bits: []const u8, i: u32) bool {
    var byte: usize = @intCast(usize, i / 8);
    var sh: u8 = @intCast(u8, 7 - (i % 8));
    return ((bits[byte] >> sh) & @intCast(u8, 1)) == @intCast(u8, 1);
}

pub fn bitSet(bits: []u8, i: u32) void {
    var byte: usize = @intCast(usize, i / 8);
    var sh: u8 = @intCast(u8, 7 - (i % 8));
    var mask: u8 = @intCast(u8, 1) << sh;
    bits[byte] = bits[byte] | mask;
}

// Initialise `state` for piece `index`: size the block vector, zero the
// counters, and copy the expected SHA-1 out of `t.piece_hashes`.
pub fn pieceInit(arena: *std.arena.Arena, t: torrent.Torrent, state: *PieceState, index: u32) PieceError!void {
    var plen: u32 = disk.pieceLength(t, index);
    if (plen == 0) return error.BadPiece;

    var n: u32 = (plen + BLOCK_SIZE - 1) / BLOCK_SIZE;
    var raw = std.arena.alloc(arena, @intCast(usize, n) * @sizeOf(BlockState)) catch return error.OutOfMemory;
    var blocks: []BlockState = @ptrCast([*]BlockState, raw)[0..@intCast(usize, n)];

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        blocks[@intCast(usize, i)] = BlockState.missing;
    }

    state.index = index;
    state.state = BlockState.missing;
    state.blocks = blocks;
    state.received_bytes = 0;
    state.length = plen;
    state.nblocks = n;

    var off: usize = pieceHashOffset(index);
    if (off + HASH_LEN > t.piece_hashes.len) return error.BadPiece;
    var k: usize = 0;
    while (k < HASH_LEN) : (k += 1) {
        state.hash[k] = t.piece_hashes[off + k];
    }
}

// Fill `out` with up to `DEPTH` requests for missing blocks of `state`,
// marking each requested block `requested`. The last block is length
// `piece_len - (n-1)*16384` (clamped to the remaining piece bytes).
pub fn nextRequests(state: *PieceState, out: *RequestQueue) void {
    out.head = 0;

    var outstanding: u32 = 0;
    var i: u32 = 0;
    while (i < state.nblocks) : (i += 1) {
        if (state.blocks[@intCast(usize, i)] == BlockState.requested) outstanding += 1;
    }

    var n: u32 = 0;
    var j: u32 = 0;
    while (j < state.nblocks and (outstanding + n) < DEPTH) : (j += 1) {
        var bi: usize = @intCast(usize, j);
        if (state.blocks[bi] == BlockState.missing) {
            var begin: u32 = j * BLOCK_SIZE;
            var len: u32 = BLOCK_SIZE;
            if (begin + len > state.length) len = state.length - begin;
            out.in_flight[@intCast(usize, n)] = Request{ .index = state.index, .begin = begin, .length = len };
            state.blocks[bi] = BlockState.requested;
            n += 1;
        }
    }
    out.tail = n;
}

// Receive one block of `state` at `begin`. Writes through to disk, and on the
// final block reads the piece back + SHA-1 verifies. Returns `.Continue` while
// blocks remain, `.Complete` when the piece verifies, `.Corrupt` when the
// received bytes do not hash to `state.hash` (all blocks are re-queued).
pub fn onBlock(state: *PieceState, begin: u32, bytes: []const u8, io: *PieceIO) PieceError!BlockResult {
    if (begin % BLOCK_SIZE != 0) return BlockResult.Corrupt;
    var bi: u32 = begin / BLOCK_SIZE;
    if (bi >= state.nblocks) return BlockResult.Corrupt;

    var expect: u32 = BLOCK_SIZE;
    if (begin + expect > state.length) expect = state.length - begin;
    if (bytes.len != @intCast(usize, expect)) return BlockResult.Corrupt;

    disk.writeBlock(io.f, io.t, state.index, begin, bytes) catch return error.DiskFailed;

    var biu: usize = @intCast(usize, bi);
    state.blocks[biu] = BlockState.received;
    state.received_bytes += @intCast(u32, bytes.len);

    // All blocks present?
    var all: bool = true;
    var i: u32 = 0;
    while (i < state.nblocks) : (i += 1) {
        var s = state.blocks[@intCast(usize, i)];
        if (s != BlockState.received and s != BlockState.verified) all = false;
    }
    if (!all) return BlockResult.Continue;

    // Verify-on-complete: read the piece back and SHA-1 it (spec §7).
    var raw = std.arena.alloc(io.arena, @intCast(usize, state.length)) catch return error.OutOfMemory;
    var buf: []u8 = raw[0..@intCast(usize, state.length)];
    var got: usize = disk.readPiece(io.f, io.t, state.index, buf) catch return error.DiskFailed;
    if (got != @intCast(usize, state.length)) return BlockResult.Corrupt;

    var hs = crypto.sha1Init();
    crypto.sha1Update(&hs, buf);
    var h: [20]u8 = undefined;
    crypto.sha1Final(&hs, &h);

    var match: bool = true;
    var k: usize = 0;
    while (k < HASH_LEN) : (k += 1) {
        if (h[k] != state.hash[k]) match = false;
    }

    if (match) {
        i = 0;
        while (i < state.nblocks) : (i += 1) {
            state.blocks[@intCast(usize, i)] = BlockState.verified;
        }
        state.state = BlockState.verified;
        return BlockResult.Complete;
    }

    // Corrupt: mark failed and re-queue every block (spec §7 — mismatch is
    // re-requested; the peer that delivered it is dropped by the caller).
    state.state = BlockState.failed;
    i = 0;
    while (i < state.nblocks) : (i += 1) {
        state.blocks[@intCast(usize, i)] = BlockState.missing;
    }
    state.received_bytes = 0;
    return BlockResult.Corrupt;
}
