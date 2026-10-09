// scheduler.zig — z9torr: rarest-first multi-peer piece scheduler.
//
// Spec 2026-10-08 §6 (`Scheduler`), §7 (multi-peer retry), §9 (determinism).
// The scheduler owns the per-piece status array, the `piece_rarest` counter
// (connected peers holding each piece), the claimed-piece owner map, the
// `max_peers` `Peer` slots, and a small ring of recently-seen `PeerAddr`s used
// to skip duplicate connections.
//
// Rarest-first WITHOUT sorting: `pickPiece` linear-scans eligible pieces in
// ascending index order and keeps the first minimum-count piece, so ties break
// by the lowest piece index (spec §9 M3 determinism).
//
// Claim/owner model: a peer holds at most one claimed piece at a time (the M2
// coroutine works on a single `PieceState`). `pickPiece` stashes the choosing
// peer's slot in `pending_owner`; the caller then calls `claim(index)`, which
// marks the piece `requested` and records that slot in `piece_owner`. There is
// no suspension between the two calls (both are plain functions), so the
// pairing is deterministic. `release(peer)` returns every piece owned by the
// peer's slot to `missing` (block state is retained; the resume sidecar's
// `partial[]` survives claim/release, spec §7).
//
// `piece_state` is the authoritative per-piece status array (`PieceStatus`:
// only {index, state}); the working block state lives in the owning peer's
// `Peer.ps` (spec §6 M3 amendment). Callers that already verified pieces from a
// resume sidecar must set those entries `.verified` after `schedulerInit`.
//
// Z98 rules: free functions only, no generics/`anytype`, strict `@intCast`,
// `switch` needs `else`, string literals via `var s: []const u8 = "x";`.
// D2: every slice is a primitive element (`[]u8`/`[]u32`), a named element
// (`[]Peer`, `[]PieceStatus`), or a fixed array of a named type.

const std = @import("std");
const piece = @import("piece.zig");
const peer = @import("peer.zig");
const torrent = @import("torrent.zig");
const tracker = @import("tracker.zig");

// Owner sentinel: "no owner" / "no piece". 0xFFFFFFFF is not a valid piece
// index (piece count is bounded by MAX_TORRENT_BYTES/20).
pub const NO_OWNER: u32 = 0xFFFFFFFF;

// Recently-seen address ring capacity (spec §12 item 8).
const SEEN_RING: u32 = 8;

pub const SchedulerError = error{OutOfMemory};

// Minimal per-piece status the scheduler needs: spec §6 `PieceState` minus the
// per-peer working fields (`blocks` lives in the owning `Peer.ps`; `hash`/
// `received_bytes`/`length`/`nblocks` are only read by the piece pipeline).
// Keeping only {index, state} lets the arena fit the parser's `MAX_PIECES`
// (157286) inside the 16 MB target: 157286 * 8 B ≈ 1.2 MiB (vs ~7.2 MiB for
// the full `PieceState`). The authoritative block state remains per-peer.
pub const PieceStatus = struct {
    index: u32,
    state: piece.BlockState,
};

pub const Scheduler = struct {
    // Spec §6 fields.
    piece_state: []PieceStatus,
    piece_rarest: []u32,
    peers: []peer.Peer,
    active_peer_count: u32,
    // Internal fields the plan's behavior needs.
    piece_owner: []u32, // piece index -> owning peer slot (NO_OWNER if free)
    pending_owner: u32, // slot stashed by `pickPiece`, consumed by `claim`
    seen: [8]tracker.PeerAddr, // recent-address ring (dedupe)
    seen_count: u32,
    seen_next: u32,
};

// Zero-length slices for the empty-piece / empty-peer cases (D2: `[]primitive`
// and fixed arrays of named types only).
var g_empty_bits: [1]u8 = undefined;
var g_empty_u32: [1]u32 = undefined;
var g_empty_piece_status: [1]PieceStatus = undefined;
var g_empty_peer: [1]peer.Peer = undefined;

fn emptyBits() []u8 {
    return g_empty_bits[0..0];
}

fn emptyU32() []u32 {
    return g_empty_u32[0..0];
}

fn emptyPieceStatuses() []PieceStatus {
    return g_empty_piece_status[0..0];
}

fn emptyPeers() []peer.Peer {
    return g_empty_peer[0..0];
}

// `true` if `p`'s availability bitfield has bit `i` set (out-of-range false).
fn peerHas(p: *peer.Peer, i: u32) bool {
    var byte: usize = @intCast(usize, i / 8);
    if (byte >= p.bitfield.len) return false;
    return piece.bitGet(p.bitfield, i);
}

