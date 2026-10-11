// scheduler_test.zig — deterministic unit harness for scheduler.Scheduler.
//
// No wall clock, no randomness: a synthetic 6-piece torrent and two mock peers
// with overlapping availability bitfields exercise the rarest-first selection,
// the claim/release owner model, duplicate-address skipping and slot reuse.
//
// Asserts:
//   1. `pickPiece` prefers the rarer piece and ties break by lowest index;
//   2. `pickPiece` never returns a `requested` (already claimed) piece;
//   3. `release(peer)` returns the peer's claimed pieces to `missing`;
//   4. `addPeer` skips a recently-seen `PeerAddr` and a freed slot is reused.
//
// Build (binding recipe), entry is this file:
//   mkdir -p out
//   timeout 120 /tmp/z9_m0_seed/zig1_5_clean -fsafe -o out testdata/scheduler_test.zig
//   sh out/build_target.sh linux out/prog
//   ./out/prog
//
// Lives under testdata/ so the example entry stays main.zig (corpus rule).

const std = @import("std");
const scheduler = @import("../scheduler.zig");
const peer = @import("../peer.zig");
const torrent = @import("../torrent.zig");
const tracker = @import("../tracker.zig");

var g_arena_buf: [1048576]u8 = undefined;
var g_hashes: [120]u8 = undefined;

fn fail(msg: []const u8) void {
    var p: []const u8 = "scheduler_test: FAIL: ";
    std.io.write(p);
    std.io.write(msg);
    var nl: []const u8 = "\n";
    std.io.write(nl);
    std.os.exit(1);
}

fn checkPick(s: *scheduler.Scheduler, p: *peer.Peer, want: u32, label: []const u8) void {
    var got: ?u32 = scheduler.pickPiece(s, p);
    if (got) |g| {
        if (g != want) fail(label);
        scheduler.claim(s, g);
    } else {
        fail(label);
    }
}

fn checkNull(s: *scheduler.Scheduler, p: *peer.Peer, label: []const u8) void {
    var got: ?u32 = scheduler.pickPiece(s, p);
    if (got) |g| {
        _ = g;
        fail(label);
    }
}

fn checkRarest(s: *scheduler.Scheduler, i: usize, want: u32, label: []const u8) void {
    if (s.piece_rarest[i] != want) fail(label);
}

// After A has {0,1,2,3} and B has {2,3}, counts are [1,1,2,2,0,0].
fn checkCounts(s: *scheduler.Scheduler, label: []const u8) void {
    checkRarest(s, 0, 1, label);
    checkRarest(s, 1, 1, label);
    checkRarest(s, 2, 2, label);
    checkRarest(s, 3, 2, label);
    checkRarest(s, 4, 0, label);
    checkRarest(s, 5, 0, label);
}

fn makeTorrent() torrent.Torrent {
    var ih: [20]u8 = undefined;
    var z: usize = 0;
    while (z < 20) : (z += 1) ih[z] = 0;
    z = 0;
    while (z < 120) : (z += 1) g_hashes[z] = 0;
    var alist: [8][]const u8 = undefined;
    var e: []const u8 = "";
    z = 0;
    while (z < 8) : (z += 1) alist[z] = e;
    return torrent.Torrent{
        .announce = e,
        .announce_list = alist,
        .announce_count = 0,
        .info_hash = ih,
        .name = "sched",
        .piece_length = 1024,
        .piece_hashes = g_hashes[0..],
        .total_length = 6144,
    };
}

