// scheduler.zig — z9torr: rarest-first multi-peer piece scheduler.
//
// Spec 2026-10-08 §6 (`Scheduler`), §7 (multi-peer retry), §9 (determinism).
// The scheduler owns the per-piece status array, the `piece_rarest` counter
// (connected peers holding each piece), the claimed-piece owner map, the
// `max_peers` `Peer` slots, and a small ring of recently-seen `PeerAddr`s used
// to skip duplicate connections.
//
// Rarest-first WITHOUT sorting: one bitset bucket per rarest count holds the
// `missing` pieces, and `pickPiece` takes the lowest index in the lowest bucket
// the peer can serve (spec §9 M3 determinism). Per-peer bucket counts let an
// empty bucket be skipped without scanning every piece.
//
// Claim/owner model: a peer holds at most one claimed piece at a time (the M2
// coroutine works on a single `PieceState`). `pickPiece` stashes the choosing
// peer's slot in `pending_owner`; the caller then calls `claim(index)`, which
// marks the piece `requested` and records that slot in `piece_owner` and
// `peer_owned`. There is no suspension between the two calls (both are plain
// functions), so the pairing is deterministic. `release(peer)` is O(1) and
// returns the peer's single owned piece to `missing` (block state is retained;
// the resume sidecar's `partial[]` survives claim/release, spec §7).
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
// Rarest counts run 0..16 (MAX_RUNTIME_PEERS); one bucket per value.
const MAX_BUCKETS: usize = 17;

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
    // One bitset per rarest count (0..MAX_BUCKETS-1) holding only `missing`
    // pieces. `bucket_min[r]` caches the lowest index still in bucket `r`.
    bucket_bits: [17][]u8,
    bucket_min: [17]u32,
    // Per-peer count of missing pieces in each rarest bucket. Lets `pickPiece`
    // skip buckets the peer cannot serve without scanning every piece.
    peer_bucket_counts: []u32,
    // Each peer claims at most one piece; `release` is O(1) via this map.
    peer_owned: []u32,
    seen: [8]tracker.PeerAddr, // recent-address ring (dedupe)
    seen_count: u32,
    seen_next: u32,
};

// Zero-length slices for the empty-piece / empty-peer cases (D2: `[]primitive`
// and fixed arrays of named types only).
var g_empty_bits: [1]u8;
var g_empty_u32: [1]u32;
var g_empty_piece_status: [1]PieceStatus;
var g_empty_peer: [1]peer.Peer;
var g_zero_seen: [8]tracker.PeerAddr;
var g_zero_buckets: [17][]u8;
var g_zero_bucket_min: [17]u32;

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

// --- rarest buckets -------------------------------------------------------

fn bucketGet(s: *Scheduler, r: u32, i: u32) bool {
    var ri: usize = @intCast(usize, r);
    if (ri >= MAX_BUCKETS) return false;
    var bits = s.bucket_bits[ri];
    var byte: usize = @intCast(usize, i / 8);
    if (byte >= bits.len) return false;
    return piece.bitGet(bits, i);
}

fn bucketNextSet(s: *Scheduler, r: u32, start: u32) u32 {
    var n: u32 = @intCast(u32, s.piece_state.len);
    var i: u32 = start;
    while (i < n) : (i += 1) {
        if (bucketGet(s, r, i)) return i;
    }
    return NO_OWNER;
}

fn bucketSet(s: *Scheduler, r: u32, i: u32) void {
    var ri: usize = @intCast(usize, r);
    if (ri >= MAX_BUCKETS) return;
    var bits = s.bucket_bits[ri];
    var byte: usize = @intCast(usize, i / 8);
    if (byte >= bits.len) return;
    piece.bitSet(bits, i);
    if (s.bucket_min[ri] == NO_OWNER or i < s.bucket_min[ri]) s.bucket_min[ri] = i;
}

fn bucketClear(s: *Scheduler, r: u32, i: u32) void {
    var ri: usize = @intCast(usize, r);
    if (ri >= MAX_BUCKETS) return;
    var bits = s.bucket_bits[ri];
    var byte: usize = @intCast(usize, i / 8);
    if (byte >= bits.len) return;
    var sh: u8 = @intCast(u8, 7 - (i % 8));
    var m: u8 = @intCast(u8, 1) << sh;
    bits[byte] = bits[byte] & ~m;
    if (s.bucket_min[ri] == i) s.bucket_min[ri] = bucketNextSet(s, r, i + 1);
}

fn bucketOf(s: *Scheduler, index: u32) u32 {
    var r: u32 = s.piece_rarest[@intCast(usize, index)];
    if (r >= @intCast(u32, MAX_BUCKETS)) r = @intCast(u32, MAX_BUCKETS - 1);
    return r;
}