pub fn schedulerInit(arena: *std.arena.Arena, t: torrent.Torrent, max_peers: u32) SchedulerError!Scheduler {
    var n_pieces: u32 = 0;
    if (t.total_length > 0 and t.piece_length > 0) {
        var pl: u64 = @intCast(u64, t.piece_length);
        n_pieces = @intCast(u32, (t.total_length + pl - 1) / pl);
    }

    // Per-piece status array. `blocks` is deliberately absent: block state is
    // owned by each peer's `Peer.ps` (spec §6 M3 amendment).
    var ps: []PieceStatus = emptyPieceStatuses();
    if (n_pieces > 0) {
        var raw = std.arena.alloc(arena, @intCast(usize, n_pieces) * @sizeOf(PieceStatus)) catch return error.OutOfMemory;
        ps = @ptrCast([*]PieceStatus, raw)[0..@intCast(usize, n_pieces)];
        var i: u32 = 0;
        while (i < n_pieces) : (i += 1) {
            ps[@intCast(usize, i)] = PieceStatus{
                .index = i,
                .state = piece.BlockState.missing,
            };
        }
    }

    // `piece_rarest[i]` = connected peers holding bit `i` (all zero initially).
    var rar: []u32 = emptyU32();
    if (n_pieces > 0) {
        var rawr = std.arena.alloc(arena, @intCast(usize, n_pieces) * @sizeOf(u32)) catch return error.OutOfMemory;
        rar = @ptrCast([*]u32, rawr)[0..@intCast(usize, n_pieces)];
        var k: u32 = 0;
        while (k < n_pieces) : (k += 1) {
            rar[@intCast(usize, k)] = 0;
        }
    }

    var own: []u32 = emptyU32();
    if (n_pieces > 0) {
        var rawo = std.arena.alloc(arena, @intCast(usize, n_pieces) * @sizeOf(u32)) catch return error.OutOfMemory;
        own = @ptrCast([*]u32, rawo)[0..@intCast(usize, n_pieces)];
        var ko: u32 = 0;
        while (ko < n_pieces) : (ko += 1) {
            own[@intCast(usize, ko)] = NO_OWNER;
        }
    }

    var peers: []peer.Peer = emptyPeers();
    if (max_peers > 0) {
        var rawp = std.arena.alloc(arena, @intCast(usize, max_peers) * @sizeOf(peer.Peer)) catch return error.OutOfMemory;
        peers = @ptrCast([*]peer.Peer, rawp)[0..@intCast(usize, max_peers)];
        var j: u32 = 0;
        while (j < max_peers) : (j += 1) {
            // `sock`/`addr`/`ps`/`io`/`hs`/`rhs`/`peer_id`/`read_buf` stay
            // uninitialised until `addPeer`/`peerRun` set them (a struct literal
            // cannot `undefined` a nested named-struct field in Z98 emission).
            var p: peer.Peer = undefined;
            p.active = false;
            p.slot = j;
            p.sched = null;
            p.have_piece = false;
            p.bitfield = emptyBits();
            p.rarest = rar;
            p.sock = @intCast(i32, -1);
            peers[@intCast(usize, j)] = p;
        }
    }

    var s = Scheduler{
        .piece_state = ps,
        .piece_rarest = rar,
        .peers = peers,
        .active_peer_count = 0,
        .piece_owner = own,
        .pending_owner = NO_OWNER,
        .seen = undefined,
        .seen_count = 0,
        .seen_next = 0,
    };
    return s;
}

// Rarest-first selection: the `missing` piece this peer holds with the minimum
// `piece_rarest` count; ties break by the lowest piece index. Returns null when
// the peer holds no eligible piece. On success the owner slot is stashed for the
// immediately-following `claim`.
pub fn pickPiece(s: *Scheduler, p: *peer.Peer) ?u32 {
    var best: u32 = NO_OWNER;
    var best_r: u32 = 0xFFFFFFFF;
    var n: u32 = @intCast(u32, s.piece_state.len);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        if (s.piece_state[@intCast(usize, i)].state != piece.BlockState.missing) continue;
        if (!peerHas(p, i)) continue;
        var r: u32 = s.piece_rarest[@intCast(usize, i)];
        if (r < best_r) {
            best_r = r;
            best = i;
        }
    }
    if (best == NO_OWNER) return null;
    s.pending_owner = p.slot;
    return best;
}

// Record that `p` now holds piece `index`: set the peer's availability bit (if
// it fits the peer's bitfield) and increment `piece_rarest[index]`. The peer
// loop and the unit harness share this single increment path, so the counter is
// only ever moved here.
pub fn noteHave(s: *Scheduler, p: *peer.Peer, index: u32) void {
    var ui: usize = @intCast(usize, index);
    if (ui >= s.piece_rarest.len) return;
    if (ui / 8 >= p.bitfield.len) return;
    if (peerHas(p, index)) return; // already counted
    piece.bitSet(p.bitfield, index);
    s.piece_rarest[ui] += 1;
}