pub fn main(argc: i32, argv: [*][*]u8) void {
    _ = argc;
    _ = argv;

    var arena: std.arena.Arena = std.arena.init(g_arena_buf[0..]);
    var t: torrent.Torrent = makeTorrent();

    var s: scheduler.Scheduler = scheduler.schedulerInit(&arena, t, 4) catch {
        fail("schedulerInit");
        return;
    };
    if (s.piece_state.len != 6) fail("n_pieces != 6");

    var addr_a: tracker.PeerAddr = tracker.PeerAddr{ .ip_be = 1, .port = 1000 };
    var addr_b: tracker.PeerAddr = tracker.PeerAddr{ .ip_be = 2, .port = 2000 };
    var addr_c: tracker.PeerAddr = tracker.PeerAddr{ .ip_be = 3, .port = 3000 };
    var addr_d: tracker.PeerAddr = tracker.PeerAddr{ .ip_be = 4, .port = 4000 };

    if (!scheduler.addPeer(&s, addr_a)) fail("addPeer A");
    if (!scheduler.addPeer(&s, addr_b)) fail("addPeer B");
    if (s.active_peer_count != 2) fail("active != 2");

    var pa: *peer.Peer = &s.peers[0];
    var pb: *peer.Peer = &s.peers[1];

    // Correctly-sized zeroed availability bitfields: the peer loop allocates
    // these; the harness must provide storage for the shared `noteHave` path.
    var bf_a: [1]u8 = [1]u8{0};
    var bf_b: [1]u8 = [1]u8{0};
    pa.bitfield = bf_a[0..];
    pb.bitfield = bf_b[0..];

    // Drive the REAL increment path: A has {0,1,2,3}, B also has {2,3}.
    scheduler.noteHave(&s, pa, 0);
    scheduler.noteHave(&s, pa, 1);
    scheduler.noteHave(&s, pa, 2);
    scheduler.noteHave(&s, pa, 3);
    scheduler.noteHave(&s, pb, 2);
    scheduler.noteHave(&s, pb, 3);
    scheduler.noteHave(&s, pa, 2); // duplicate: must not double-count

    // piece_rarest = [1,1,2,2,0,0]: 0/1 tie at 1, 2/3 tie at 2.
    checkCounts(&s, "piece_rarest after noteHave");

    // Test 1: rarest-first (count 1 before count 2) with lowest-index tie-break
    // at both equal pairs (0 before 1; 2 before 3).
    checkPick(&s, pa, 0, "tie-break: index 0 over 1");
    checkPick(&s, pa, 1, "tie-break: index 1 next");
    checkPick(&s, pa, 2, "tie-break: index 2 over 3");
    checkPick(&s, pa, 3, "tie-break: index 3 next");
    checkNull(&s, pa, "A has no missing piece left");

    // Test 2: B's only pieces (2,3) are `requested` -> never returned.
    checkNull(&s, pb, "pickPiece returned a requested piece");

    // Test 3: release returns A's claimed pieces to `missing`.
    scheduler.release(&s, pa);
    if (s.piece_state[0].state != .missing) fail("release did not free piece 0");
    if (s.piece_state[2].state != .missing) fail("release did not free piece 2");
    checkPick(&s, pb, 2, "B now picks released tie-lowest piece 2");
    scheduler.release(&s, pb);

    // Test 4: removePeer decrements the counts for the peer's set bits.
    scheduler.removePeer(&s, pa);
    if (s.active_peer_count != 1) fail("removePeer did not drop active count");
    if (s.peers[0].active) fail("removed slot still active");
    checkRarest(&s, 0, 0, "A decrement piece 0");
    checkRarest(&s, 1, 0, "A decrement piece 1");
    checkRarest(&s, 2, 1, "A decrement piece 2");
    checkRarest(&s, 3, 1, "A decrement piece 3");
    scheduler.removePeer(&s, pb);
    if (s.active_peer_count != 0) fail("active != 0 after removing B");
    checkRarest(&s, 2, 0, "B decrement piece 2");
    checkRarest(&s, 3, 0, "B decrement piece 3");

    // Test 5: duplicate recently-seen address is skipped.
    if (scheduler.addPeer(&s, addr_a)) fail("duplicate A accepted");

    // Test 6: freed slots are reused (both A and B are gone; slot 0 first).
    if (!scheduler.addPeer(&s, addr_c)) fail("addPeer C (reuse)");
    if (!s.peers[0].active) fail("slot 0 not reused");
    if (s.peers[0].addr.ip_be != addr_c.ip_be) fail("slot 0 has wrong address");

    // C holds nothing; D, E and F take the remaining free slots.
    if (!scheduler.addPeer(&s, addr_d)) fail("addPeer D");
    if (!scheduler.addPeer(&s, tracker.PeerAddr{ .ip_be = 5, .port = 5000 })) fail("addPeer E");
    if (!scheduler.addPeer(&s, tracker.PeerAddr{ .ip_be = 6, .port = 6000 })) fail("addPeer F");
    if (s.active_peer_count != 4) fail("active != 4 after fill");
    if (scheduler.addPeer(&s, tracker.PeerAddr{ .ip_be = 7, .port = 7000 })) fail("full slot table accepted peer");

    var p: []const u8 = "scheduler_test: PASS rarest-first+ties + counts + claim/release + dedupe + slot reuse\n";

    std.io.write(p);
    std.os.exit(0);
}