// Move every active peer's per-bucket count for `index` from `old_r` to
// `new_r`. Called only while the piece is `missing`.
fn movePeerCounts(s: *Scheduler, index: u32, old_r: u32, new_r: u32) void {
    if (old_r == new_r) return;
    var oi: usize = @intCast(usize, old_r);
    var ni: usize = @intCast(usize, new_r);
    if (oi >= MAX_BUCKETS or ni >= MAX_BUCKETS) return;
    for (0..s.peers.len) |q| {
        if (!s.peers[q].active) continue;
        if (!peerHas(&s.peers[q], index)) continue;
        var ci: usize = @intCast(usize, q) * MAX_BUCKETS + oi;
        if (ci < s.peer_bucket_counts.len and s.peer_bucket_counts[ci] > 0) s.peer_bucket_counts[ci] -= 1;
        var cj: usize = @intCast(usize, q) * MAX_BUCKETS + ni;
        if (cj < s.peer_bucket_counts.len) s.peer_bucket_counts[cj] += 1;
    }
}

// Remove/add `index` from/to every active peer's count for its current bucket.
fn removePeerCount(s: *Scheduler, index: u32) void {
    var r: u32 = bucketOf(s, index);
    var ri: usize = @intCast(usize, r);
    for (0..s.peers.len) |q| {
        if (!s.peers[q].active) continue;
        if (!peerHas(&s.peers[q], index)) continue;
        var ci: usize = @intCast(usize, q) * MAX_BUCKETS + ri;
        if (ci < s.peer_bucket_counts.len and s.peer_bucket_counts[ci] > 0) s.peer_bucket_counts[ci] -= 1;
    }
}