// Mark piece `index` requested and record the owner stashed by `pickPiece`.
// A claim on a piece that is not `missing` would be a double-claim (two peers
// asked for the same piece); `pickPiece` selects only `missing` pieces and
// pick/claim are consecutive with no suspension between them, so this never
// fires — it is the assertion that the invariant holds.
pub fn claim(s: *Scheduler, index: u32) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    if (index >= n) return;
    var ui: usize = @intCast(usize, index);
    if (s.piece_state[ui].state != piece.BlockState.missing) {
        @panic("scheduler: claim of a non-missing piece (double claim)");
    }
    s.piece_state[ui].state = piece.BlockState.requested;
    if (ui < s.piece_owner.len) s.piece_owner[ui] = s.pending_owner;
}

// Mark piece `index` verified (clear its owner).
pub fn complete(s: *Scheduler, index: u32) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    if (index >= n) return;
    var ui: usize = @intCast(usize, index);
    s.piece_state[ui].state = piece.BlockState.verified;
    if (ui < s.piece_owner.len) s.piece_owner[ui] = NO_OWNER;
}

// A corrupted piece returns to `missing` (written-through blocks are retained
// in the resume sidecar's `partial[]`), clear of any owner.
pub fn corrupt(s: *Scheduler, index: u32) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    if (index >= n) return;
    var ui: usize = @intCast(usize, index);
    s.piece_state[ui].state = piece.BlockState.missing;
    if (ui < s.piece_owner.len) s.piece_owner[ui] = NO_OWNER;
}

// Return every piece claimed by `p` (owner slot) to `missing`, retaining its
// written-through block mask.
pub fn release(s: *Scheduler, p: *peer.Peer) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var ui: usize = @intCast(usize, i);
        if (ui >= s.piece_owner.len) continue;
        if (s.piece_owner[ui] == p.slot and s.piece_state[ui].state == piece.BlockState.requested) {
            s.piece_state[ui].state = piece.BlockState.missing;
            s.piece_owner[ui] = NO_OWNER;
        }
    }
    p.have_piece = false;
}

fn addrSeen(s: *Scheduler, addr: tracker.PeerAddr) bool {
    var n: u32 = @intCast(u32, s.peers.len);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var ui: usize = @intCast(usize, i);
        if (s.peers[ui].active) {
            if (s.peers[ui].addr.ip_be == addr.ip_be and s.peers[ui].addr.port == addr.port) return true;
        }
    }
    var j: u32 = 0;
    while (j < s.seen_count) : (j += 1) {
        var uj: usize = @intCast(usize, j);
        if (s.seen[uj].ip_be == addr.ip_be and s.seen[uj].port == addr.port) return true;
    }
    return false;
}

fn rememberAddr(s: *Scheduler, addr: tracker.PeerAddr) void {
    var ui: usize = @intCast(usize, s.seen_next);
    s.seen[ui] = addr;
    s.seen_next = (s.seen_next + 1) % SEEN_RING;
    if (s.seen_count < SEEN_RING) s.seen_count += 1;
}

// Claim a free peer slot for `addr`; returns false if the slot table is full or
// `addr` was seen recently (duplicate) or is already active.
pub fn addPeer(s: *Scheduler, addr: tracker.PeerAddr) bool {
    if (addrSeen(s, addr)) return false;
    var n: u32 = @intCast(u32, s.peers.len);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        var ui: usize = @intCast(usize, i);
        if (!s.peers[ui].active) {
            var p = &s.peers[ui];
            p.active = true;
            p.addr = addr;
            p.slot = i;
            p.have_piece = false;
            p.sock = @intCast(i32, -1);
            p.am_choking = true;
            p.am_interested = false;
            p.peer_choking = true;
            p.peer_interested = false;
            p.last_recv_ms = 0;
            p.last_send_ms = 0;
            p.down_bytes = 0;
            p.up_bytes = 0;
            p.bitfield = emptyBits();
            p.rarest = s.piece_rarest;
            p.sched = s;
            s.active_peer_count += 1;
            rememberAddr(s, addr);
            return true;
        }
    }
    return false;
}

// Free `p`'s slot: release its claimed pieces, decrement `piece_rarest` for each
// availability bit it had set (no underflow), and clear the slot.
pub fn removePeer(s: *Scheduler, p: *peer.Peer) void {
    if (!p.active) return;
    release(s, p);
    var n: u32 = @intCast(u32, s.piece_rarest.len);
    var i: u32 = 0;
    while (i < n) : (i += 1) {
        if (peerHas(p, i)) {
            var ui: usize = @intCast(usize, i);
            if (s.piece_rarest[ui] == 0) {
                // Invariant: a bit is only ever counted via `noteHave`, so a
                // set bit must have a non-zero count. Underflow is a bug.
                unreachable;
            }
            s.piece_rarest[ui] -= 1;
        }
    }
    p.active = false;
    p.bitfield = emptyBits();
    p.rarest = emptyU32();
    p.sched = null;
    p.have_piece = false;
    if (s.active_peer_count > 0) s.active_peer_count -= 1;
}