fn addPeerCount(s: *Scheduler, index: u32) void {
    var r: u32 = bucketOf(s, index);
    var ri: usize = @intCast(usize, r);
    for (0..s.peers.len) |q| {
        if (!s.peers[q].active) continue;
        if (!peerHas(&s.peers[q], index)) continue;
        var ci: usize = @intCast(usize, q) * MAX_BUCKETS + ri;
        if (ci < s.peer_bucket_counts.len) s.peer_bucket_counts[ci] += 1;
    }
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
        for (ps) |*item, i| {
            item.* = PieceStatus{
                .index = @intCast(u32, i),
                .state = piece.BlockState.missing,
            };
        }
    }

    // `piece_rarest[i]` = connected peers holding bit `i` (all zero initially).
    var rar: []u32 = emptyU32();
    if (n_pieces > 0) {
        var rawr = std.arena.alloc(arena, @intCast(usize, n_pieces) * @sizeOf(u32)) catch return error.OutOfMemory;
        rar = @ptrCast([*]u32, rawr)[0..@intCast(usize, n_pieces)];
        for (rar) |*item| {
            item.* = 0;
        }
    }

    var own: []u32 = emptyU32();
    if (n_pieces > 0) {
        var rawo = std.arena.alloc(arena, @intCast(usize, n_pieces) * @sizeOf(u32)) catch return error.OutOfMemory;
        own = @ptrCast([*]u32, rawo)[0..@intCast(usize, n_pieces)];
        for (own) |*item| {
            item.* = NO_OWNER;
        }
    }

    var mp: u32 = max_peers;
    if (mp > @intCast(u32, MAX_BUCKETS - 1)) mp = @intCast(u32, MAX_BUCKETS - 1);

    // One bitset per rarest count; initially every piece is missing in bucket 0.
    var bset: [17][]u8 = g_zero_buckets;
    var bmin: [17]u32 = g_zero_bucket_min;
    for (0..MAX_BUCKETS) |r| {
        bset[r] = emptyBits();
        bmin[r] = NO_OWNER;
    }
    if (n_pieces > 0) {
        var nbits: usize = (@intCast(usize, n_pieces) + 7) / 8;
        var rawb = std.arena.alloc(arena, MAX_BUCKETS * nbits) catch return error.OutOfMemory;
        var all: []u8 = rawb[0 .. MAX_BUCKETS * nbits];
        for (all) |*item| {
            item.* = 0;
        }
        for (0..MAX_BUCKETS) |r| {
            var start: usize = @intCast(usize, r) * nbits;
            bset[r] = all[start .. start + nbits];
        }
        for (0..n_pieces) |i| {
            piece.bitSet(bset[0], @intCast(u32, i));
        }
        bmin[0] = 0;
    }

    var pbc: []u32 = emptyU32();
    if (mp > 0) {
        var rawc = std.arena.alloc(arena, @intCast(usize, mp) * MAX_BUCKETS * @sizeOf(u32)) catch return error.OutOfMemory;
        pbc = @ptrCast([*]u32, rawc)[0 .. @intCast(usize, mp) * MAX_BUCKETS];
        for (pbc) |*item| {
            item.* = 0;
        }
    }
    var pown: []u32 = emptyU32();
    if (mp > 0) {
        var rawo2 = std.arena.alloc(arena, @intCast(usize, mp) * @sizeOf(u32)) catch return error.OutOfMemory;
        pown = @ptrCast([*]u32, rawo2)[0..@intCast(usize, mp)];
        for (pown) |*item| {
            item.* = NO_OWNER;
        }
    }

    var peers: []peer.Peer = emptyPeers();
    if (mp > 0) {
        var rawp = std.arena.alloc(arena, @intCast(usize, mp) * @sizeOf(peer.Peer)) catch return error.OutOfMemory;
        peers = @ptrCast([*]peer.Peer, rawp)[0..@intCast(usize, mp)];
        for (0..mp) |j| {
            // `ps`/`io` are fully zero-initialised: `saveResume` walks every
            // ACTIVE peer slot and reads `ps` before `peerRun` has acquired a
            // piece (`pieceInit`), so an undefined `ps` would poison-read (and
            // `-fsafe` traps/segfaults on `blocks`). `sock`/`addr`/`hs`/`rhs`/
            // `peer_id`/`read_buf` stay uninitialised until `addPeer`/`peerRun`
            // set them (a struct literal cannot `undefined` a nested named-struct
            // field in Z98 emission).
            var p: peer.Peer = peer.zeroPeer();
            p.active = false;
            p.slot = j;
            p.sched = null;
            p.have_piece = false;
            p.bitfield = emptyBits();
            p.rarest = rar;
            p.sock = @intCast(i32, -1);
            p.encrypted = false;
            p.mse_attempts = 0;
            p.ps = peer.zeroPieceState();
            p.io = peer.zeroPieceIO();
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
        .bucket_bits = bset,
        .bucket_min = bmin,
        .peer_bucket_counts = pbc,
        .peer_owned = pown,
        .seen = g_zero_seen,
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
    var r: usize = 0;
    while (r < MAX_BUCKETS) : (r += 1) {
        var ci: usize = @intCast(usize, p.slot) * MAX_BUCKETS + r;
        if (ci >= s.peer_bucket_counts.len) continue;
        if (s.peer_bucket_counts[ci] == 0) continue;
        var start: u32 = s.bucket_min[r];
        if (start == NO_OWNER) start = 0;
        var n: u32 = @intCast(u32, s.piece_state.len);
        var i: u32 = start;
        while (i < n) : (i += 1) {
            if (!bucketGet(s, @intCast(u32, r), i)) continue;
            if (!peerHas(p, i)) continue;
            if (s.piece_state[@intCast(usize, i)].state != piece.BlockState.missing) continue;
            s.pending_owner = p.slot;
            return i;
        }
    }
    return null;
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
    var old_r: u32 = s.piece_rarest[ui];
    var new_r: u32 = old_r + 1;
    if (new_r >= @intCast(u32, MAX_BUCKETS)) new_r = @intCast(u32, MAX_BUCKETS - 1);
    piece.bitSet(p.bitfield, index);
    s.piece_rarest[ui] = new_r;
    if (s.piece_state[ui].state == piece.BlockState.missing and old_r != new_r) {
        bucketClear(s, old_r, index);
        bucketSet(s, new_r, index);
        movePeerCounts(s, index, old_r, new_r);
    }
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
    var r: u32 = bucketOf(s, index);
    bucketClear(s, r, index);
    removePeerCount(s, index);
    s.piece_state[ui].state = piece.BlockState.requested;
    if (ui < s.piece_owner.len) s.piece_owner[ui] = s.pending_owner;
    if (@intCast(usize, s.pending_owner) < s.peer_owned.len) {
        s.peer_owned[@intCast(usize, s.pending_owner)] = index;
    }
}

// Mark piece `index` verified and clear its owner. Used both by the download
// path (`complete`) and by `main` when seeding resume-verified pieces.
pub fn complete(s: *Scheduler, index: u32) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    if (index >= n) return;
    var ui: usize = @intCast(usize, index);
    var was_missing: bool = s.piece_state[ui].state == piece.BlockState.missing;
    var old_owner: u32 = NO_OWNER;
    if (ui < s.piece_owner.len) {
        old_owner = s.piece_owner[ui];
        s.piece_owner[ui] = NO_OWNER;
    }
    if (old_owner != NO_OWNER and @intCast(usize, old_owner) < s.peer_owned.len) {
        if (s.peer_owned[@intCast(usize, old_owner)] == index) {
            s.peer_owned[@intCast(usize, old_owner)] = NO_OWNER;
        }
    }
    if (was_missing) {
        var r: u32 = bucketOf(s, index);
        bucketClear(s, r, index);
        removePeerCount(s, index);
    }
    s.piece_state[ui].state = piece.BlockState.verified;
}

// Seed a piece already verified from a resume sidecar without going through a
// claim. `complete` already handles the missing -> verified transition.
pub fn markVerified(s: *Scheduler, index: u32) void {
    complete(s, index);
}

// A corrupted piece returns to `missing` (written-through blocks are retained
// in the resume sidecar's `partial[]`), clear of any owner.
pub fn corrupt(s: *Scheduler, index: u32) void {
    var n: u32 = @intCast(u32, s.piece_state.len);
    if (index >= n) return;
    var ui: usize = @intCast(usize, index);
    var was_missing: bool = s.piece_state[ui].state == piece.BlockState.missing;
    var old_owner: u32 = NO_OWNER;
    if (ui < s.piece_owner.len) {
        old_owner = s.piece_owner[ui];
        s.piece_owner[ui] = NO_OWNER;
    }
    if (old_owner != NO_OWNER and @intCast(usize, old_owner) < s.peer_owned.len) {
        if (s.peer_owned[@intCast(usize, old_owner)] == index) {
            s.peer_owned[@intCast(usize, old_owner)] = NO_OWNER;
        }
    }
    s.piece_state[ui].state = piece.BlockState.missing;
    if (!was_missing) {
        var r: u32 = bucketOf(s, index);
        bucketSet(s, r, index);
        addPeerCount(s, index);
    }
}

// Return the single piece claimed by `p` (owner slot) to `missing`, retaining
// its written-through block mask. O(1): a peer never owns more than one piece.
pub fn release(s: *Scheduler, p: *peer.Peer) void {
    var si: usize = @intCast(usize, p.slot);
    if (si < s.peer_owned.len) {
        var idx: u32 = s.peer_owned[si];
        if (idx != NO_OWNER) {
            var ui: usize = @intCast(usize, idx);
            if (ui < s.piece_state.len and s.piece_state[ui].state == piece.BlockState.requested) {
                s.piece_state[ui].state = piece.BlockState.missing;
                if (ui < s.piece_owner.len) s.piece_owner[ui] = NO_OWNER;
                var r: u32 = bucketOf(s, idx);
                bucketSet(s, r, idx);
                addPeerCount(s, idx);
            }
            s.peer_owned[si] = NO_OWNER;
        }
    }
    p.have_piece = false;
}

fn addrSeen(s: *Scheduler, addr: tracker.PeerAddr) bool {
    var n: u32 = @intCast(u32, s.peers.len);
    for (0..n) |i| {
        var ui: usize = @intCast(usize, i);
        if (s.peers[ui].active) {
            if (s.peers[ui].addr.ip_be == addr.ip_be and s.peers[ui].addr.port == addr.port) return true;
        }
    }
    for (0..s.seen_count) |j| {
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
    for (0..n) |i| {
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
            p.encrypted = false;
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
    for (0..n) |i| {
        if (peerHas(p, i)) {
            var ui: usize = @intCast(usize, i);
            if (s.piece_rarest[ui] == 0) {
                // Invariant: a bit is only ever counted via `noteHave`, so a
                // set bit must have a non-zero count. Underflow is a bug.
                unreachable;
            }
            var old_r: u32 = s.piece_rarest[ui];
            var new_r: u32 = old_r - 1;
            s.piece_rarest[ui] = new_r;
            if (s.piece_state[ui].state == piece.BlockState.missing) {
                bucketClear(s, old_r, i);
                bucketSet(s, new_r, i);
                movePeerCounts(s, i, old_r, new_r);
            }
        }
    }
    var si: usize = @intCast(usize, p.slot);
    if (si < s.peer_owned.len) {
        s.peer_owned[si] = NO_OWNER;
    }
    if (si < s.peers.len) {
        for (0..MAX_BUCKETS) |r| {
            var ci: usize = si * MAX_BUCKETS + r;
            if (ci < s.peer_bucket_counts.len) s.peer_bucket_counts[ci] = 0;
        }
    }
    p.active = false;
    p.bitfield = emptyBits();
    p.rarest = emptyU32();
    p.sched = null;
    p.have_piece = false;
    if (s.active_peer_count > 0) s.active_peer_count -= 1;
}
